ARG SUI_LOCALNET_VERSION=latest

FROM ghcr.io/gfusee/sui-localnet/sui-binary:${SUI_LOCALNET_VERSION} AS sui-binary
FROM ghcr.io/gfusee/sui-localnet/seal-binary:${SUI_LOCALNET_VERSION} AS seal-binary

FROM ubuntu:24.04 AS runner

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libssl3 \
    ca-certificates \
    curl \
    jq \
    git \
    && rm -rf /var/lib/apt/lists/*

COPY --from=sui-binary /usr/local/bin/sui /usr/local/bin/sui
COPY --from=seal-binary /seal/move/seal /seal/move/seal
COPY --from=seal-binary /seal/move/committee /seal/move/committee
COPY --from=seal-binary /usr/local/bin/seal-cli /usr/local/bin/seal-cli
COPY --from=seal-binary /usr/local/bin/key-server /usr/local/bin/key-server
COPY --from=seal-binary /usr/local/bin/aggregator-server /usr/local/bin/aggregator-server
COPY --from=seal-binary /usr/local/bin/seal-keygen /usr/local/bin/seal-keygen
COPY run.sh run.sh
COPY run_independent.sh run_independent.sh
COPY run_committee.sh run_committee.sh
COPY wait_for_localnet.sh wait_for_localnet.sh
COPY empty_sui_config.yaml /root/.sui/sui_config/client.yaml
COPY faucet.sh faucet.sh
COPY deploy_seal.sh deploy_seal.sh
COPY deploy_committee.sh deploy_committee.sh

RUN chmod +x run.sh
RUN chmod +x run_independent.sh
RUN chmod +x run_committee.sh
RUN chmod +x wait_for_localnet.sh
RUN chmod +x faucet.sh
RUN chmod +x deploy_seal.sh
RUN chmod +x deploy_committee.sh

ENTRYPOINT ["./run.sh", "http://localnet:9000"]
