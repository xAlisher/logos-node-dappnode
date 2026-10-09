# logos-blockchain-node — DAppNode package (community, unofficial)

A one-click [DAppNode](https://dappnode.io) package that runs a **Logos 0.3.1
blockchain testnet node**, headless.

> **Community-maintained, UNOFFICIAL — not an official Logos release.** For an
> official, signed package watch the curated DAppStore. This exists to give
> DAppNode operators a frictionless Logos node on-ramp and to dogfood the path.

## What it does

On first run the container:
- generates a fresh 0.3.1 config + keys (`init-config`), with **`bootstrap.ibd.peers` filled** so it syncs cleanly;
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
- Resource caps: `mem_limit: 6g`, `cpus: 2` (under `deploy.resources.limits`).
- **Backup** targets the keystore + config (`/data/keystore.yaml`, `/data/user_config.yaml`),
  **not** the chain DB — testnet state is disposable and re-syncs from IBD peers.

### Monitoring (Grafana + Prometheus)

A second service, **`monitoring/`**, runs a tiny stdlib-only Prometheus exporter
(`monitoring/exporter.py`) that polls the node HTTP API each scrape and renders
the Prometheus text format on `:9112/metrics` — the node itself only speaks JSON
(`GET /mantle/metrics` returns JSON, not Prometheus), so DMS can't scrape it
directly. DAppNode's DMS picks up `prometheus-targets.json` and
`logos-node-grafana-dashboard.json` automatically. Metrics: `logos_node_up`,
`_online`, `_height`, `_lib_slot`, `_connected_peers`, `_mining`,
`_rewards_enabled`, `_auto_claim_armed`, `_aged_notes_count`/`_total_value`,
`_vouchers_count`/`_total_claimable`, `_reward_amount`, `_mempool_pending_items`,
`_scrape_duration_seconds`.

### Web dashboard (the UI button)

A third service, **`webui/`**, serves a faithful web replica of the official
Logos node app (`logos-blockchain/logos-blockchain-ui`) — node status, rewards,
explorer, wallet, mining, and settings, in the real Logos design system. It is
built from **xAlisher/logos-node-webui** (pinned by commit in `webui/Dockerfile`)
and served by nginx, which reverse-proxies `/api` to the node on the package
network (`node:8080`), including the two SSE streams. The package manifest wires
`links.ui` to `http://webui.logos-blockchain-node.public.dappnode`, so the UI
button in the DAppNode installer opens the dashboard. Feature/action parity with
the official app is gated by a 225-entry checklist in the UI repo.

## Install

- **GitHub release:** [v0.1.18](https://github.com/xAlisher/logos-node-dappnode/releases/tag/v0.1.18)
  ships the built package bundles for **`linux/amd64` and `linux/arm64`**.
- **On a DAppNode:** DAppStore → *Install from URL* → paste the release
  `/ipfs/Qm…` hash (or, once registered, find it in the **Public** DAppStore).
- The Dockerfile downloads the pinned node binary at build time
  (`ARG NODE_VERSION`, `ARG TARGETARCH`) and builds **both** architectures via
  `docker buildx` + QEMU (`arm64 → aarch64`); the arm64 binary is verified aarch64.

## Build / publish

```
npm i -g @dappnode/dappnodesdk
dappnodesdk build   --provider <ipfs-api-url>   # -> install hash
dappnodesdk publish <patch|minor|major>         # -> APM/ENS release (mainnet tx)
```

## CI

- **`.github/workflows/build.yml`** — on every PR/push, installs the SDK, sets
  up buildx + QEMU, and runs `dappnodesdk build --skip_upload` to validate the
  manifest/compose/setup-wizard against the DAppNode schemas and build both
  images. **No secrets required.**
- **`.github/workflows/bump-upstream.yml`** — daily (+ manual) check of
  `logos-blockchain/logos-blockchain` releases via `dappnodesdk github-action
  bump-upstream`; opens a PR that bumps `manifest.upstream[].version` and the
  `NODE_VERSION` compose build arg when a newer node release lands. Uses the
  auto-provided `GITHUB_TOKEN` (contents + PR write). The APM next-version
  lookup only fully resolves once the package is registered on APM.

## Roadmap

Tracked in `logos-co/ecosystem#247`. **Done here:** setup wizard, healthcheck +
resource caps, backups, **Prometheus exporter + Grafana dashboard + DMS
targets**, **CI (build-validate + bump-upstream)**, **real multi-arch (amd64 + arm64) build
+ GitHub release ([v0.1.18](https://github.com/xAlisher/logos-node-dappnode/releases/tag/v0.1.18))**,
**web dashboard (`webui/`) + `links.ui` wiring**. Remaining toward a
polished, publicly-listed package:

- **IPFS publish in CI** — `build.yml` validates but does not upload. A
  publishing workflow needs an IPFS provider / pinning secret (e.g. a
  self-hosted IPFS node or Infura IPFS creds) added as repo secrets.
- **ENS/APM registration + official curated store** — registering
  `logos-blockchain-node.public.dappnode.eth` needs a funded wallet (mainnet tx); the
  official signed store needs a Logos-controlled wallet whitelisted by DAppNode
  (out of our hands; this package stays on `public.dappnode.eth`).

### Setup wizard: why "Enable mining" is a dropdown, not a checkbox (issue #1)

DAppNode's setup-wizard schema has **no boolean/checkbox/toggle field type** —
only `enum` (→ select menu), `pattern` (→ text) and `secret` (→ masked text).
A two-option `enum` `["true","false"]` rendered as a dropdown is the canonical
DAppNode idiom for an on/off setting. Not a bug we can fix package-side; a native
toggle would be an upstream DAppNode feature request.

## Layout

- `Dockerfile` — downloads + installs the node binary (pinned, arch-parametric)
- `entrypoint.sh` — first-run config, mining cap, API expose, auto mining/claim, env-wired
- `dappnode_package.json` — DAppNode manifest (+ `backup[]`)
- `setup-wizard.yml` — install-time options (mining on/off, threads, log level)
- `docker-compose.yml` — node + monitoring + webui services / ports / volume / healthcheck / caps
- `monitoring/` — `exporter.py` (JSON→Prometheus shim) + its `Dockerfile`
- `webui/` — `Dockerfile` that clones + builds the web dashboard (nginx + `/api` proxy)
- `prometheus-targets.json` / `logos-node-grafana-dashboard.json` — DMS wiring
- `.github/workflows/` — build-validate + bump-upstream CI
- `avatar.png` — DAppStore icon
