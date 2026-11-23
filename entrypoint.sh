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

# New chain (relaunch / re-genesis): a volume created on another chain still holds
# that chain's config and blocks, and the node panics replaying them
# ("The chain can't be recovered from storage ... FutureBlock"). Move them aside,
# keys included, and start fresh. The chain is identified by its genesis, read
# from the node binary (chain-genesis.sh), so a node release on the same chain
# keeps config, keys and data.
MARK="$DATA/.chain-genesis"
# Older package versions recorded the node version instead: v0.2.x wrote
# .chain-version=0.3.1 (Oct 9 relaunch), v0.1.x (node 0.3.0) wrote nothing.
LEGACY_MARK="$DATA/.chain-version"
GENESIS_030=1790758800000
GENESIS_031=1791556200000

# Replace a marker atomically, so an interrupted write never leaves it empty.
write_marker() { printf '%s\n' "$2" > "$1.tmp" && mv "$1.tmp" "$1"; }

GENESIS="$(chain-genesis.sh)" || GENESIS=""
case "$GENESIS" in ''|*[!0-9]*) GENESIS="" ;; esac

if [ -z "$GENESIS" ]; then
  if [ ! -f "$CFG" ]; then
    # Keys created now would carry no marker and be archived on the next start.
    echo "[logos-node] could not read the chain genesis; not creating keys yet, exiting so the container restarts" >&2
    exit 1
  fi
  echo "[logos-node] could not read the chain genesis; leaving config, keys and chain data as they are"
else
  if [ -f "$CFG" ]; then
    # .chain-version comes first: this entrypoint writes it only next to a
    # matching .chain-genesis, while a downgraded v0.2.x rewrites it and leaves
    # .chain-genesis stale.
    if [ -f "$LEGACY_MARK" ]; then
      case "$(cat "$LEGACY_MARK")" in
        0.3.1) OLD="$GENESIS_031" ;;
        *) OLD=unknown ;;
      esac
    elif [ -f "$MARK" ]; then
      OLD="$(cat "$MARK")"
    else
      OLD="$GENESIS_030"
    fi
    if [ "$OLD" != "$GENESIS" ]; then
      # Never merge into an earlier archive: mv would overwrite its keystore.
      BASE="$DATA/oldchain-${OLD:-unknown}"
      ARCH="$BASE"
      n=1
      while [ -e "$ARCH" ]; do ARCH="$BASE-$n"; n=$((n + 1)); done
      echo "[logos-node] chain changed (genesis $OLD -> $GENESIS): moving old config, keys and chain data to $ARCH"
      mkdir -p "$ARCH"
      # Config last: until it moves, a restart redoes the migration; once it
      # has moved, the old keys are already archived.
      for f in db state keystore.yaml user_config.yaml; do
        if [ -e "$DATA/$f" ]; then mv "$DATA/$f" "$ARCH/"; fi
      done
    fi
  fi
  # Mark before init-config: a restart during init must not archive new keys.
  write_marker "$MARK" "$GENESIS"
  # Keep .chain-version right for a downgrade to v0.2.x, which reads only that.
  if [ "$GENESIS" = "$GENESIS_031" ]; then write_marker "$LEGACY_MARK" 0.3.1; else rm -f "$LEGACY_MARK"; fi
fi

# A config written by an older node release can fail to parse in a newer one on
# the same chain (0.3.2 and later reject 0.3.1's `tracing: None`). Set it aside
# and generate a new one below; init-config reuses the existing keystore.
if [ -f "$CFG" ] && ! logos-blockchain-node --check-config "$CFG" >/dev/null 2>&1; then
  BAK="$CFG.$(date +%s).bak"
  echo "[logos-node] config does not parse with this node release; keeping it as $BAK and generating a new one (keystore and chain data kept)"
  mv "$CFG" "$BAK"
fi

# No config: generate one, and keys unless a keystore exists. init-config fills
# BOTH initial_peers and bootstrap.ibd.peers from the -p peers, so IBD works.
if [ ! -f "$CFG" ]; then
  echo "[logos-node] generating config (genesis ${GENESIS:-unknown}; an existing keystore is reused)"
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
