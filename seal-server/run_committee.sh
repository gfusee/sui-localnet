#!/usr/bin/env bash
set -euo pipefail

to_vector() {
    local hex=${1#0x}
    local -a parts=()
    [[ $(( ${#hex} % 2 )) -ne 0 ]] && hex="0$hex"
    for ((i=0; i<${#hex}; i+=2)); do
        parts+=("0x${hex:i:2}")
    done
    echo "vector[${parts[*]}]" | sed 's/ /, /g'
}

# Strip JSON output from sui client commands (skip non-JSON preamble lines).
strip_to_json() {
    awk '
    BEGIN { found=0 }
    {
      if (!found) {
        pos = index($0, "{")
        if (pos) {
          found=1
          print substr($0, pos)
        }
        next
      }
      print
    }
  '
}

COMMITTEE_SIZE="${SEAL_COMMITTEE_SIZE:-3}"
THRESHOLD="${SEAL_COMMITTEE_THRESHOLD:-2}"
NODE_URL="${NODE_URL:-http://localnet:9000}"
FAUCET_URL="${FAUCET_URL:-http://localnet:9123}"
SEAL_SERVER_URL="${SEAL_SERVER_URL:-http://localhost:2024}"
BASE_PORT=9010

echo "=== Seal Committee Mode ==="
echo "Committee size: $COMMITTEE_SIZE"
echo "Threshold: $THRESHOLD"
echo "Node URL: $NODE_URL"

# ============================================================
# Phase 0: Wait for localnet and create addresses
# ============================================================
echo ""
echo "=== Phase 0: Setup ==="

./wait_for_localnet.sh "$NODE_URL"

# Create first address (coordinator) and set up localnet env.
sui client new-address ed25519
sui client new-env --alias localnet --rpc "$NODE_URL"
COORDINATOR_ADDR="$(sui client active-address)"
./faucet.sh "$FAUCET_URL" "$COORDINATOR_ADDR"
echo "Coordinator: $COORDINATOR_ADDR"

# Create member addresses.
declare -a MEMBER_ADDRS
for ((i=0; i<COMMITTEE_SIZE; i++)); do
    RAW="$(sui client new-address ed25519)"
    ADDR="$(echo "$RAW" | grep -oP '0x[0-9a-fA-F]{64}')"
    ./faucet.sh "$FAUCET_URL" "$ADDR"
    MEMBER_ADDRS+=("$ADDR")
    echo "Member $i: $ADDR"
done

# ============================================================
# Phase 1: Deploy Move packages
# ============================================================
echo ""
echo "=== Phase 1: Deploy Move packages ==="

# Switch back to coordinator for publishing.
sui client switch --address "$COORDINATOR_ADDR"

DEPLOY_JSON="$(./deploy_committee.sh)"
SEAL_PKG_ID="$(echo "$DEPLOY_JSON" | jq -r '.seal_package_id')"
COMMITTEE_PKG_ID="$(echo "$DEPLOY_JSON" | jq -r '.committee_package_id')"
UPGRADE_CAP_ID="$(echo "$DEPLOY_JSON" | jq -r '.upgrade_cap_id')"

echo "Seal package: $SEAL_PKG_ID"
echo "Committee package: $COMMITTEE_PKG_ID"
echo "UpgradeCap: $UPGRADE_CAP_ID"

# ============================================================
# Phase 2: Generate threshold keys
# ============================================================
echo ""
echo "=== Phase 2: Generate threshold keys ==="

KEYGEN_JSON="$(seal-keygen -t "$THRESHOLD" -n "$COMMITTEE_SIZE")"
PUBLIC_KEY="$(echo "$KEYGEN_JSON" | jq -r '.public_key')"
G1_GEN="$(echo "$KEYGEN_JSON" | jq -r '.g1_generator')"
G2_GEN="$(echo "$KEYGEN_JSON" | jq -r '.g2_generator')"

echo "Public key: $PUBLIC_KEY"

declare -a MASTER_SHARES
declare -a PARTIAL_PKS
for ((i=0; i<COMMITTEE_SIZE; i++)); do
    MASTER_SHARES+=("$(echo "$KEYGEN_JSON" | jq -r ".members[$i].master_share")")
    PARTIAL_PKS+=("$(echo "$KEYGEN_JSON" | jq -r ".members[$i].partial_pk")")
done

# ============================================================
# Phase 3: Initialize committee on-chain
# ============================================================
echo ""
echo "=== Phase 3: Initialize committee ==="

sui client switch --address "$COORDINATOR_ADDR"

# Build the members vector argument.
MEMBERS_VEC="vector["
for ((i=0; i<COMMITTEE_SIZE; i++)); do
    [[ $i -gt 0 ]] && MEMBERS_VEC+=", "
    MEMBERS_VEC+="@${MEMBER_ADDRS[$i]}"
done
MEMBERS_VEC+="]"

INIT_JSON="$(sui client ptb \
  --move-call "${COMMITTEE_PKG_ID}::seal_committee::init_committee" \
    "@${UPGRADE_CAP_ID}" "${THRESHOLD}u16" "$MEMBERS_VEC" \
  --json \
  | strip_to_json
)"

COMMITTEE_ID="$(
  jq -r '.objectChanges[]
         | select(.type=="created" and (.objectType | contains("::seal_committee::Committee")))
         | .objectId' \
    <<< "$INIT_JSON"
)"

echo "Committee ID: $COMMITTEE_ID"

# ============================================================
# Phase 4: Register members
# ============================================================
echo ""
echo "=== Phase 4: Register members ==="

ENC_PK_VEC="$(to_vector "$G1_GEN")"
SIGNING_PK_VEC="$(to_vector "$G2_GEN")"

for ((i=0; i<COMMITTEE_SIZE; i++)); do
    sui client switch --address "${MEMBER_ADDRS[$i]}"
    MEMBER_PORT=$((BASE_PORT + i))

    echo "Registering member $i (${MEMBER_ADDRS[$i]}) on port $MEMBER_PORT..."

    sui client ptb \
      --move-call "${COMMITTEE_PKG_ID}::seal_committee::register" \
        "@${COMMITTEE_ID}" $ENC_PK_VEC $SIGNING_PK_VEC \
        "\"http://localhost:${MEMBER_PORT}\"" "\"member${i}\"" \
      --json \
      | strip_to_json > /dev/null

    echo "  Registered member $i"
done

# ============================================================
# Phase 5: Propose and finalize
# ============================================================
echo ""
echo "=== Phase 5: Propose and finalize ==="

# Build partial_pks vector of vectors.
PARTIAL_PKS_VEC="vector["
for ((i=0; i<COMMITTEE_SIZE; i++)); do
    [[ $i -gt 0 ]] && PARTIAL_PKS_VEC+=", "
    PARTIAL_PKS_VEC+="$(to_vector "${PARTIAL_PKS[$i]}")"
done
PARTIAL_PKS_VEC+="]"

PK_VEC="$(to_vector "$PUBLIC_KEY")"

# Dummy 32-byte messages hash (all zeros).
DUMMY_HASH="0x0000000000000000000000000000000000000000000000000000000000000000"
HASH_VEC="$(to_vector "$DUMMY_HASH")"

KEY_SERVER_OBJECT_ID=""
for ((i=0; i<COMMITTEE_SIZE; i++)); do
    sui client switch --address "${MEMBER_ADDRS[$i]}"

    echo "Member $i proposing..."

    PROPOSE_JSON="$(sui client ptb \
      --move-call "${COMMITTEE_PKG_ID}::seal_committee::propose" \
        "@${COMMITTEE_ID}" "$PARTIAL_PKS_VEC" $PK_VEC $HASH_VEC \
      --json \
      | strip_to_json
    )"

    # On the last proposal, finalization creates the KeyServer object.
    CREATED_KS="$(
      jq -r '.objectChanges[]
             | select(.type=="created" and (.objectType | endswith("::key_server::KeyServer")))
             | .objectId // empty' \
        <<< "$PROPOSE_JSON"
    )"

    if [ -n "$CREATED_KS" ]; then
        KEY_SERVER_OBJECT_ID="$CREATED_KS"
        echo "  KeyServer created: $KEY_SERVER_OBJECT_ID"
    else
        echo "  Proposed (awaiting more approvals)"
    fi
done

if [ -z "$KEY_SERVER_OBJECT_ID" ]; then
    echo "ERROR: KeyServer was not created after all proposals"
    exit 1
fi

echo ""
echo "=== Committee finalized ==="
echo "Key server object: $KEY_SERVER_OBJECT_ID"

# ============================================================
# Phase 6: Write output
# ============================================================
echo ""
echo "=== Phase 6: Write output ==="

mkdir -p /shared

cat <<EOF > /shared/seal.json
{
  "seal_package_id": "$SEAL_PKG_ID",
  "key_server_object_id": "$KEY_SERVER_OBJECT_ID",
  "public_key": "$PUBLIC_KEY",
  "mode": "committee",
  "committee_size": $COMMITTEE_SIZE,
  "threshold": $THRESHOLD,
  "seal_server_url": "$SEAL_SERVER_URL"
}
EOF

echo "Wrote /shared/seal.json"

# ============================================================
# Phase 7: Start key servers
# ============================================================
echo ""
echo "=== Phase 7: Start key servers ==="

mkdir -p /config

for ((i=0; i<COMMITTEE_SIZE; i++)); do
    MEMBER_PORT=$((BASE_PORT + i))
    METRICS_PORT=$((9190 + i))

    cat <<YAML > /config/key-server-${i}.yaml
network: !Devnet
  seal_package: '${SEAL_PKG_ID}'
node_url: '${NODE_URL}'
server_mode: !Committee
  member_address: '${MEMBER_ADDRS[$i]}'
  key_server_obj_id: '${KEY_SERVER_OBJECT_ID}'
  committee_state: !Active
metrics_host_port: ${METRICS_PORT}
YAML

    echo "Starting key-server $i on port $MEMBER_PORT..."
    CONFIG_PATH="/config/key-server-${i}.yaml" \
      MASTER_SHARE_V0="${MASTER_SHARES[$i]}" \
      PORT="$MEMBER_PORT" \
      key-server &

    sleep 1
done

# ============================================================
# Phase 8: Start aggregator
# ============================================================
echo ""
echo "=== Phase 8: Start aggregator ==="

# Build api_credentials YAML block.
API_CREDS=""
for ((i=0; i<COMMITTEE_SIZE; i++)); do
    API_CREDS+="  member${i}:
    api_key_name: x-api-key
    api_key: localnet
"
done

cat <<YAML > /config/aggregator.yaml
network: !Devnet
  seal_package: '${SEAL_PKG_ID}'
node_url: '${NODE_URL}'
key_server_object_id: '${KEY_SERVER_OBJECT_ID}'
api_credentials:
${API_CREDS}
YAML

echo "Starting aggregator on port 2024..."
CONFIG_PATH="/config/aggregator.yaml" PORT=2024 aggregator-server
