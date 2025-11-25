ARG SUI_LOCALNET_VERSION=latest

FROM ghcr.io/gfusee/sui-localnet/sui-binary:${SUI_LOCALNET_VERSION} AS sui-binary

FROM ubuntu:24.04 AS runner

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libssl3 \
    ca-certificates \
    postgresql-common

RUN /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y

RUN apt-get install postgresql-18 -y
ENV PATH="$PATH:/usr/lib/postgresql/18/bin/initdb"

RUN rm -rf /var/lib/apt/lists/*

# Copy the compiled binary from the builder
COPY --from=sui-binary /usr/local/bin/sui /usr/local/bin/sui
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]