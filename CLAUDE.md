# CLAUDE.md — Insta-Automate Control Center

Read this first, then [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and
[docs/PLAN.md](docs/PLAN.md). Current state: **Phases 0, 1 and 2 complete and accepted** (accepted
2026-07-31 — the user accepted Phase 2 outright without a separate CP 2.6 verification pass). The
`wt.exe` startup shortcut is gone: an `ia-agent` **logon task** starts
the agent, which starts the three services from their `autostart` switches (now on). What CP 2.5
measured — supervised services die with the agent — is closed by CP 2.6: the pseudo-console now
lives in a detached service-host process, so a service survives the agent dying any way (D23).
**Phase 3 is open, CP 3.1–3.3 done** (Trigger delays & conditions, in `Insta-Automate` on
`feat/control-center`). `Limit` in `models/meta.py` is generalised into typed `Config`
(`Limit = Config` alias, no call sites changed), carrying every key from ARCHITECTURE §4.1 with
coded defaults for the ones not yet in `config.env`. Q3 is answered: `PROFILES/REELS/POSTS` really
are the live daily scan caps, and the `config.env` comment that said otherwise is fixed (D24).
`controllers/prefect.py`'s five trigger loops now sleep through `wait_until(flow, key)`, which
re-reads its `Config` key every tick so an edited delay re-targets a wait already in progress
(D25); the day-rollover fall-through is fixed with a `continue`, and `SCRAPE_BACKPRESSURE_FACTOR`
replaces the hardcoded `* 3`. New `controllers/agent.py`'s `AgentClient` (heartbeat/emit/notify,
all failure-swallowing) talks to the agent over `Config.get("IA_AGENT_URL")` with a bearer token
from the new `vars.py` `IA_AGENT_TOKEN` (env-only — never `config.env`, which syncs to the phone;
D26). Countdown publishing and `run_now`/`skip_wait` commands are not yet wired — that needs CP
3.4's heartbeat endpoint agent-side. Next up: CP 3.4 — the scheduler mirror in the agent.

All five flow switches (`ENTITY_INGEST/SCAN/CLASSIFY/SCRAPE/FOLLOW`) were restored to **ON** on
2026-07-31 when Phase 2 was accepted — the pipeline fires live flows on its normal schedule again.

**Startup is the agent's now (CP 2.5).** `agent/src/ia_agent/startup.py` — `install` / `remove` /
`status`, run as `uv run --project agent python -m ia_agent.startup <action>` — registers the
Task Scheduler logon task, flips the three `autostart` switches, and deletes the old shortcut after
checking its hash against the committed backup. The task's action is the **base** interpreter's
`pythonw.exe` (GUI subsystem, so no console window exists) running
`agent/scripts/ia_agent_launcher.pyw`, which starts `ia-agent.exe` with `CREATE_NO_WINDOW`, holds it
in a `KILL_ON_JOB_CLOSE` job object, logs to `%LOCALAPPDATA%\ia-agent\logs\startup.log`, and restarts
it on any non-zero exit — because `RestartOnFailure` does not (D21). `schtasks /End /TN ia-agent`
stops everything; `%LOCALAPPDATA%\ia-agent\stop-launcher` keeps it down. Full record and undo:
`backups/2026-07-31-agent-task/MANIFEST.md`.

`config.env` is fully controllable from the app (CP 1.1–1.4). The agent also supervises processes:
`agent/src/ia_agent/services/` holds the spec/probe/terminal-ring/supervisor engine plus the three
real service specs, exposed at `GET /api/services`, `PATCH /api/services/{name}` and
`POST /api/services/{name}/{start|stop|restart|takeover|test|resize}`. Services are spawned into a
**ConPTY owned by a detached host process** (`services/host.py`, CP 2.6, D23), not the agent itself,
and their output kept verbatim, which the app renders with `xterm.dart` as a real terminal rather
than a log list. Each service has a **self-heal** switch (persisted in `services.json`) and a
functional self-test; **autostart is on** for all three since CP 2.5, so after a logon the agent
spawns them and they read `supervised`. Until the next reboot they are still whatever the old
shortcut left running, which the agent reports as `external`. **A supervised service now survives
the agent dying, any way** — restart, crash, `taskkill /F` or `/F /T` — and comes back `adopted`
with its terminal history intact on the next agent start (D10's promise, finally true; D22 explains
what CP 2.5 measured before this landed). `GET /api/dependencies`
(CP 2.3) covers the ten things the pipeline needs but the agent does not supervise, and now has a
tab on the Services screen (D16).

The **Services** screen (`app/lib/features/services/`) is master–detail: tiles left, actions +
probe/test metrics + self-heal + terminal right, with *Dependencies* as a second tab. Two things
pin it: `agent/tests/test_ui_contract.py` for the payload shapes the app decodes (keep its field
tables in step with `app/lib/core/service_models.dart` and `dependency_models.dart`), and
`app/test/services_layout_test.dart` for overflow, which nothing else can see (D19).

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
   manual test the user runs **before** the commit. The test is the checkpoint — do not commit a UI
   checkpoint ahead of it, not even with "awaiting your test" in the message (done once, in CP 2.4;
   do not repeat). For UI work, `flutter test` runs as part of that gate: overflow is a paint-time
   error that `flutter analyze` and every agent-side test are blind to.
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

**Startup, since CP 2.5** — the `ia-agent` logon task, 15 s after logon, running
`pythonw.exe ia_agent_launcher.pyw` → `ia-agent.exe` → the three services. What it replaced was
`%APPDATA%\…\Startup\dev-startup.exe.lnk`, which despite the name was `wt.exe` with four tabs
(`adb -a start-server ; ollama serve ; start_vl_server.py ; wsl-bridge.exe`) — note `start-server`
*forks*, so that tab exited and nothing supervised adb. `ollama serve` is not carried over (D13);
`Ollama.lnk` starts it separately anyway. The `.lnk` is backed up and one command restores it.

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
   agent never *deliberately* stops services when it exits (D10) — though today they die with it
   regardless, because the pseudo-console is the agent's; CP 2.6 fixes that (D22). Supervisor state
   is lock-guarded (D9).
7. **The agent is the only supervisor.** Services' own restart loops are switched off
   (`start_vl_server.py --no-autorestart`), because nested supervisors fight each other and hide
   their restart counts (D14). Service output is a raw ConPTY stream kept verbatim — never
   line-strip it, that is what a terminal needs (D15).
8. **The agent's ring is the terminal's only source of truth** — the app replays it, dedupes live
   chunks by `seq` (overlap between a replay and the live stream is normal, a gap is not), and
   re-replays with `?since=` after a dropped WebSocket (D18). A pane with nothing real to render
   explains why instead of showing a one-line "terminal" (D17), and the dependency panel is the
   Services screen's second tab (D16).
9. **Startup is a logon task running a GUI-subsystem interpreter** (D20) — nothing else keeps a
   console window off the screen, because Task Scheduler has no window style and `<Hidden>` only
   hides the task in its own UI. The launcher, not `RestartOnFailure`, restarts the agent, and a job
   object stops `schtasks /End` from orphaning it (D21).

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
