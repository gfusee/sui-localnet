#!/bin/sh

if [ -n "$(ls -A "$dir")" ]; then
    CMD="sui start --with-faucet --network.config=/Users/quentin/WebstormProjects/sui-poker/localnet-config"

    if [ -n "$WITH_GRAPHQL" ]; then
        CMD="$CMD --with-graphql"
    fi

    if [ -n "$WITH_INDEXER" ]; then
        CMD="$CMD --with-indexer"
    fi

    exec sh -c "$CMD"
else
    exec sui start --with-faucet --force-regenesis
fi