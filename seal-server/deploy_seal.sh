#!/usr/bin/env bash
set -euo pipefail

NODE_URL="${NODE_URL:-http://localnet:9000}"

# Get the localnet chain ID and add environment declaration if needed.
CHAIN_ID="$(curl -s -X POST "$NODE_URL" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"sui_getChainIdentifier","params":[]}' \
  | jq -r '.result')"

rm -f /seal/move/seal/Published.toml
if ! grep -q '\[environments\]' /seal/move/seal/Move.toml; then
    printf '\n[environments]\nlocalnet = "%s"\n' "$CHAIN_ID" >> /seal/move/seal/Move.toml
fi

publish_json() {
  local dir="$1"
  ( cd "$dir" && sui client test-publish --build-env localnet --json ) | awk '
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

SEAL_JSON="$(publish_json "/seal/move/seal")"

PACKAGE_ID="$(
  jq -r '[.objectChanges[] | select(.type=="published")] | last | .packageId' \
    <<< "$SEAL_JSON"
)"

echo "$PACKAGE_ID"
