# logos-node — DAppNode package (community, unofficial)

A one-click [DAppNode](https://dappnode.io) package that runs a **Logos 0.3.0
blockchain testnet node**, headless.

> **Community-maintained, UNOFFICIAL — not an official Logos release.** For an
> official, signed package watch the curated DAppStore. This exists to give
> DAppNode operators a frictionless Logos node on-ramp and to dogfood the path.

## What it does

On first run the container:
- generates a fresh 0.3.0 config + keys (`init-config`), with **`bootstrap.ibd.peers` filled** so it syncs cleanly;
- **caps PoW mining to 1 thread** so it never pegs the host;
- binds the node HTTP API to `0.0.0.0:8080` so it can be monitored;
- persists chain state / keystore to a named volume (restart-safe);
- once the chain is Online, enables PoW mining + auto-claim via the node API.

Ports: `udp/3000` (swarm) and `udp/3400` (Blend). Testnet is ephemeral — it
re-genesises on each node release.

### Setup wizard

Install-time options (`setup-wizard.yml` → container env, honored every start):
- **Enable mining** (`MINING_ENABLED`, default `true`) — turn off for a pure syncing/observing node.
- **Mining CPU threads** (`MINING_MAX_THREADS`, default `1`) — raise only on a dedicated box.
- **Log level** (`LOG_LEVEL`, default `info`) → `RUST_LOG`.

### Resilience

- `restart: unless-stopped` + a **healthcheck** (`cryptarchia/info`, 10-min start grace).
- Resource caps: `mem_limit: 6g`, `cpus: 2`.
- **Backup** targets the keystore + config (`/data/keystore.yaml`, `/data/user_config.yaml`),
  **not** the chain DB — testnet state is disposable and re-syncs from IBD peers.

## Install

- **Published build:** DAppStore → *Install from URL* → paste the release
  `/ipfs/Qm…` hash (or, once registered, find it in the **Public** DAppStore).
- The Dockerfile downloads the pinned node binary at build time
  (`ARG NODE_VERSION`, `ARG TARGETARCH`). **Published arch: `linux/amd64` only.**
  The Dockerfile already resolves `arm64 → aarch64` (the release has that asset),
  but a multi-arch publish needs `docker buildx`, which isn't on the current build
  host — tracked as a CI follow-up (see Roadmap).

## Build / publish

```
npm i -g @dappnode/dappnodesdk
dappnodesdk build   --provider <ipfs-api-url>   # -> install hash
dappnodesdk publish <patch|minor|major>         # -> APM/ENS release (mainnet tx)
```

## Roadmap

Tracked in `logos-co/ecosystem#247`. Done here: setup wizard, healthcheck +
resource caps, backups. Remaining toward a polished, publicly-listed package:

- **Multi-arch (`arm64`)** — needs `docker buildx` in CI; the Dockerfile is
  already arch-parametric.
- **Grafana dashboard + Prometheus targets** — blocked on the node exposing
  Prometheus metrics. `GET /mantle/metrics` currently returns **JSON**
  (e.g. `{"pending_items":…}`), not the Prometheus text format, so a dashboard
  needs a small exporter shim (JSON → `/metrics`) or a node-side `/metrics`
  endpoint. Not fabricated here.
- **Own web UI** + `links.ui` wiring.
- **CI** (`dappnodesdk github-action bump-upstream`) to auto-bump on node releases.
- **Official curated store** — a Logos-controlled signing wallet whitelisted by
  DAppNode (out of our hands; this package stays on `public.dappnode.eth`).

## Layout

- `Dockerfile` — downloads + installs the node binary (pinned, arch-parametric)
- `entrypoint.sh` — first-run config, mining cap, API expose, auto mining/claim, env-wired
- `dappnode_package.json` — DAppNode manifest (+ `backup[]`)
- `setup-wizard.yml` — install-time options (mining on/off, threads, log level)
- `docker-compose.yml` — service / ports / volume / healthcheck / resource caps
- `avatar.png` — DAppStore icon
