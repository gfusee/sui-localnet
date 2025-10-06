FROM debian:bookworm-slim AS runner

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libssl3 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=sui-binary /usr/local/bin/sui /usr/local/bin/sui
COPY --from=seal-binary /usr/local/bin/seal-cli /usr/local/bin/seal-cli
COPY --from=seal-binary /usr/local/bin/key-server /usr/local/bin/key-server
COPY run.sh run.sh

ENTRYPOINT ["run.sh"]
