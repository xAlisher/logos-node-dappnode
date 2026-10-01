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

## Install

- **Published build:** DAppStore → *Install from URL* → paste the release
  `/ipfs/Qm…` hash (or, once registered, find it in the **Public** DAppStore).
- The Dockerfile downloads the pinned node binary at build time
  (`ARG NODE_VERSION`), multi-arch via buildx (`amd64` / `arm64`).

## Build / publish

```
npm i -g @dappnode/dappnodesdk
dappnodesdk build   --provider <ipfs-api-url>   # -> install hash
dappnodesdk publish <patch|minor|major>         # -> APM/ENS release (mainnet tx)
```

## Roadmap

Tracked in `logos-co/ecosystem#247`. Toward a polished, publicly-listed package:
setup wizard, Grafana dashboard + Prometheus targets, own web UI, backups,
healthchecks + resource caps, multi-arch, CI (`bump-upstream`), and — for the
official curated store — a Logos-controlled signing wallet whitelisted by DAppNode.

## Layout

- `Dockerfile` — downloads + installs the node binary (pinned, multi-arch)
- `entrypoint.sh` — first-run config, mining cap, API expose, auto mining/claim
- `dappnode_package.json` — DAppNode manifest
- `docker-compose.yml` — service / ports / volume
- `avatar.png` — DAppStore icon
