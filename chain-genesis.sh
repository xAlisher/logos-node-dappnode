#!/bin/sh
# Prints the genesis (genesis_time_unix_ms) of the chain the installed
# logos-blockchain-node joins, read from the node's own API with a throwaway
# config in a temp dir. Needs no peers and takes about a second. The entrypoint
# runs it before starting the node, natively: under QEMU (cross-arch image
# builds) the node binary can die on unsupported CPU instructions.
set -eu
DEADLINE=$(($(date +%s) + 30))
dir="$(mktemp -d)"
pid=""
# shellcheck disable=SC2329 # called by the EXIT trap
cleanup() {
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null || true
    # Wait for the throwaway node to exit, so its ports are free for the real one.
    i=0
    while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 10 ]; do sleep 0.5; i=$((i + 1)); done
    kill -9 "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -rf "$dir"
}
trap cleanup EXIT
cd "$dir"
if ! timeout 30 logos-blockchain-node init-config -o "$dir/user_config.yaml" -k keystore.yaml >"$dir/init.log" 2>&1; then
  echo "chain-genesis: init-config failed:" >&2
  tail -20 "$dir/init.log" >&2
  exit 1
fi
logos-blockchain-node "$dir/user_config.yaml" >"$dir/node.log" 2>&1 &
pid=$!
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  # One integer of at least 10 digits, followed by the end of the JSON value.
  genesis="$(curl -sf -m1 http://127.0.0.1:8080/time/info 2>/dev/null \
    | sed -n 's/.*"genesis_time_unix_ms"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\)[[:space:]]*[,}].*/\1/p' \
    | head -n 1 || true)"
  if [ "${#genesis}" -ge 10 ]; then
    echo "$genesis"
    exit 0
  fi
  if ! kill -0 "$pid" 2>/dev/null; then
    break
  fi
  sleep 1
done
echo "chain-genesis: could not read genesis_time_unix_ms from the node:" >&2
tail -20 "$dir/node.log" >&2
exit 1
