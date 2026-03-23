#!/usr/bin/env bash
set -euo pipefail

# Publishes the seal package first, then the committee package.
# The seal ephemeral published file (Pub.localnet.toml) is created in /seal/move/seal/
# and committee resolves it via its local dependency path "../seal".

NODE_URL="${NODE_URL:-http://localnet:9000}"

# Get the localnet chain ID for the environment declaration.
CHAIN_ID="$(curl -s -X POST "$NODE_URL" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"sui_getChainIdentifier","params":[]}' \
  | jq -r '.result')"

echo "Chain ID: $CHAIN_ID" >&2

# Remove any existing Published.toml to allow fresh publish.
rm -f /seal/move/seal/Published.toml
rm -f /seal/move/committee/Published.toml

# Add [environments] section to both Move.toml files.
if ! grep -q '\[environments\]' /seal/move/seal/Move.toml; then
    printf '\n[environments]\nlocalnet = "%s"\n' "$CHAIN_ID" >> /seal/move/seal/Move.toml
fi

if ! grep -q '\[environments\]' /seal/move/committee/Move.toml; then
    printf '\n[environments]\nlocalnet = "%s"\n' "$CHAIN_ID" >> /seal/move/committee/Move.toml
fi

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

# Step 1: Publish the seal package from its directory.
echo "Publishing seal package..." >&2
SEAL_JSON="$( cd /seal/move/seal && sui client test-publish --build-env localnet --json 2>&1 | strip_to_json )"

SEAL_PACKAGE_ID="$(
  jq -r '[.objectChanges[] | select(.type=="published")] | last | .packageId' \
    <<< "$SEAL_JSON"
)"
echo "Seal package: $SEAL_PACKAGE_ID" >&2

# Step 2: Publish the committee package from its directory.
# Copy the seal ephemeral file to the committee directory so the resolver finds it.
cp /seal/move/seal/Pub.localnet.toml /seal/move/committee/Pub.localnet.toml
echo "Publishing committee package..." >&2
COMMITTEE_JSON="$( cd /seal/move/committee && sui client test-publish --build-env localnet --json 2>&1 | strip_to_json )"

COMMITTEE_PACKAGE_ID="$(
  jq -r '[.objectChanges[] | select(.type=="published")] | last | .packageId' \
    <<< "$COMMITTEE_JSON"
)"

# Extract the UpgradeCap object ID.
UPGRADE_CAP_ID="$(
  jq -r '.objectChanges[]
         | select(.type=="created" and (.objectType | contains("UpgradeCap")))
         | .objectId' \
    <<< "$COMMITTEE_JSON"
)"

echo "Committee package: $COMMITTEE_PACKAGE_ID" >&2
echo "UpgradeCap: $UPGRADE_CAP_ID" >&2

# Output as JSON for the caller to parse.
cat <<EOF
{
  "seal_package_id": "$SEAL_PACKAGE_ID",
  "committee_package_id": "$COMMITTEE_PACKAGE_ID",
  "upgrade_cap_id": "$UPGRADE_CAP_ID"
}
EOF
