#!/bin/sh
set -eu
DATA=/data
CFG="$DATA/user_config.yaml"
KS="$DATA/keystore.yaml"

# First run: generate a fresh 0.3.0 config + keys. init-config 0.3.0 fills BOTH
# initial_peers and bootstrap.ibd.peers from the -p peers, so IBD works.
if [ ! -f "$CFG" ]; then
  echo "[logos-node] first run: generating fresh 0.3.0 config + keys"
  logos-blockchain-node init-config -o "$CFG" -k "$KS" \
    -p /ip4/65.109.51.37/udp/3000/quic-v1/p2p/12D3KooWFrouXfmrR4nsLMtE7wu15DoMJ6VtoUtHinREZCvbWHar \
    -p /ip4/65.109.51.37/udp/3001/quic-v1/p2p/12D3KooWJRGau8M1rjT7R5e4YYsgdFhsMX35nRDtMwCDjxQkXAHz \
    -p /ip4/65.109.51.37/udp/3002/quic-v1/p2p/12D3KooWQXJavMDTRscjauFSgVAB1VLB6Rzpy2uY5SU9Tk7927tb \
    -p /ip4/65.109.51.37/udp/50001/quic-v1/p2p/12D3KooWSQc7CcGtvWDPF1yCbBthFnQjprfCVHmfmNDUrSmqQsU1
  # Cap PoW mining to 1 thread so it never pegs the host.
  sed -i 's/^\([[:space:]]*\)max_threads: null/\1max_threads: 1/' "$CFG"
  echo "[logos-node] config generated; mining capped to 1 thread"
fi

# Expose the HTTP API on the container network (not only localhost) so it can be
# reached over the DAppNode network / VPN for monitoring. Idempotent, every start.
sed -i 's|listen_address: 127.0.0.1:8080|listen_address: 0.0.0.0:8080|' "$CFG"

# Once the node is Online, enable PoW mining + auto-claim via the local HTTP API.
(
  until curl -sf -m3 http://127.0.0.1:8080/cryptarchia/info >/dev/null 2>&1; do sleep 5; done
  i=0
  while [ "$i" -lt 180 ]; do
    if curl -s -m3 http://127.0.0.1:8080/cryptarchia/info 2>/dev/null | grep -q '"state":"Online"'; then
      break
    fi
    i=$((i + 1)); sleep 10
  done
  curl -s -X PUT -m5 http://127.0.0.1:8080/pow/mining/start     >/dev/null 2>&1 || true
  curl -s -X PUT -m5 http://127.0.0.1:8080/pow/auto-claim/start >/dev/null 2>&1 || true
  echo "[logos-node] PoW mining + auto-claim requested"
) &

echo "[logos-node] starting node"
exec logos-blockchain-node "$CFG"
