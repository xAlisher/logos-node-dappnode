#!/usr/bin/env bash
# Upgrade-path tests for entrypoint.sh. Each case seeds a data volume the way an
# earlier package version (or an interrupted start) left it, runs the image's
# entrypoint against it with a stub node binary and a stub chain-genesis.sh
# reporting a chosen genesis, and checks what happened to config, keystore and
# chain data. A last check runs the real chain-genesis.sh against the image's
# node binary.
#
#   tests/entrypoint-upgrade.sh <image>
set -euo pipefail

IMAGE="${1:?usage: $0 <image>}"
# Geneses (genesis_time_unix_ms): the 0.3.0 chain, the Oct 9 relaunch, a future one.
GENESIS_030=1790758800000
GENESIS_031=1791556200000
GENESIS_NEXT=1799999999999

WORK="$(mktemp -d)"
trap 'docker run --rm -v "$WORK:/w" --entrypoint sh "$IMAGE" -c "rm -rf /w/vol-*" >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT
mkdir -p "$WORK/stub"
# Stub node: `init-config -o <cfg> -k <keystore>` writes a minimal config and a
# fresh keystore (unless one exists); `--check-config <cfg>` rejects a config
# containing "old-format"; the final `exec` of the node just exits.
cat > "$WORK/stub/logos-blockchain-node" <<'EOF'
#!/bin/sh
if [ "${1:-}" = --check-config ]; then
  ! grep -q old-format "$2"
  exit
fi
if [ "${1:-}" = init-config ]; then
  shift
  while [ $# -gt 0 ]; do
    case "$1" in -o) out="$2"; shift 2 ;; -k) ks="$2"; shift 2 ;; *) shift ;; esac
  done
  printf 'api:\n  listen_address: 127.0.0.1:8080\npow:\n  max_threads: 4\n' > "$out"
  [ -f "$ks" ] || echo "fresh-key" > "$ks"
fi
exit 0
EOF
# Stub probe: prints STUB_GENESIS, or fails when it is "fail".
cat > "$WORK/stub/chain-genesis.sh" <<'EOF'
#!/bin/sh
[ "$STUB_GENESIS" != fail ] || exit 1
echo "$STUB_GENESIS"
EOF
chmod +x "$WORK/stub/logos-blockchain-node" "$WORK/stub/chain-genesis.sh"

fails=0
pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }
check() { if "${@:2}"; then pass "$1"; else fail "$1"; fi; }

# Each case gets a new directory: re-creating one bind-mounted path can leave
# Docker on macOS mounting the deleted one.
case_n=0
new_vol() { case_n=$((case_n + 1)); VOL="$WORK/vol-$case_n"; mkdir -p "$VOL"; }

# seed <marker-file|none> [value] [<marker-file> <value>]: a volume holding a
# node's config, keystore, state and chain data, plus the markers an earlier
# package version wrote.
seed() {
  new_vol; mkdir -p "$VOL/db" "$VOL/state"
  echo "operator-config" > "$VOL/user_config.yaml"
  echo "operator-key" > "$VOL/keystore.yaml"
  echo "blocks" > "$VOL/db/blocks"
  echo "consensus" > "$VOL/state/consensus"
  while [ $# -ge 2 ]; do echo "$2" > "$VOL/$1"; shift 2; done
}

# run <genesis-the-node-reports> [expected-exit]
run() {
  local want="${2:-0}" got=0
  docker run --rm -e MINING_ENABLED=false -e STUB_GENESIS="$1" \
    -e PATH=/stub:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    -v "$WORK/stub:/stub:ro" -v "$VOL:/data" "$IMAGE" >"$WORK/out.log" 2>&1 || got=$?
  if [ "$got" -ne "$want" ]; then
    fail "entrypoint exited $got, expected $want (case $case_n)"
    sed 's/^/     | /' "$WORK/out.log"
  fi
}

# kept [dir]: the operator's config, keystore, state and chain data are in dir.
kept() {
  local d="${1:-$VOL}"
  grep -q operator-config "$d/user_config.yaml" 2>/dev/null \
    && [ "$(cat "$d/keystore.yaml" 2>/dev/null)" = operator-key ] \
    && [ -f "$d/db/blocks" ] && [ -f "$d/state/consensus" ]
}
fresh() { [ "$(cat "$VOL/keystore.yaml" 2>/dev/null)" = fresh-key ]; }
moved_to() { kept "$VOL/$1" && fresh; }
marked() { [ "$(cat "$VOL/.chain-genesis" 2>/dev/null)" = "$1" ]; }
legacy_is() { [ "$(cat "$VOL/.chain-version" 2>/dev/null)" = "$1" ]; }
no_legacy() { [ ! -e "$VOL/.chain-version" ]; }
same_chain_marks() { marked "$GENESIS_031" && legacy_is 0.3.1; }
new_chain_marks() { marked "$GENESIS_NEXT" && no_legacy; }
untouched_relaunch_volume() { kept && legacy_is 0.3.1 && [ ! -e "$VOL/.chain-genesis" ]; }
nothing_created() { [ ! -e "$VOL/keystore.yaml" ] && [ ! -e "$VOL/user_config.yaml" ] && [ ! -e "$VOL/.chain-genesis" ]; }
fresh_and_marked() { fresh && marked "$GENESIS_031"; }
is_genesis() { [[ "$1" =~ ^[0-9]{13}$ ]]; }
config_regenerated() {
  [ "$(cat "$VOL/keystore.yaml")" = operator-key ] && [ -f "$VOL/db/blocks" ] && [ -f "$VOL/state/consensus" ] \
    && grep -q max_threads "$VOL/user_config.yaml" && grep -q old-format "$VOL"/user_config.yaml.*.bak
}
archives_separate() {
  [ "$(cat "$VOL/oldchain-$GENESIS_031/keystore.yaml")" = older-key ] \
    && [ "$(cat "$VOL/oldchain-$GENESIS_031-1/keystore.yaml")" = older-key ] \
    && kept "$VOL/oldchain-$GENESIS_031-2"
}
migration_finished() {
  fresh && grep -q operator-config "$VOL/oldchain-$GENESIS_031-1/user_config.yaml" \
    && [ "$(cat "$VOL/oldchain-$GENESIS_031/keystore.yaml")" = operator-key ]
}

# v0.2.x volume (.chain-version=0.3.1), newer node on the same relaunch chain.
seed .chain-version 0.3.1; run "$GENESIS_031"
check "0.3.1 volume on the same chain keeps config, keys, state and data" kept
check "  ...is marked with its genesis and stays readable by v0.2.x" same_chain_marks

# v0.2.x volume after a re-genesis.
seed .chain-version 0.3.1; run "$GENESIS_NEXT"
check "0.3.1 volume after a re-genesis is moved aside" moved_to "oldchain-$GENESIS_031"
check "  ...is marked with the new genesis, without a v0.2.x marker" new_chain_marks

# v0.1.x volume (node 0.3.0, no marker) on the relaunch chain.
seed none; run "$GENESIS_031"
check "0.3.0 volume is moved aside" moved_to "oldchain-$GENESIS_030"

# Volumes this version already marked.
seed .chain-genesis "$GENESIS_031" .chain-version 0.3.1; run "$GENESIS_031"
check "volume marked with the current genesis is kept" kept
seed .chain-genesis "$GENESIS_NEXT"; run "$GENESIS_031"
check "volume marked with another genesis is moved aside" moved_to "oldchain-$GENESIS_NEXT"

# Downgrade round trip: a future-chain volume opened by v0.2.x gets relaunch data
# and .chain-version=0.3.1 next to the stale .chain-genesis.
seed .chain-genesis "$GENESIS_NEXT" .chain-version 0.3.1; run "$GENESIS_NEXT"
check "after a v0.2.x downgrade, the future chain moves the relaunch data aside" moved_to "oldchain-$GENESIS_031"
seed .chain-genesis "$GENESIS_NEXT" .chain-version 0.3.1; run "$GENESIS_031"
check "after a v0.2.x downgrade, the relaunch chain keeps its data" kept

# Earlier archives with the same name are never merged into.
seed .chain-genesis "$GENESIS_031"
for a in "oldchain-$GENESIS_031" "oldchain-$GENESIS_031-1"; do mkdir -p "$VOL/$a"; echo older-key > "$VOL/$a/keystore.yaml"; done
run "$GENESIS_NEXT"
check "existing archives keep their keystores, the new one gets its own folder" archives_separate

# A migration interrupted after db, state and keystore moved: config is still
# there, so the next start finishes it and makes fresh keys.
seed .chain-version 0.3.1; mkdir -p "$VOL/oldchain-$GENESIS_031"
mv "$VOL/db" "$VOL/state" "$VOL/keystore.yaml" "$VOL/oldchain-$GENESIS_031/"
run "$GENESIS_NEXT"
check "an interrupted migration finishes on restart" migration_finished

# Same chain, but the config is in a format this node release rejects (0.3.1's
# config under 0.3.2 or later): a new config, same keystore and chain data.
seed .chain-version 0.3.1; echo "old-format" >> "$VOL/user_config.yaml"; run "$GENESIS_031"
check "a config the node rejects is regenerated, keystore and data kept" config_regenerated

# The probe fails or prints garbage: nothing is moved, markers stay as they were.
seed .chain-version 0.3.1; run fail
check "a failed genesis probe leaves keys, data and markers alone" untouched_relaunch_volume
seed .chain-version 0.3.1; run 12abc
check "garbage from the probe leaves keys, data and markers alone" untouched_relaunch_volume

# A fresh volume.
new_vol; run "$GENESIS_031"
check "fresh volume is initialised and marked" fresh_and_marked
new_vol; run fail 1
check "a fresh volume without a genesis gets no keys yet" nothing_created

# The real probe against the image's node binary (runs natively, needs no peers).
REAL="$(docker run --rm --entrypoint chain-genesis.sh "$IMAGE" 2>"$WORK/probe.log" || true)"
check "chain-genesis.sh reads a genesis from the node ($REAL)" is_genesis "$REAL"

if [ "$fails" -gt 0 ]; then echo "$fails failing"; exit 1; fi
echo "all passed"
