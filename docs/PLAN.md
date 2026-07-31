# Insta-Automate Control Center — Implementation Plan

> Read [ARCHITECTURE.md](ARCHITECTURE.md) first. This document is the build order.
> Every checkpoint (`CP`) is a **commit boundary** with a manual test you can run yourself.
> Phases are ordered so that each one delivers standalone value even if the next never ships.

**Legend** — 🟢 this repo · 🟡 `Insta-Automate` (`feat/control-center`) ·
🔵 `Insta-Automate-Client` (`feat/lan-agent`) · 🟣 `Helmcharts` (`feat/control-center`)

---

## Phase 0 — Foundations

Goal: a repo that builds, an agent that answers, a window that opens.

### CP 0.1 — Repo scaffold 🟢
- Layout: `app/` (Flutter), `agent/` (Python/uv), `docs/`, `CLAUDE.md`, `MEMORY.md`.
- **Replace `.gitignore`** — the current file is the Flutter *SDK repo's* ignore list
  (`/bin/cache/`, `/dev/benchmarks/`, …), not an app's. Two concrete bugs in it:
  `*.lock` would exclude `pubspec.lock` and `uv.lock` (both must be committed for an
  application), and it has no Python/uv/`__pycache__`/`.venv` rules at all.
- Seed `docs/DECISIONS.md` with the four decisions taken in the planning session.

**Test:** `git status` clean; `pubspec.lock` and `uv.lock` are tracked once they exist.

### CP 0.2 — Agent skeleton 🟢
- `agent/pyproject.toml` (uv, py≥3.12), console script `ia-agent`, dependencies:
  `fastapi uvicorn httpx pydantic python-dotenv watchfiles adbutils psutil sqlmodel
  psycopg2-binary kubernetes telethon my-modules pillow`.
- `main()` → uvicorn on `0.0.0.0:8787`; `GET /api/health`; bearer-token middleware; token
  generated on first run at `%LOCALAPPDATA%\ia-agent\token`.
- Structured logging reusing `my_modules.logger`.

**Test:** `uv run ia-agent`, then `curl -H "Authorization: Bearer $(cat token)" localhost:8787/api/health`.

### CP 0.3 — Flutter shell 🟢
- `flutter create app --platforms=windows`; Material 3 dark, custom title bar
  (`window_manager` + `flutter_acrylic`), persisted window geometry.
- Navigation rail with all seven destinations (placeholder bodies).
- Riverpod providers: agent client (`dio`), WS connection, connection-state banner with
  Retry / *Start agent*.

**Test:** app opens, shows **Agent: connected**; stop the agent → banner appears within 3 s;
click *Start agent* → reconnects.

---

## Phase 1 — Config control · solves expectation #1

Goal: never edit a limit by hand again.

### CP 1.1 — Config engine 🟢
- `config/env_file.py` — read/write `IA_DIR/config.env` preserving comments, blank lines,
  key order, and unknown keys verbatim (mirror the semantics of the mobile app's
  `env_service.dart`). Atomic write via temp-file + replace.
- `config/schema.py` — typed key registry: name, group, type, default, range, help text.
  Defaults must match `Limit._DEFAULTS` exactly.
- `watchfiles` watcher → `config.changed` WS broadcast on external edits (Syncthing, mobile,
  manual).

### CP 1.2 — Config API 🟢
- `GET /api/config` (values + schema + provenance), `GET /api/config/schema`,
  `PATCH /api/config` with validation: ranges, and cross-checks such as
  `SCRAPE_BATCH ≤ SCRAPE`, `FOLLOW_BATCH ≤ FOLLOW`, `FMIN < FMAX`.

### CP 1.3 — Limits UI 🟢
- Limits screen: cards grouped Scan / Scrape / Follow, each key with a slider + numeric field,
  inline help, dirty indicator, instant apply with undo, and a "changed externally" toast wired
  to `config.changed`.

### CP 1.4 — Switches UI 🟢
- Five flow switches, confirm-on-disable, and the shared `ENTITY_QUEUE` priority list with
  drag-reorder (**see Q1 — this list is currently shared by scrape *and* follow**).

**Test:** change `FOLLOW` 60 → 80 in the app; `cat config.env` shows the new value with all
comments intact; a pod picks it up on its next `Limit.get()` with no restart.

---

## Phase 2 — Core services · solves #3 #4 #5 #6

Goal: start, stop, restart and *prove* each Windows service from the UI.

### CP 2.1 — Supervisor engine 🟢
- `ServiceSpec` (cmd, cwd, env, probe, autostart, restart policy, backoff).
- Spawn with piped stdout/stderr → per-service ring buffer (5k lines) + WS broadcast +
  rotating file. PID file per service.
- **Adoption on agent start**: PID file alive and healthy → adopt (flag stdout as unavailable);
  port held by a foreign PID → mark `external` and offer takeover. This is what lets the agent
  restart without killing a running scrape.

### CP 2.2 — The three services + self-tests 🟢

| Service | Command | Health probe | Functional test |
|---|---|---|---|
| `adb` | `adb -a nodaemon server start` (foreground, so it is supervisable — unlike today's `start-server`) | TCP 5037 + `adb devices` contains `ANDROID_SERIAL` | `adb -s <serial> shell echo ok` |
| `vl-server` | `D:\Coding\Insta-Automate\.venv\Scripts\python.exe D:\Coding\Insta-Automate\scripts\start_vl_server.py` | `GET 127.0.0.1:11500/v1/models` | real inference on a bundled fixture jpg → assert the JSON schema parses, **report ms/image** |
| `wsl-bridge` | `D:\Coding\wsl-bridge\.venv\Scripts\wsl-bridge.exe` | `GET 127.0.0.1:8000/` → `true` | `POST /scrcpy/start` → `GET /scrcpy/` is `true` → `POST /scrcpy/stop` |

The vl-server test is the valuable one: it is the difference between "port is open" and
"classification actually works at 0.2 s/img instead of 12 s/img".

### CP 2.3 — Dependency panel (read-only) 🟢
k3s reachable · postgres · prefect server + worker + work-pool has a live worker ·
`insta-automate` and `insta-automate-worker` pod phases and restart counts · ADB device present ·
internet · Syncthing running · free space on the `IA_DIR` volume.

### CP 2.4 — Services UI 🟢
Status tiles (state, uptime, restart count, probe latency), Start / Stop / Restart / Test,
and a per-service log console with level filter, search, follow-tail, and copy.

### CP 2.5 — Agent autostart 🟢
Install a Startup-folder shortcut (or Task Scheduler logon task) that launches `ia-agent`,
which then starts the three services per their `autostart` policy. **Retire the current
`wt.exe …` shortcut** (keep a documented rollback).

**Test:** kill `llama-server.exe` from Task Manager → the tile goes red within one probe
interval → *Restart* → green, and *Test* reports a plausible ms/image. Reboot the laptop →
everything comes up with the old shortcut removed.

---

## Phase 3 — Trigger delays & conditions · solves #2

Goal: change any delay from the UI, see exactly when the next run fires and why it might not.

### CP 3.1 — Typed live config 🟡
`models/meta.py`: generalise `Limit` into `Config` (typed get with defaults for int/float/
bool/str), keep `Limit` as an alias so no existing call site changes. Add every key from
ARCHITECTURE §4.1. Fix the stale `PROFILES/REELS/POSTS` comment in `config.env`.

### CP 3.2 — Config-driven scheduler 🟡
In `controllers/prefect.py`:
- every hardcoded `wait` / `buffer` / `sleep` → `Config.get(...)`;
- `wait_until()` interruptible sleep (TICK granularity, re-reads config, returns wake reason);
- `SCRAPE_BACKPRESSURE_FACTOR` replaces the hardcoded `* 3`;
- **fix** the day-rollover fall-through — re-fetch `Scan`/`Scrape`/`Follow` after
  `wait_day_change()` before evaluating the gate;
- `SCAN_WAIT` cooldown between scan runs (default `0` = today's behaviour, so this is a no-op
  until you set it — see Q2).

### CP 3.3 — Agent client in the pod 🟡
New `controllers/agent.py`: `AgentClient` with heartbeat (2 s), event emit, notify — every
method swallows failures so the agent being down is invisible to the pipeline. Heartbeat
publishes the per-flow state block from ARCHITECTURE §4.3 and drains commands from the response.

### CP 3.4 — Scheduler mirror in the agent 🟢
`POST /api/scheduler/heartbeat`, in-memory state store, command queue, `flows.state` WS channel,
plus staleness detection (no heartbeat for 15 s → scheduler shown as offline).

### CP 3.5 — Flows UI 🟢
Five flow cards: countdown ring to `next_trigger_at`, the gate reason in plain language, today's
counters against the limit, the switch, **Run now** (respects gates) and **Force run** (bypasses,
with confirmation), last run state + duration + a jump to its logs.

**Test:** while `entity_follow` is waiting, change `FOLLOW_WAIT` 1200 → 120 — the countdown
re-targets within one TICK. Press *Skip wait* → it fires immediately. Turn the switch off → the
card reads "skipped: switch OFF". Fill `follow_queued` past the threshold → the scrape card
explains `scraped+follow_queued = 180 ≥ FOLLOW×3 = 180`.

---

## Phase 4 — Live logs & flow-aware imagery · solves #7

Goal: the showpiece screen.

### CP 4.1 — Log aggregation 🟢
Prefect log tailer (incremental by timestamp cursor, ~1 s per active run), active-run discovery
from the heartbeat with a `flow_runs/filter` fallback, and the scheduler pod's container log
merged in via the k8s API. Unified log model: ts, source, level, task, message.

### CP 4.2 — Event pipeline 🟢
`POST /api/events`; **cache image bytes on receipt** (content-addressed under
`%LOCALAPPDATA%\ia-agent\cache`), generate thumbnails, serve `GET /api/images/{key}`; replay ring
buffer; `flow.events` WS channel. Resolve IA_DIR-relative paths against the Windows `IA_DIR`.

### CP 4.3 — Flow instrumentation 🟡
Add `emit()` next to the existing log lines at every point in the ARCHITECTURE §5.1 table —
`tasks/ia.py` (`profile_entity_scan`, `post_entity_scan`, `profile_scrape`, `profile_follow`,
`add_new_entity`), `tasks/ollama.py` (`remove_public`, `gender_classify`), and the five flow
bodies for started/completed. **Always relativise paths to `IA_DIR`** — `profile_scrape` and
`profile_follow` currently log absolute paths.

### CP 4.4 — Live screen 🟢
Three panes: log console (auto-follows the active run, level filter, task grouping, sticky
errors) · flow-specific visualization surface (per-kind layouts for the three aspect ratios) ·
run summary with counters and the device pane.

Per-flow surfaces: scan → live-growing strip filmstrip with `added/scanned`; classify → verdict
card stream with running img/s; scrape → before→after morph plus reason chips carrying real
numbers; follow → profile report with outcome; ingest → hero page cards.

### CP 4.5 — Device view 🟢
Primary: control the native scrcpy window through wsl-bridge, positioned with
`my_modules.win32.snap_window`. Secondary (opt-in, low fps): `adb exec-out screencap` frames
streamed over `device.mirror` so the phone can watch too. See Q6.

**Test:** trigger `entity_scrape` and watch each queued row strip resolve into a profile report
or a reason chip showing the actual follower count, live, with no gaps where files were deleted.

---

## Phase 5 — Library & curation parity

Goal: review the backlog on a 16-inch screen instead of a phone.

### CP 5.1 — Library API 🟢
Folders, entities, and images with cached counts (invalidated by the `IA_DIR` watcher, seeded
from a background scan — 7.5k files means naive `rglob` per request is not acceptable).
Thumbnail service. `library.changes` WS channel.

### CP 5.2 — Mutations 🟢
`apply` (move selected to the folder's configured target, delete the rest), `delete`, and queue
add/remove/reorder. Use `send2trash` so semantics match the Python side and mistakes are
recoverable. Every mutation is confirmed and reported.

### CP 5.3 — Library UI 🟢
Virtualized grid, keyboard-driven multi-select (arrows, space, shift-range, ctrl-A), zoom
levels, per-folder move targets mirroring the mobile app's mapping, double-tap to copy id,
long-press/context-menu to open the Instagram URL (reuse the `reel-` / `post-` / account
resolution rules).

### CP 5.4 — Entity view 🟢
One entity across every stage at once, with DB-backed yield: scanned → private → female →
scraped → followed. This is the genuinely new capability — it tells you which source entities
are worth queueing.

**Test:** clear a 118-entity `scrape_queued` backlog from the desktop; counts stay correct
throughout; the mobile app agrees after Syncthing settles.

---

## Phase 6 — Mobile pairing & notification rework · solves #8

### CP 6.1 — Pairing + notification core 🟢
`/api/pair/*`, device tokens, revocation, the `notifications` channel, and a persisted
notification store with unread state and history.

### CP 6.2 — Notifier facade 🟡
`controllers/notify.py`, `NOTIFY_POLICY`, and conversion of all seven call sites
(ARCHITECTURE §6), preserving `transient` and dedupe semantics. Telegram stays the backstop.

### CP 6.3 — Desktop pairing & notification center 🟢
QR screen, paired-device list with last-seen and revoke, notification center with history and
per-tag mute.

### CP 6.4 — Mobile client 🔵
QR scan (`mobile_scanner`), agent client, foreground-service WebSocket
(`flutter_foreground_task`), local notifications, a compact live flow view, and config writes
through the agent when connected with the existing Syncthing path as the offline fallback.

**Test:** pair the phone; run a flow; the notification lands in under a second **with its image**.
Kill the mobile app → the next notification arrives on Telegram instead.

---

## Phase 7 — Ops & insight · solves #9

### CP 7.1 — Ops panel 🟢 🟣
`ia build`, `helm upgrade`/`uninstall`, pod restart, `prefect-k3s purge`, `ia db backup`/`restore`
— each with streamed output on `ops.logs`. Surface `IA_AGENT_URL`/`IA_AGENT_TOKEN` through helm
values so they change without an image rebuild. This closes the loop on the
*change → commit → build → undeploy → deploy* chore for the cases that still need a rebuild,
and retires the hand-run `kubectl` undeploy/redeploy cycle (EXPECTATION.md complexity #9).

Note that Phases 1 and 3 already remove *most* of the reason to redeploy at all: limits and
delays become live-read config, so the rebuild chore stops applying to the changes you make
most often. Phase 7 covers what genuinely still needs an image or a chart change.

### CP 7.2 — Insights 🟢
Funnel charts, daily limit burn-down history, per-entity yield ranking, and a classify-accuracy
sampling view (show N random verdicts with their images and let you mark disagreements — that is
how you find out the prompt has drifted).

### CP 7.3 — Polish 🟢
Theming, tray icon, global hotkey, empty/error/loading states everywhere, first-run onboarding,
keyboard shortcut cheat sheet.

---

## Phase 8 — Hardening

Firewall rule automation for TCP 8787 (one-time elevation), optional self-signed TLS with SPKI
pinning in the pairing QR, agent self-update, crash reporting, and the secret rotation from
ARCHITECTURE §10.

---

## Open questions

Answer these as they come up — none of them block starting Phase 0.

**Q1 — Shared queue.** `Queue(FOLLOW_QUEUE_DIR)` and `Queue(SCRAPE_QUEUE_DIR)` both use
`env_key="ENTITY_QUEUE"`, so one ordered list drives both the scrape and follow priority.
Intentional, or should it split into `SCRAPE_QUEUE`/`FOLLOW_QUEUE` keys? Splitting is a
behaviour change in the flows, so it needs your call before I build the queue UI.

**Q2 — Scan cooldown.** `entity_scan` has no inter-run delay today: the trigger blocks until the
flow finishes, then sleeps 10 s. Scan is the most rate-limit-sensitive flow. Do you want a real
`SCAN_WAIT` cooldown, and if so what default? (Planned as `0` = no behaviour change.)

**Q3 — Scan limits.** Confirm `PROFILES`/`REELS`/`POSTS` are genuinely the live daily scan caps
(the code says yes, the `config.env` comment says no) so the UI labels them honestly.

**Q4 — Startup ownership.** Replace the `wt.exe` shortcut with the agent (recommended), or leave
the shortcut in place and have the agent adopt whatever is already running?

**Q5 — Force run.** Should *Run now* ever bypass the daily limits, or only the wait? Planned:
*Run now* respects every gate, *Force run* bypasses with a confirmation dialog.

**Q6 — Device mirror.** Native scrcpy window on the desktop (cheap, already works) with streamed
frames only as an opt-in remote glance for the phone — or streamed frames everywhere? Streaming
costs device CPU while a flow is driving the UI.

**Q7 — Adding entities.** Should the app's *Add entity* post the URL to the Telegram entity
channel (zero flow changes; the existing `NewMessage` handler fires ingest instantly), or write
to the DB directly? Recommended: post to Telegram.

**Q8 — Notification taxonomy.** Which events deserve a phone notification versus a quiet feed
entry? Current candidates: limit reached (scan/scrape/follow), new entities classified, new
entities scraped, scan complete / unfollow prompt, device disconnected, flow failed, service
down. And how long should history be kept?

**Q9 — Laptop locked / away.** Should the agent keep everything running when the machine is
locked, and should the desktop app suppress the device mirror when it is not visible?

**Q10 — Secrets.** The committed `Insta-Automate/Dockerfile` exposes the Postgres password, the
bot token, and two Telethon session strings (ARCHITECTURE §10). Rotate and purge from history
now, or after the control center is up?

**Q11 — Firewall.** Is it acceptable for the agent to add its own inbound rule for TCP 8787 on
first run (needs one elevation prompt), or would you rather add it manually?

---

## Session discipline

Per your working rules:

- Cross-repo work happens only on the feature branches named at the top of this file and is
  **never merged** until you accept the control center.
- Every checkpoint ends with a commit and a manual test you run.
- **Every UI test in this document is yours to perform, not Claude's** (EXPECTATION.md #8).
  Claude builds, analyzes and starts the app, then hands over and waits. It never clicks,
  navigates or screenshots the window — single screen, VS Code maximized. Agent-side checks
  (REST, WS, `config.env` round-trips) Claude still verifies itself.
- Decisions land in [DECISIONS.md](DECISIONS.md); durable context lands in
  [../CLAUDE.md](../CLAUDE.md).
- A natural session boundary is one phase (or one checkpoint for Phases 4 and 5, which are
  large). I will tell you when a session's goal is met and it is time to open a fresh one.
