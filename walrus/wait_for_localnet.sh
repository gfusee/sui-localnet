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
RPC_BASE_URL=$(echo "$RPC_URL" | sed -E 's#(https?://[^/:]+).*#\1#')
GAS_URL="${RPC_BASE_URL}:9123/v2/gas"
echo "[DEBUG] GAS_URL set to: $GAS_URL"

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

echo "Waiting for gas endpoint at $GAS_URL to return a successful response..."

i=0
while true; do
  i=$((i+1))
  echo "[DEBUG] Gas loop iteration $i"

  echo "[DEBUG] Running gas curl..."
  GAS_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$GAS_URL" \
    -H "Content-Type: application/json" \
    -d '{"FixedAmountRequest":{"recipient":"0x0000000000000000000000000000000000000000000000000000000000000002"}}' || echo "")

  echo "[DEBUG] Gas curl exit code: $?"
  echo "[DEBUG] Raw gas response: '$GAS_RESPONSE'"

  if [ -z "$GAS_RESPONSE" ]; then
    echo "⚠️  Cannot reach $GAS_URL yet. Retrying in 5 seconds..."
    sleep 5
    continue
  fi

  GAS_BODY=$(printf "%s" "$GAS_RESPONSE" | sed '$d')
  GAS_CODE=$(printf "%s" "$GAS_RESPONSE" | tail -n 1)
  echo "[DEBUG] Gas HTTP code: '$GAS_CODE'"

  if [ "$GAS_CODE" = "200" ] || [ "$GAS_CODE" = "201" ]; then
    echo "✅ Gas endpoint is ready. Response:"
    echo "$GAS_BODY"
    break
  else
    echo "⏳ Gas endpoint not ready (HTTP $GAS_CODE). Retrying in 5 seconds."
    sleep 5
  fi
done

echo "[DEBUG] Exiting normally."
