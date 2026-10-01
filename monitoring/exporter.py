#!/usr/bin/env python3
"""Prometheus exporter for a Logos blockchain node.

The node speaks JSON over its HTTP API (GET /mantle/metrics returns JSON, not
Prometheus text), so DAppNode's DMS cannot scrape it directly. This tiny,
dependency-free sidecar polls the node API on each scrape and renders the
Prometheus text exposition format on /metrics.

Env:
  NODE_API      base URL of the node HTTP API   (default http://node:8080)
  LISTEN_PORT   port to serve /metrics on        (default 9112)
  SCRAPE_TIMEOUT per-endpoint timeout seconds     (default 4)
"""
import json
import os
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NODE_API = os.environ.get("NODE_API", "http://node:8080").rstrip("/")
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "9112"))
TIMEOUT = float(os.environ.get("SCRAPE_TIMEOUT", "4"))


def _get(path):
    """GET <NODE_API><path> and return parsed JSON, or None on any failure."""
    try:
        with urllib.request.urlopen(NODE_API + path, timeout=TIMEOUT) as r:
            return json.loads(r.read().decode("utf-8"))
    except Exception:
        return None


def _num(x, default=0):
    try:
        return float(x)
    except (TypeError, ValueError):
        return default


class Metric:
    """Accumulates (name, help, type, value) lines into Prometheus text."""

    def __init__(self):
        self.lines = []

    def add(self, name, value, mtype, help_text):
        if value is None:
            return
        self.lines.append("# HELP %s %s" % (name, help_text))
        self.lines.append("# TYPE %s %s" % (name, mtype))
        self.lines.append("%s %s" % (name, value))

    def text(self):
        return "\n".join(self.lines) + "\n"


def collect():
    m = Metric()
    t0 = time.time()

    crypt = _get("/cryptarchia/info")
    up = 1 if crypt is not None else 0
    m.add("logos_node_up", up, "gauge",
          "1 if the node HTTP API responded to this scrape, else 0.")

    if crypt is not None:
        info = crypt.get("cryptarchia_info", {})
        m.add("logos_node_height", int(_num(info.get("height"))), "gauge",
              "Current chain height (blocks) as seen by the node.")
        m.add("logos_node_slot", int(_num(info.get("slot"))), "gauge",
              "Current Cryptarchia slot.")
        m.add("logos_node_lib_slot", int(_num(info.get("lib_slot"))), "gauge",
              "Slot of the last immutable block (finalised).")
        online = 1 if info.get("state") == "Online" else 0
        m.add("logos_node_online", online, "gauge",
              "1 if cryptarchia state is Online (synced), else 0.")

    net = _get("/network/info")
    if net is not None:
        peers = net.get("connected_peers") or []
        m.add("logos_node_connected_peers", len(peers), "gauge",
              "Number of currently connected libp2p peers.")

    pow_s = _get("/pow/status")
    if pow_s is not None:
        m.add("logos_node_mining", 1 if pow_s.get("is_mining") else 0, "gauge",
              "1 if PoW mining is active, else 0.")
        m.add("logos_node_rewards_enabled",
              1 if pow_s.get("are_rewards_enabled") else 0, "gauge",
              "1 if PoW rewards are enabled, else 0.")
        ac = pow_s.get("auto_claim") or {}
        m.add("logos_node_auto_claim_armed",
              1 if ac.get("is_armed") else 0, "gauge",
              "1 if auto-claim is armed, else 0.")

    aged = _get("/leader/aged-notes")
    if aged is not None:
        m.add("logos_node_aged_notes_count", int(_num(aged.get("count"))),
              "gauge", "Number of aged leadership notes (eligible stake).")
        m.add("logos_node_aged_notes_total_value",
              int(_num(aged.get("total_value"))), "gauge",
              "Total value of aged leadership notes.")

    vouch = _get("/leader/claim/vouchers")
    if vouch is not None:
        vouchers = vouch.get("vouchers") or []
        m.add("logos_node_vouchers_count", len(vouchers), "gauge",
              "Number of unclaimed leader reward vouchers.")
        m.add("logos_node_vouchers_total_claimable",
              int(_num(vouch.get("total_claimable"))), "gauge",
              "Total claimable amount across vouchers.")
        m.add("logos_node_reward_amount", int(_num(vouch.get("reward_amount"))),
              "gauge", "Per-voucher reward amount advertised by the node.")

    mant = _get("/mantle/metrics")
    if mant is not None:
        m.add("logos_node_mempool_pending_items",
              int(_num(mant.get("pending_items"))), "gauge",
              "Pending mantle mempool items.")

    m.add("logos_node_scrape_duration_seconds",
          round(time.time() - t0, 4), "gauge",
          "Seconds the exporter spent polling the node for this scrape.")
    return m.text()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.rstrip("/") in ("", "/metrics"):
            body = collect().encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type",
                             "text/plain; version=0.0.4; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *_a):  # quiet
        pass


if __name__ == "__main__":
    print("[logos-exporter] scraping %s, serving :%d/metrics" %
          (NODE_API, LISTEN_PORT), flush=True)
    ThreadingHTTPServer(("0.0.0.0", LISTEN_PORT), Handler).serve_forever()
