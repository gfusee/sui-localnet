#!/usr/bin/env bash

# Usage: ./request_gas.sh <hex_address>

HEX_ADDRESS="$1"

if [ -z "$HEX_ADDRESS" ]; then
  echo "Usage: $0 <hex_address>"
  exit 1
fi

curl -X POST http://localnet:9123/v2/gas \
  -H "Content-Type: application/json" \
  -d "{\"FixedAmountRequest\":{\"recipient\":\"$HEX_ADDRESS\"}}"

