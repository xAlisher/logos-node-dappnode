FROM debian:stable-slim

# Pinned node version + target arch (buildx sets TARGETARCH for multi-arch builds).
ARG NODE_VERSION=0.3.0
ARG TARGETARCH=amd64

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

# Download + install the logos-blockchain-node binary for the target architecture.
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) A=x86_64 ;; \
      arm64) A=aarch64 ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}"; exit 1 ;; \
    esac; \
    curl -fL "https://github.com/logos-blockchain/logos-blockchain/releases/download/${NODE_VERSION}/logos-blockchain-node-linux-${A}-${NODE_VERSION}.tar.gz" -o /tmp/node.tgz; \
    tar -xzf /tmp/node.tgz -C /tmp; \
    install -m 0755 "$(find /tmp -type f -name logos-blockchain-node | head -1)" /usr/local/bin/logos-blockchain-node; \
    rm -rf /tmp/node.tgz; \
    logos-blockchain-node --version || true

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /data
# swarm (udp/3000) and blend (udp/3400)
EXPOSE 3000/udp 3400/udp
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
