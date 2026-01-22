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

NODE_URL="${NODE_URL:-http://localnet:9000}"
echo "Using node URL: $NODE_URL"

FAUCET_URL="${FAUCET_URL:-http://localnet:9123}"
echo "Using faucet URL: $FAUCET_URL"

./wait_for_localnet.sh $NODE_URL

sui client new-address ed25519
sui client new-env --alias localnet --rpc $NODE_URL
./faucet.sh "$FAUCET_URL" "$(sui client active-address)"

WALRUS_ADDRESS="${WALRUS_ADDRESS:-localhost}"
echo "Using Walrus address: $WALRUS_ADDRESS"

cd /walrus
scripts/local-testbed.sh -n "http://localnet:9000;http://localnet:9123/v2/gas" -a $WALRUS_ADDRESS -s 200 -L 0.0.0.0