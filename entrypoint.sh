#!/bin/sh
set -eu
DATA=/data
CFG="$DATA/user_config.yaml"
KS="$DATA/keystore.yaml"

# Wizard-controlled settings (from docker-compose env; defaults keep it host-friendly).
MINING_ENABLED="${MINING_ENABLED:-true}"
MINING_MAX_THREADS="${MINING_MAX_THREADS:-1}"
LOG_LEVEL="${LOG_LEVEL:-info}"
export RUST_LOG="${RUST_LOG:-$LOG_LEVEL}"

# First run: generate a fresh 0.3.0 config + keys. init-config fills BOTH
# initial_peers and bootstrap.ibd.peers from the -p peers, so IBD works.
if [ ! -f "$CFG" ]; then
  echo "[logos-node] first run: generating fresh 0.3.0 config + keys"
  logos-blockchain-node init-config -o "$CFG" -k "$KS" \
    -p /ip4/65.109.51.37/udp/3000/quic-v1/p2p/12D3KooWFrouXfmrR4nsLMtE7wu15DoMJ6VtoUtHinREZCvbWHar \
    -p /ip4/65.109.51.37/udp/3001/quic-v1/p2p/12D3KooWJRGau8M1rjT7R5e4YYsgdFhsMX35nRDtMwCDjxQkXAHz \
    -p /ip4/65.109.51.37/udp/3002/quic-v1/p2p/12D3KooWQXJavMDTRscjauFSgVAB1VLB6Rzpy2uY5SU9Tk7927tb \
    -p /ip4/65.109.51.37/udp/50001/quic-v1/p2p/12D3KooWSQc7CcGtvWDPF1yCbBthFnQjprfCVHmfmNDUrSmqQsU1
  echo "[logos-node] config generated"
fi

# Apply wizard settings every start (idempotent) so updates take effect:
#  - cap mining threads to the configured value (default 1, host-friendly)
sed -i "s/^\([[:space:]]*\)max_threads:.*/\1max_threads: ${MINING_MAX_THREADS}/" "$CFG"
#  - expose the API on the container network so it is monitorable over the DAppNode net / VPN
sed -i 's|listen_address: 127.0.0.1:8080|listen_address: 0.0.0.0:8080|' "$CFG"
echo "[logos-node] mining max_threads=${MINING_MAX_THREADS}, API on 0.0.0.0:8080, log=${LOG_LEVEL}"

# Once Online, enable PoW mining + auto-claim — unless the wizard disabled mining.
if [ "${MINING_ENABLED}" = "true" ]; then
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
else
  echo "[logos-node] mining disabled (MINING_ENABLED=false)"
fi

echo "[logos-node] starting node"
exec logos-blockchain-node "$CFG"
