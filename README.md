# Insta-Automate Control Center

A Flutter Windows control center for [`Insta-Automate`](https://github.com/SeshuTarapatla/Insta-Automate),
a Prefect-based Instagram scraping pipeline that drives a real Android phone over ADB, stores rows
in Postgres and screenshots in a local `IA_DIR`, and runs as two pods on local k3s (Rancher Desktop).

Before this project, running the pipeline meant hand-editing `config.env`, tailing raw Kubernetes
logs, remembering a handful of `kubectl`/`helm`/`ia` incantations in the right order, and manually
starting three Windows-side services (ADB, a local VL model server, a scrcpy bridge) from a startup
shortcut with no supervision. This app turns all of that into a single mature desktop control
center — see [EXPECTATION.md](EXPECTATION.md) for the original problem statement this project set
out to solve, all nine points of which are now addressed.

**Status: v1.0.0 — every phase in [docs/PLAN.md](docs/PLAN.md) is built and accepted.**

## What it does

- **Live config** — every limit, trigger delay, and flow switch is editable from the app and takes
  effect on the pipeline's next read, no rebuild or redeploy required.
- **Core services** — start/stop/restart/test ADB, the local VL inference server, and the wsl-bridge
  scrcpy shim, with real terminal output, self-heal, and autostart, all supervised by the agent
  rather than a startup shortcut.
- **Live screen** — flow-aware log console plus a per-flow visualization surface (scan filmstrip,
  classify verdict stream, scrape/follow before→after cards, ingest hero grid) and a device pane
  that drives the phone's scrcpy mirror.
- **Library** — full image review/curation parity with the mobile app: browse every pipeline stage,
  multi-select, apply/discard, and a per-entity yield funnel.
- **Mobile pairing** — QR-code pairing to a phone on the same LAN, with real-time push notifications
  (falling back to Telegram when nothing is listening) instead of a Syncthing-delayed one-way sync.
- **Ops panel** — build the image, deploy/restart pods, back up/restore/purge the database, and
  upgrade the Helm release, each as a button with streamed live output instead of a manual shell
  session.
- **Insights** — a whole-library funnel, per-entity ranking, and daily limit burn-down charts, built
  entirely on data the pipeline already persists.
- **Polish** — a mission-control Overview page, a system tray icon with a global show/hide hotkey,
  and consistent empty/error/loading states throughout.

## Structure

This repo ships two parts:

- **`app/`** — the Flutter Windows client (`ia_control_center`, org `com.instaautomate`).
- **`agent/`** — `ia-agent`, a Python/FastAPI service (`uv` project) that is the long-lived Windows
  process. It supervises the core services, serves the pods and the phone over REST/WebSocket, and
  outlives the UI window.

```
agent/  uv run ia-agent            # starts the agent on 0.0.0.0:8787
app/    flutter run -d windows     # starts the desktop client
```

The agent must be running (or reachable) before the app connects; the app can also start it via
`ia_agent_launcher.pyw`. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full request flow
and [docs/PLAN.md](docs/PLAN.md) for how each piece was built, checkpoint by checkpoint.

## Docs

Read in this order:

1. [CLAUDE.md](CLAUDE.md) — current project state, decisions, and working rules.
2. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — system design.
3. [docs/PLAN.md](docs/PLAN.md) — the phased build order and every checkpoint's outcome.
4. [docs/DECISIONS.md](docs/DECISIONS.md) — the full decision log, newest first.

## The repos in play

This control center coordinates changes across several other local repos, each on its own
feature branch until this project accepted it (see `CLAUDE.md` rule 3):

| Repo | Role |
|---|---|
| `Insta-Automate` | the pipeline: flows, tasks, controllers, `ia` CLI |
| `wsl-bridge` | FastAPI scrcpy shim, not modified by this project |
| `Insta-Automate-Client` | the companion Android app (`ia_manager`) |
| `Helmcharts/Insta-Automate` | Helm chart for the scheduler + worker pods |
| `my-modules`, `Prefect-K3S`, `TG-Auth` | supporting libraries used by the pipeline |

## License

Personal project, not licensed for reuse.
