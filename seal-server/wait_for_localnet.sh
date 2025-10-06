#!/usr/bin/env bash
set -euo pipefail

# Check that an RPC URL was provided
if [ $# -lt 1 ]; then
  echo "Usage: $0 <RPC_URL>"
  exit 1
fi

RPC_URL="$1"

echo "Waiting for RPC endpoint at $RPC_URL to return a response with 'data' defined..."

while true; do
  RESPONSE=$(curl -s -X POST "$RPC_URL" \
    -H "Content-Type: application/json" \
    -d '{
      "jsonrpc": "2.0",
      "id": 1,
      "method": "sui_getObject",
      "params": ["0x2"]
    }')

  # Check if "data" field is present and not null
  HAS_DATA=$(echo "$RESPONSE" | jq -e '.result.data != null' || echo "false")

  if [ "$HAS_DATA" = "true" ]; then
    echo "✅ RPC is ready. 'data' field is present:"
    echo "$RESPONSE" | jq
    break
  else
    echo "⏳ Still waiting for 'data'... retrying in 5 seconds."
    sleep 5
  fi
done
