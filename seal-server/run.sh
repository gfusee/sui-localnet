#!/usr/bin/env bash
set -euo pipefail

# Generate keys
OUTPUT=$(seal-cli genkey)

# Print the full output
echo "$OUTPUT"

# Extract the Master key value
MASTER_KEY=$(echo "$OUTPUT" | grep -oP '(?<=Master key:\s)0x[0-9a-fA-F]+')

# Export the Master key as an environment variable
export MASTER_KEY
echo "Exported MASTER_KEY=$MASTER_KEY"

./wait_for_localnet.sh http://localnet:9000

# Run the key-server command
key-server