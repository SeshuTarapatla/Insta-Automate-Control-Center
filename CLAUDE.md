# CLAUDE.md — Insta-Automate Control Center

Read this first, then [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and
[docs/PLAN.md](docs/PLAN.md). Current state: **Phases 0, 1 and 2 complete and accepted**, **Phase 3
complete and accepted** (CP 3.1–3.5, Trigger delays & conditions), **Phase 4 open, CP 4.1–4.3 done**
(Live logs & flow-aware imagery; log + event aggregation, flow instrumentation). Phase 2 accepted
2026-07-31 — the user accepted it outright without a separate CP 2.6 verification pass. The
`wt.exe` startup shortcut is gone: an `ia-agent` **logon task** starts
the agent, which starts the three services from their `autostart` switches (now on). What CP 2.5
measured — supervised services die with the agent — is closed by CP 2.6: the pseudo-console now
lives in a detached service-host process, so a service survives the agent dying any way (D23).
**Phase 3, CP 3.1–3.4** (Trigger delays & conditions; CP 3.1–3.3 in `Insta-Automate` on
`feat/control-center`, CP 3.4 in this repo's agent) landed first. `Limit` in `models/meta.py` is generalised
into typed `Config` (`Limit = Config` alias, no call sites changed), carrying every key from
ARCHITECTURE §4.1 with coded defaults for the ones not yet in `config.env`. Q3 is answered:
`PROFILES/REELS/POSTS` really are the live daily scan caps, and the `config.env` comment that said
otherwise is fixed (D24). `controllers/prefect.py`'s five trigger loops now sleep through
`wait_until(flow, key)`, which re-reads its `Config` key every tick so an edited delay re-targets a
wait already in progress (D25); the day-rollover fall-through is fixed with a `continue`, and
`SCRAPE_BACKPRESSURE_FACTOR` replaces the hardcoded `* 3`. New `controllers/agent.py`'s
`AgentClient` (heartbeat/emit/notify, all failure-swallowing) talks to the agent over
`Config.get("IA_AGENT_URL")` with a bearer token from the new `vars.py` `IA_AGENT_TOKEN` (env-only —
never `config.env`, which syncs to the phone; D26). The agent's own `ia_agent/scheduler.py`
(`SchedulerMirror`) now receives `POST /api/scheduler/heartbeat`, stores per-flow state, serves
`GET /api/scheduler`, queues commands via `POST /api/scheduler/{flow}/command`, and broadcasts the
full snapshot on `flows.state` when it changes, with a 3s watchdog for staleness (D27).
`Prefect.serve()` now closes the loop (D28): a `heartbeat_loop()` posts every flow's real state
every ~2s — each trigger loop sets its own `gate` (backpressure/day_limit/no_work, with the exact
detail string ARCHITECTURE §4.3 illustrates) right before whichever wait follows it, and
`wait_until` only ever updates `phase`/`next_trigger_at`, never touching `gate`, so the reason
survives the whole wait. Verified cross-process (a real `AgentClient` from the `Insta-Automate`
venv against a throwaway agent instance — two genuinely separate Python environments).
**Phase 3, CP 3.5 (Flows UI) is done and accepted, after several rounds of your live testing and
fixes (all in D29).** `heartbeat_loop()` actually queues the commands it receives now, and
`wait_until` wakes on `skip_wait`/`run_now`/`reload_config`/a pending `force_run` — the last one was
a real bug: it was only ever checked at the top of each trigger loop, so pressing Force Run while a
flow was mid-wait (fine on Scrape's short waits, silently broken on Follow's 20-minute one) queued
the command with nothing consuming it. `force_run` bypasses the rate gate (day-limit/backpressure)
*and* the `ENTITY_*` switch — corrected mid-session from "never the switch" once you pointed out
manual and scheduled triggers are two different things — but never a no-work gate, since force can't
invent a queued entity or file that doesn't exist. It's unconditionally enabled now too, not just
when something's blocking. `pause`/`resume`/`reload_config` stay accepted by the agent's REST layer
but unwired — no button asks for them. The Flows screen (`app/lib/features/flows/`) is five cards:
a smoothly-animating countdown ring (an earlier version reset to full every ~5s from deadline
jitter, fixed alongside the Force Run bug above), gate reason, today's counters, the switch, Run
now/Skip wait, Force run (confirmed, with optimistic "command sent…" feedback so a worker-pickup
delay can't invite a double-click), and a "View logs" link out to Prefect's own UI (CP 4.1's in-app
viewer doesn't exist yet). Also landed: a Settings > Limits "Timings" group exposing all eleven
trigger-timing keys (previously only hand-editable in `config.env`), `SCRAPE_BACKPRESSURE_FACTOR`
renamed to `SCRAPE_RESERVE_FACTOR`, the "triggering" phase renamed to "running" (it described a
flow's entire run, not a momentary state), and a worked-around maximized-mode title bar rendering
glitch (D29 — unverified by Claude directly, reasoned from your screenshots, since driving the app
is your job per rule 5). Verified without any live Telegram/DB/device call throughout — see D29 for
the full history, including the live pipeline verification technique (`GIT_BRANCH` env var pointing
a rebuilt image's flow deployments at `feat/control-center` for testing, reverts once merged).

**Phase 4 (Live logs & flow-aware imagery) is open, CP 4.1 (Log aggregation) done, agent-only, 🟢.**
New `ia_agent/flowruns.py`'s `FlowRunTailer`: active-run discovery prefers the scheduler heartbeat
(a `phase == "running"` flow's `last_run.id` already *is* the in-progress run — no pipeline change
needed), falling back to Prefect's `flow_runs/filter` when the mirror is offline; a per-run `Ring`
(same `seq`-replay discipline as the service terminal's, D18) polled via `logs/filter`, deduped at
the boundary by log id; the scheduler pod's own container log (where trigger/gate decisions print)
merged into every currently-active run's ring in append order, not a timestamp-sorted interleave —
reusing D18's precedent rather than inventing a second seq space (D30). New REST
(`GET /api/flow-runs[?limit=]` · `GET /api/flow-runs/{id}` · `GET /api/flow-runs/{id}/logs?since=`)
and WS channel `flowrun.logs`. Live verification against the real cluster caught two client-library
quirks before they could ship: the installed `kubernetes` package's generated bindings never wired
up `since_time` for pod log reads (switched to relative `since_seconds`, re-filtered by the caller),
and that same call hands back the literal string `b'...'` instead of decoded text for pod logs only
(unwrapped via `ast.literal_eval`) — both D30. Verified: `agent/tests/test_flowruns.py` (36/36,
Prefect/k8s calls monkeypatched) plus new read-only `check_flowruns.py` against the real Prefect
server and k3s cluster. All prior suites unchanged; `test_ui_contract.py`'s `terminal_available`
`KeyError` is a pre-existing issue (reproduces on a clean `main`, confirmed via `git stash`), not a
regression from this session. Nothing to test in the GUI yet — CP 4.4 is what puts this on screen.

**CP 4.2 (Event pipeline) done, agent-only, 🟢.** New `ia_agent/images.py`: content-addressed cache
(`cache(rel_path)` reads `IA_DIR/rel_path`, keys the bytes by sha256, tolerates the file already
being gone by returning `None` rather than raising — the race `entity_classify`/`entity_follow`'s
future `emit()` calls will sometimes lose), `thumbnail(key, width)` generated lazily and cached
alongside the original. New `ia_agent/events/store.py`'s `EventStore` accepts events as a loose
dict (same reasoning as `SchedulerMirror.heartbeat` — a validation error here is an event the
pipeline can never learn was dropped), assigns `seq`/`id`/`ts` when absent, caches any referenced
image inline, and publishes on `flow.events`. New REST: `POST/GET /api/events[?since=]`,
`GET /api/images/{key}`, `GET /api/images/{key}/thumb?w=` (clamped 16–2000px). Verified:
`agent/tests/test_events.py` (35/35 — content-addressing, the missing-file race, thumbnail
proportions/clamping, replay, and a live app exercising every endpoint plus a real WS delivery,
all against a scratch directory, never the real `IA_DIR` or cache). All other suites unchanged.
Nothing to test in the GUI yet, and no pipeline-side caller exists until CP 4.3.

**CP 4.3 (Flow instrumentation) done, cross-repo, `Insta-Automate` on `feat/control-center`, 🟡.**
Every ARCHITECTURE §5.1 table row now has a real `emit()` call: `entity.added`, `scan.started`/
`scan.item`/`scan.completed`, `scrape.started`/`scrape.skipped` (all four real reasons)/
`scrape.done` (real parsed posts/followers/following), `follow.attempt`/`follow.result` (all six
verdicts), `classify.access`/`classify.gender` — plus a `flow.started`/`flow.completed` pair added to
all five flow bodies beyond the table, giving CP 4.4's run summary an unambiguous whole-run boundary.
The absolute-path bug the plan called out is fixed alongside its emit call in `profile_scrape`/
`profile_follow`. `tasks/ollama.py`'s `remove_public`/`gender_classify` are plain sync functions, so
they use a new `controllers.agent.emit_sync` — which had to become a genuinely blocking `httpx.post`
after a first `create_task`-based version turned out to lose the exact image-deletion race the cache
exists to win, since neither function ever yields back to the event loop until it returns (D32).
**Also fixed, found only by live verification**: CP 4.1's `run_logs()`/`flow_runs_filter()` 422 above
Prefect's real `limit=200` cap — invisible to fakes, silently broken in production (no crash, no
tailed logs). Verified: import sanity-check on every changed pipeline module (no test suite there),
plus a live round trip against a throwaway agent instance confirming both `emit()` and `emit_sync()`
actually reach `POST /api/events`. Nothing deployed to the live pod yet.

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
