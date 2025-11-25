#!/bin/sh

if [ -n "$(ls -A "/home/user/localnet-config")" ]; then
    echo "-> Running with persistent configuration"
    CMD="RUST_LOG="off,sui_node=info" sui start --with-faucet --network.config=/home/user/localnet-config"

    if [ -n "$WITH_GRAPHQL" ]; then
        echo "-> Running with GraphQL"
        CMD="$CMD --with-graphql"
    fi

    if [ -n "$WITH_INDEXER" ]; then
        echo "-> Running with indexer"
        CMD="$CMD --with-indexer"
    fi

    exec sh -c "$CMD"
else
    echo "-> Running with no persistence"
    exec sui start --with-faucet --force-regenesis
fi