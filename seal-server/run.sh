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

./wait_for_localnet.sh http://localnet:9000

sui client new-address ed25519
sui client new-env --alias localnet --rpc http://localnet:9000
./faucet.sh "$(sui client active-address)"

SEAL_PACKAGE_ID="$(./deploy_seal.sh)"

echo "Seal package id: $SEAL_PACKAGE_ID"

# Generate keys
OUTPUT=$(seal-cli genkey)

# Print the full output
echo "$OUTPUT"

# Extract the Master key value
MASTER_KEY=$(echo "$OUTPUT" | grep -oP '(?<=Master key:\s)0x[0-9a-fA-F]+')
PUBLIC_KEY=$(echo "$OUTPUT" | grep -oP '(?<=Public key:\s)0x[0-9a-fA-F]+')

# Use SEAL_SERVER_URL if defined, otherwise default to localhost:9005
URL="${SEAL_SERVER_URL:-http://localhost:9005}"
echo "Using Seal server URL: $URL"

KEY_SERVER_JSON="$(sui client ptb \
  --move-call $SEAL_PACKAGE_ID::key_server::create_and_transfer_v1 '"FirstServer"' "\"$URL\"" 0 $(to_vector "$PUBLIC_KEY") \
  --json
)"

KEY_SERVER_OBJECT_ID="$(
  jq -r '.objectChanges[]
         | select(.type=="created" and (.objectType | endswith("::key_server::KeyServer")))
         | .objectId' \
    <<< "$KEY_SERVER_JSON"
)"

echo "Seal package ID: $SEAL_PACKAGE_ID"
echo "Key server ID: $KEY_SERVER_OBJECT_ID"
echo "Master key: $MASTER_KEY"

# Run the key-server command
MASTER_KEY="$MASTER_KEY" NETWORK="custom" NODE_URL="http://localnet:9000" KEY_SERVER_OBJECT_ID="$KEY_SERVER_OBJECT_ID" key-server
