# CLAUDE.md — Insta-Automate Control Center

Read this first, then [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and
[docs/PLAN.md](docs/PLAN.md). Current state: **Phases 0 and 1 complete and user-verified**;
**Phase 2 in progress — CP 2.1 (supervisor engine) is done and Claude-verified**, with no UI yet,
so there is nothing for the user to click until CP 2.4.

`config.env` is fully controllable from the app (CP 1.1–1.4). The agent now also supervises
processes: `agent/src/ia_agent/services/` holds the spec/probe/terminal-ring/supervisor engine plus
the three real service specs, exposed at `GET /api/services`, `PATCH /api/services/{name}` and
`POST /api/services/{name}/{start|stop|restart|takeover|resize}`. Services are spawned into a
**ConPTY** and their output kept verbatim, so CP 2.4 renders a real terminal rather than a log list.
Each service has a **self-heal** switch (persisted in `services.json`) and a functional self-test at
`POST /api/services/{name}/test`; autostart is **off** until CP 2.5 hands startup ownership to the
agent, so today it adopts or observes rather than spawns. `GET /api/dependencies` (CP 2.3) covers
the ten things the pipeline needs but the agent does not supervise. Next up is **CP 2.4** (Services
UI — the first thing here you can click).

---

## ⚠ TEMPORARY: all five flow switches are OFF

Set **2026-07-31** so the pods and helm chart can be worked against without the pipeline firing
flows on its own. `config.env` now has `ENTITY_INGEST/SCAN/CLASSIFY/SCRAPE/FOLLOW=0`; every other
key is untouched. Verified live inside the running scheduler pod — `Deployment.switch()` returns
`False` for all five, no restart needed.

**This must be turned back on when Phase 2 is accepted.** Restore with the app's Flows tab, or:

```bash
uv run --project agent python -c "
from ia_agent.config import env_file
from ia_agent.vars import CONFIG_PATH
d = env_file.load(CONFIG_PATH)
env_file.save(CONFIG_PATH, d, switches={k: '1' for k in d.switches})
"
```

What OFF does and does not do:

- **Does** stop the scheduler from triggering any flow — the gate is in `Deployment.trigger()`.
- **Does not** stop manual triggers. The Prefect UI/API and `prefect deployment run` call
  `run_deployment` directly and never consult the switch. (Verified by reading the code path, not
  by executing a run.)
- **Does not** stop the trigger loops themselves. They keep polling the DB, calling
  `wait_for_device()` and pinging Telegram every pass; they just skip the trigger. If that residual
  activity is unwanted, scale the `insta-automate` deployment to 0 instead — the worker deployment
  still executes manual runs.

---

## What this project is

A Flutter Windows control center for `Insta-Automate`, a Prefect-based Instagram scraping
pipeline that drives a real Android phone over ADB, stores rows in Postgres and screenshots in
`IA_DIR`, and runs as two pods on local k3s (Rancher Desktop).

It ships as **two parts, both in this repo**:

- `app/` — the Flutter Windows client. Pubspec name `ia_control_center`, org `com.instaautomate`.
- `agent/` — `ia-agent`, a Python/FastAPI service that is the long-lived Windows process. It
  supervises the core services, serves the pods and the phone, and outlives the UI window.
  `uv` project; console script `ia-agent`; bearer token at `%LOCALAPPDATA%\ia-agent\token`.

---

## The five repos in play

| Path | Role |
|---|---|
| `d:\Coding\Insta-Automate-Control-Center` | **this repo** — Flutter app + agent |
| `D:\Coding\Insta-Automate` | the pipeline: flows, tasks, controllers, `ia` CLI |
| `D:\Coding\wsl-bridge` | FastAPI scrcpy shim on `0.0.0.0:8000` — supervised, **not modified** |
| `D:\Coding\flutter\Insta-Automate-Client` | the existing Android review app (pubspec name `ia_manager`) |
| `D:\Coding\Helmcharts\Insta-Automate` | helm chart: `server.yaml` (scheduler) + `worker.yaml` |

Supporting: `D:\Coding\my-modules` (logger, postgres, kubernetes, scrcpy, win32, inet),
`D:\Coding\Prefect-K3S` (`prefect-k3s` CLI and the base image).

---

## Rules for working here

1. **Context and memory files live only in this repo.** `CLAUDE.md`, `MEMORY.md`, and everything
   under `docs/` — never anywhere else on the filesystem.
2. **Record decisions as they are made** in `docs/DECISIONS.md`, and keep `CLAUDE.md` and the
   plan docs current within the session that changed them.
3. **Other repos are feature-branch only.** Everything outside this repo works today. Changes go
   on `feat/control-center` (or `feat/lan-agent` for the mobile client) and are **never merged**
   until the control center is accepted. Never commit to `main` in another repo.
4. **Build in phases, stop at checkpoints.** Each `CP` in the plan is a commit boundary with a
   manual test the user runs before moving on.
5. **The user drives the app, never you.** (EXPECTATION.md #8 — this is absolute.) Do **not**
   click, navigate, screenshot, or otherwise drive the Flutter app, and do not use the `run`
   skill's GUI-driving patterns on it. The laptop has a single screen with VS Code maximized, so
   automated window driving actively disrupts the user's workspace. What you may do: build it,
   `flutter analyze` it, start it, and then **stop and hand over** — say it's running and what to
   check. The user tests, kills it, and reports back. Backend pieces (the agent's REST/WS surface,
   `config.env` round-trips) you *should* still verify yourself with `curl`/scripts — the rule is
   about the GUI, not about skipping verification.
6. **Say when a session is done.** When a phase's goal is met, tell the user explicitly that the
   session's goal is complete and a fresh session should be opened.
7. **No compromise on UI/UX.** This is meant to feel like a mature control center, not a form
   over a config file — visually mature, with UI/UX decisions that make the app genuinely easier
   to use, not merely functional.

---

## Facts an implementer needs

Verified live on 2026-07-30.

**Endpoints**

```
prefect     http://localhost:4200/api        (/health → true)
postgres    localhost:5432                   db: insta_automate
adb         0.0.0.0:5037
vl-server   127.0.0.1:11500/v1               qwen3-vl:4b-instruct via llama-server
wsl-bridge  0.0.0.0:8000                     GET / → true, /scrcpy/{start,stop}
k8s api     127.0.0.1:6443
ia-agent    0.0.0.0:8787                     (new, this project)
pod → host  172.19.16.1  ==  host.docker.internal
```

**Process shapes** — the pid that binds a port is rarely the pid you launched. A uv venv's
`python.exe` and its console-script `.exe` files are trampolines that re-exec the managed
interpreter under `%APPDATA%\uv\python\`, and `start_vl_server.py` supervises `llama-server.exe`
with its own restart loop. Live chains, all launched from one `WindowsTerminal.exe` (pid 20840):
`wsl-bridge.exe → python → python:8000`, `python start_vl_server.py → llama-server.exe:11500`.
Anything that identifies, kills, or adopts a process must walk the tree — see D11.

**Startup today** — `%APPDATA%\…\Startup\dev-startup.exe.lnk`, despite the name, is `wt.exe` with
four tabs: `adb -a start-server ; ollama serve ; start_vl_server.py ; wsl-bridge.exe`. Note
`start-server` *forks*, so that tab exits and nothing supervises adb. CP 2.5 replaces the whole
shortcut with a logon task running `ia-agent`; `ollama serve` is dropped (D13).

**IA_DIR** = `C:\Users\seshu\Pictures\insta-automate`, hostPath-mounted into both IA pods at
`/insta-automate`. Paths that cross the pod↔host boundary must be **IA_DIR-relative**.

```
config.env                    switches + ENTITY_QUEUE + limits (live-read by flows)
entities/<id>.jpg             1080×2246  full profile page
scanned/<root>/<user>.jpg     1080×198   follower/like list row crop
gender_valid/  gender_invalid/            classify output, same row crops
scrape_queued/<root>/<user>.jpg           human-promoted from gender_valid
scraped/<root>/<user>.jpg     1080×~2000 dp + profile-header composite
follow_queued/<root>/<user>.jpg           human-promoted from scraped
```

**The two IA deployments look alike and are not.** `insta-automate` (helm `server.yaml`) runs
`ia prefect serve` — the **scheduler**, i.e. the trigger loops. `insta-automate-worker`
(`worker.yaml`) runs the Prefect worker that executes flow runs. They share the label
`app: insta-automate`, and one name is a prefix of the other, so identify pods by stripping the
`-<pod-template-hash>-<suffix>` a Deployment adds — see `integrations/kube._deployment_of`.

**Postgres credentials live in the k3s `postgres-secret`**, read via
`my_modules.postgres.PostgresSecret`. Never copy them into this repo.

**Flows** (`entity_ingest`, `entity_scan`, `entity_classify`, `entity_scrape`, `entity_follow`)
are deployed to Prefect work pool `insta-automate-pool` from the git repo. The trigger loops all
live in `Insta-Automate/src/insta_automate/controllers/prefect.py` — that one file holds every
hardcoded delay and gate.

**Two humans-in-the-loop steps** gate the pipeline: `gender_valid → scrape_queued` and
`scraped → follow_queued`. Today they only happen on the phone.

**Don't confuse** `entity_scan` (harvest usernames from a profile's followers/following or a
post's likers) with `entity_scrape` (open one profile and capture its stats). Different limits,
different images, different Instagram account used (`alt` for scrape, `main` for follow).

---

## Decisions already taken

Recorded in [docs/DECISIONS.md](docs/DECISIONS.md):

1. Flutter UI + Python `ia-agent`, both in this repo. The agent, not the UI, owns process
   lifetime and becomes the Windows startup entry.
2. Flows get structured `emit()` events plus a filesystem watcher — not log scraping — because
   `entity_classify` and `entity_follow` delete images immediately after logging them.
3. Phone notifications over a LAN WebSocket held by an Android foreground service, with Telegram
   kept as the guaranteed fallback when nothing is listening.
4. The desktop app gets full image review/curation parity with the mobile app.
5. The desktop app's "Start agent" action uses raw Win32 `CreateProcess` (`CREATE_NO_WINDOW`) via
   `package:win32`, not `dart:io`'s `Process.start` — the latter flashes a visible console window
   because `uv`/`python` are console-subsystem executables and `dart:io` doesn't expose that flag.
6. Killing a service means killing its **root**, not the process holding the port (D11), and the
   agent never stops services when it exits (D10). Supervisor state is lock-guarded (D9).
7. **The agent is the only supervisor.** Services' own restart loops are switched off
   (`start_vl_server.py --no-autorestart`), because nested supervisors fight each other and hide
   their restart counts (D14). Service output is a raw ConPTY stream kept verbatim — never
   line-strip it, that is what a terminal needs (D15).

---

## Open questions

Eleven of them, listed at the end of [docs/PLAN.md](docs/PLAN.md). None block Phase 0. The two
that need answers earliest are **Q1** (`ENTITY_QUEUE` is shared between the scrape and follow
queues — split it or not?) and **Q3** (are `PROFILES`/`REELS`/`POSTS` really the live scan caps?
the code says yes, the config comment says no).

---

## Security flag

`D:\Coding\Insta-Automate\Dockerfile` is committed and contains the Postgres password, the
Telegram bot token, and two Telethon session strings in plaintext — a session string is a full
account credential. `ia build` regenerates that file on every build, so it never needed to be
committed. See ARCHITECTURE §10; tracked as Q10.
