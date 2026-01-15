ARG SUI_LOCALNET_VERSION=latest

FROM ghcr.io/gfusee/sui-localnet/sui-binary:${SUI_LOCALNET_VERSION} AS sui-binary
FROM ghcr.io/gfusee/sui-localnet/walrus-binary:${SUI_LOCALNET_VERSION} AS walrus-binary

FROM ubuntu:24.04 AS runner

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libssl3 \
    ca-certificates \
    curl \
    jq \
    git \
    tmux \
    && rm -rf /var/lib/apt/lists/*

COPY --from=sui-binary /usr/local/bin/sui /usr/local/bin/sui
COPY --from=walrus-binary /build/walrus /walrus
COPY local-testbed.sh /walrus/scripts/local-testbed.sh
COPY run.sh run.sh
COPY wait_for_localnet.sh wait_for_localnet.sh
COPY empty_sui_config.yaml /root/.sui/sui_config/client.yaml
COPY faucet.sh faucet.sh

RUN chmod +x /walrus/scripts/local-testbed.sh
RUN chmod +x run.sh
RUN chmod +x wait_for_localnet.sh
RUN chmod +x faucet.sh

ENTRYPOINT ["./run.sh", "http://localnet:9000"]
