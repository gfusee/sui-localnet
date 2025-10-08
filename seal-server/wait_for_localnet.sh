#!/usr/bin/env bash
set -euo pipefail

echo "[DEBUG] Script started with args: $@"

# Check that an RPC URL was provided
if [ $# -lt 1 ]; then
  echo "[ERROR] Usage: $0 <RPC_URL>"
  exit 1
fi

RPC_URL="$1"
echo "[DEBUG] RPC_URL set to: $RPC_URL"

echo "Waiting for RPC endpoint at $RPC_URL to return a response with 'data' defined..."

i=0
while true; do
  i=$((i+1))
  echo "[DEBUG] Loop iteration $i"

  echo "[DEBUG] Running curl..."
  RESPONSE=$(curl -s -X POST "$RPC_URL" \
    -H "Content-Type: application/json" \
    -d '{
      "jsonrpc": "2.0",
      "id": 1,
      "method": "sui_getObject",
      "params": ["0x2"]
    }' || echo "")

  echo "[DEBUG] Curl exit code: $?"
  echo "[DEBUG] Raw response: '$RESPONSE'"

  if [ -z "$RESPONSE" ]; then
    echo "⚠️  Cannot reach $RPC_URL yet. Retrying in 5 seconds..."
    sleep 5
    continue
  fi

  echo "[DEBUG] Running jq..."
  HAS_DATA=$(echo "$RESPONSE" | jq -e '.result.data != null' 2>/dev/null || echo "false")
  echo "[DEBUG] jq result: '$HAS_DATA'"

  if [ "$HAS_DATA" = "true" ]; then
    echo "✅ RPC is ready. 'data' field is present:"
    echo "$RESPONSE" | jq
    break
  else
    echo "⏳ Still waiting for 'data'... retrying in 5 seconds."
    sleep 5
  fi
done

echo "[DEBUG] Exiting normally."

