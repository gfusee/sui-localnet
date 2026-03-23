#!/usr/bin/env bash
set -euo pipefail

SEAL_MODE="${SEAL_MODE:-independent}"

if [ "$SEAL_MODE" = "committee" ]; then
    exec ./run_committee.sh
else
    exec ./run_independent.sh
fi
