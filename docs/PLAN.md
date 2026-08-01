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
- A `config.env` bar at the top of the screen showing the real path (served by the agent, so
  `IA_DIR` is resolved in one place) with **Open** in the default editor (`Ctrl+E`), *Show in
  folder*, and *Copy path*. Opening goes through Win32 `ShellExecute` for the same
  no-console-flash reason as DECISIONS D5.

### CP 1.4 — Switches UI 🟢
- Five flow switches in pipeline order, confirm-on-disable (the dialog names what actually stops),
  and the shared `ENTITY_QUEUE` priority list with drag-reorder. Q1 is answered — the list stays
  shared (D8), so the queue UI shows each entity's `scrape` *and* `follow` counts, and states that
  unlisted entities still run afterwards, oldest first.
- Settings is organised as three tabs — Flows · Limits · Queue — under a persistent `config.env`
  bar, rather than one long scrolling page.
- New agent endpoint `GET /api/queue`: the ordering resolved against both stage directories, with
  per-entity jpeg counts and an `has_entity_image` flag (`Queue.add()` rejects entities without
  `entities/<id>.jpg`).

**Test:** change `FOLLOW` 60 → 80 in the app; `cat config.env` shows the new value with all
comments intact; a pod picks it up on its next `Limit.get()` with no restart.

---

## Phase 2 — Core services · solves #3 #4 #5 #6

Goal: start, stop, restart and *prove* each Windows service from the UI.

### CP 2.1 — Supervisor engine 🟢 ✅ done
- `ServiceSpec` (cmd, cwd, env, probe, autostart, restart policy, backoff).
- Spawn with piped stdout/stderr → per-service ring buffer (5k lines) + WS broadcast +
  rotating file. PID file per service.
- **Adoption on agent start**: PID file alive and healthy → adopt (flag stdout as unavailable);
  port held by a foreign PID → mark `external` and offer takeover. This is what lets the agent
  restart without killing a running scrape — **except that it does not yet**: CP 2.5 measured that a
  ConPTY-spawned service dies with the agent whatever kills it, so there is nothing left to adopt.
  CP 2.6 makes this bullet true; D22 explains why it is deferred rather than reverted.
- Also landed here (needed to make the engine testable at all): `services/registry.py` with the
  three real specs — `autostart` off, since everything is already up under the startup shortcut —
  and the REST surface `GET /api/services`, `GET /api/services/{name}[/logs]`,
  `PATCH /api/services/{name}`, `POST /api/services/{name}/{start|stop|restart|takeover|resize}`
  on `services.status` / `services.logs.<name>`. **CP 2.2 keeps** the health-probe and
  functional-test work.
- Takeover kills the *service root*, not the socket owner (D11); state is lock-guarded (D9);
  shutdown deliberately leaves services running (D10).
- **Revised after review, same checkpoint:** services are spawned into a **ConPTY** and their
  output kept verbatim so the app can render a real terminal (D15); the agent takes over restart
  duty from the services' own loops — `start_vl_server.py --no-autorestart`, adb as `nodaemon`
  (D14); `ollama serve` is dropped (D13); and `self_heal` / `autostart` are per-service switches
  persisted in `services.json` (D12).

**Test (agent-side, already verified by Claude):** 53/53 supervisor checks (ConPTY capture with a
real tty / colour / carriage returns, crash → backoff → self-heal, self-heal off → failed, flipping
it on rescuing a failed service, wedged-but-alive restart, adoption across an agent restart, stale
PID file, external detection + takeover) and 25/25 end-to-end REST+WS checks, both against a dummy
service. Against the live machine, all three real services were detected `external` with correct
kill targets and correct probes, and none was touched.

### CP 2.2 — The three services + self-tests 🟢 ✅ done

| Service | Command | Health probe | Functional test |
|---|---|---|---|
| `adb` | `adb -a nodaemon server start` (foreground, so it is supervisable — unlike today's `start-server`) | TCP 5037 + `adb devices` contains `ANDROID_SERIAL` | `adb -s <serial> shell echo ok` |
| `vl-server` | `…\.venv\Scripts\python.exe …\scripts\start_vl_server.py --no-autorestart` (the flag hands restart duty to the agent — D14) | `GET 127.0.0.1:11500/v1/models` | real inference on a bundled fixture jpg → assert the JSON schema parses, **report ms/image** |
| `wsl-bridge` | `D:\Coding\wsl-bridge\.venv\Scripts\wsl-bridge.exe` | `GET 127.0.0.1:8000/` → `true` | `POST /scrcpy/start` → `GET /scrcpy/` is `true` → `POST /scrcpy/stop` |

`POST /api/services/{name}/test` runs these on demand; the result is kept as `last_test` in the
status and narrated into the service's terminal. A failing test returns **200**, not an error —
a failed test is an answer, and the UI needs its metrics either way.

Measured on this machine when it landed:

| Service | Probe | Test |
|---|---|---|
| `adb` | 12 ms — `tcp open; device 159555486700071 attached` | 125 ms — `I2201 responded to a shell command` |
| `vl-server` | 11 ms — `GET /v1/models → 200` | **151 ms/image warm** (436 cold), **231 prompt tokens**, verdict parses to the pipeline's enum |
| `wsl-bridge` | 14 ms — `GET / → 200` | 20 ms — `scrcpy already mirroring, left running` |

Three things worth knowing about how these ended up:

- **`prompt_tokens` is the real assertion, not the clock.** The fixture is 1080×198 and costs 231
  tokens under `--image-min-tokens 64`; under Ollama's hardcoded 1024 the same crop costs ~1067 and
  the CPU CLIP encode takes 7–12 s. Token count catches that regression exactly and, unlike
  wall-clock, does not move with machine load. The test fails above 800.
- **The vl-server test warms up first.** Cold was measured at 420–750 ms against ~150 ms warm, and a
  real classify run does images back to back — reporting the cold number would overstate the steady
  state by 3–5× and read like a regression that is not there.
- **The wsl-bridge test refuses to be rude.** `POST /scrcpy/start` calls `stop()` on the way in
  (`wsl_bridge/scrcpy.py:23`), so cycling it would kill a mirror in use and throw a new scrcpy
  window onto the screen. When scrcpy is already running the test asserts the control plane answers
  and leaves it alone; it only does the full start→confirm→stop cycle when nothing is mirroring.

The fixture (`services/fixtures/row_crop.jpg`) is **synthetic** — a real row crop would put someone's
Instagram profile picture in the repo, and what the test measures depends on the dimensions, not the
subject.

Also landed: `probe_extra`, a per-spec semantic check that runs after the port probe passes. adb is
why it exists — a listening adb server with no phone attached is green on port and useless to the
pipeline, so its probe now reads `tcp open; device <serial> attached` and goes `unhealthy` when the
phone drops.

### CP 2.3 — Dependency panel (read-only) 🟢 ✅ done
k3s reachable · postgres · prefect server + work-pool has a live worker ·
`insta-automate` and `insta-automate-worker` pod phases and restart counts · ADB device present ·
internet · Syncthing running · free space on the `IA_DIR` volume.

`GET /api/dependencies` (`?refresh=true` to bypass the 5 s cache). Ten checks run concurrently,
each individually timed out at 10 s, each reporting `ok` / `warn` / `fail` with a sentence and
metrics. Always 200 — a failing dependency is the answer, not an error — and a check that raises
becomes a `fail` naming its own exception rather than a 500 for the whole panel.

Measured live, all green in 886 ms cold / 105 ms warm:

```
k3s             k3s API reachable — v1.34.3+k3s3 (linux/amd64)
postgres        insta_automate on PostgreSQL 18.3 — 6 tables, 30 MB
prefect-server  Prefect server healthy — 3.6.27
prefect-pool    insta-automate-pool served by 1 worker(s)
pod-scheduler   1 pod(s) Running, 0 restart(s)
pod-worker      1 pod(s) Running, 0 restart(s)
adb-device      device 159555486700071 attached
internet        reachable
syncthing       running (pid 10392, 10952)
disk            120 GB free of 425 GB on C:
```

Notes for whoever touches this next:

- **Pods are matched by derived deployment name, never by prefix.** `insta-automate` is a prefix of
  `insta-automate-worker`, *and* this chart gives both deployments the same `app: insta-automate`
  label — so neither the name prefix nor the label can separate them. `kube._deployment_of()`
  strips the `-<pod-template-hash>-<suffix>` a Deployment adds, which recovers the deployment
  exactly. The roles are also easy to swap by mistake: `server.yaml` runs `ia prefect serve` (the
  **scheduler**, i.e. the trigger loops), `worker.yaml` runs the Prefect worker that executes flow
  runs.
- **The work-pool check asks whether a worker is ONLINE**, not merely whether the pool exists — a
  deployment submitted to an unattended pool sits in Pending forever, which "pool exists" would
  call healthy.
- **Postgres credentials are never in this repo.** `my_modules.postgres.PostgresSecret` reads the
  k3s `postgres-secret`, the same path the pipeline uses. Consequence worth knowing: when k3s is
  down, the postgres row reports a credential failure rather than a database failure, and says so.
- Syncthing missing is a **warn**, not a fail — it means the phone stops seeing new images, not
  that a run breaks. Disk warns under 25 GB, fails under 8 GB.

### CP 2.4 — Services UI 🟢 ✅ done, user-verified
Status tiles (state, uptime, restart count, probe latency), Start / Stop / Restart / Test, and a
**self-heal toggle per tile** (off means a crashed service stays down with its exit code and final
output on screen — D12).

The log pane is a **real terminal**, not a list of strings: `xterm.dart` fed the raw ConPTY stream
from `services.logs.<name>`, with `GET /api/services/{name}/logs?since=` for replay on reconnect
and `POST /api/services/{name}/resize` wired to the pane's measured rows/cols so full-width output
wraps correctly (D15). Selection, copy and search come from the emulator. Adopted and external
services report `terminal_available: false` — the pane says why it is empty instead of showing a
blank box.

**What landed** — `app/lib/features/services/`: a master–detail screen (tile list left, detail and
terminal right) plus a second tab that finally puts CP 2.3's dependency panel on screen (D16).
`app/lib/core/service_models.dart` and `dependency_models.dart` mirror the agent's payloads. The
five things worth knowing:

- **The pane explains itself rather than rendering an empty terminal (D17).** All three real
  services are `external` today, and an external service's ring holds exactly one chunk — the
  agent's own note that the port was taken. Rendering that would be a "terminal" containing one dim
  line about itself, so external and adopted services get a card naming the reason and the fix
  instead. A *stopped* service is different: its ring is real output, so it keeps the terminal with
  a banner saying the output is history.
- **The terminal dedupes by `seq`, because overlap is normal.** The ring is written by the reader
  thread the instant a process prints; the WS batch for those same chunks goes out on the next tick
  up to 250 ms later. So replay-then-subscribe legitimately delivers chunks twice. Live chunks that
  arrive mid-replay are held back and merged by sequence, and a dropped WebSocket re-replays from
  `?since=<last rendered>` rather than from the top.
- **Uptime is grown on the client.** A status is only broadcast when its signature changes, so a
  service healthy for an hour sends nothing; the tile adds wall-clock since the snapshot arrived.
- **Action requests get their own timeouts.** The client default is 2 s, but `stop` waits out a 5 s
  terminate grace and a cold vl-server test does real inference — 20 s for actions, 60 s for tests.
- **Autostart is on screen but labelled as pending**, since it only takes effect at CP 2.5.

**Verified (agent side, `agent/tests/test_ui_contract.py`, 49/49):** every payload the app decodes,
against a dummy registry plus one deliberately foreign process — enum parity, full status shape on
every action, replay/live/`since=` sequence continuity with no gaps, `resize` actually reshaping the
child's console (173×24 read back from inside the process), the test outcome and its metrics, the
external/takeover shape, and the 409 `detail` sentence the UI shows. The existing suites still pass
(57/57, 32/32, 26/26). The GUI itself is yours to test — see the checklist below.

**Found in your test, and now guarded:** a 43 px overflow in the metrics row — vl-server's `model`
metric is the resolved blob path, ~110 characters, and `Wrap` hands its children unbounded width.
Long values now take their own full-width line with the whole path in a tooltip. Chasing it with
`app/test/services_layout_test.dart` (10 cases) turned up three more the screenshot could not show:
a **199 px vertical** overflow at the 1024 px minimum window (the panels above the terminal want
~850 px there, so `Expanded` was handed negative space — they are now capped at everything except
the terminal's 220 px floor and scroll among themselves, a maximum rather than a share, so a tall
window still gives the terminal every spare pixel), a 30 px overflow in a tile, and a header that
its own buttons could starve.

Two things worth keeping: **overflow is a paint-time error**, invisible to `flutter analyze` and to
every agent-side test, so `flutter test` is now part of this checkpoint's gate. And **test at the
size the screen actually produces** — the first version of that test used 560 and 1400 px and
reproduced none of it; the reported bug needs ~1250, which is what a maximized 1920 window leaves
after the rail and the tile list.

**Test (yours):** open **Services**. All three services should read `external` with a *Take over*
button and a card explaining that the startup shortcut owns them. Take over **wsl-bridge** (the
least disruptive — nothing is mirroring): the tile should go supervised, the terminal should fill
with its real output in colour, and *Test* should report a scrcpy round trip. Resize the window and
confirm the output rewraps rather than breaking. Turn self-heal off, kill that process from Task
Manager, and confirm the tile goes red and *stays* red with its exit code and final output; turn
self-heal back on and it should come back by itself with the restart count incremented. Then check
the **Dependencies** tab shows ten green rows and *Re-check* re-runs them.

### CP 2.5 — Agent autostart 🟢 ✅ done, user-verified
`dev-startup.exe.lnk` — a `wt.exe` shortcut with four tabs (`adb -a start-server ; ollama serve ;
start_vl_server.py ; wsl-bridge.exe`) — is **gone**, replaced by a Task Scheduler logon task named
`ia-agent`. The agent now starts at logon and starts the three services from their `autostart`
switches, which this checkpoint turned on. Answers **Q4**.

**What landed** — `agent/src/ia_agent/startup.py` (`install` / `remove` / `status`, run as
`uv run --project agent python -m ia_agent.startup <action>`) and
`agent/scripts/ia_agent_launcher.pyw`, the process the task actually runs. Install registers the
task from generated XML, flips `autostart` on for all three services, and deletes the shortcut only
after checking its SHA-256 against the committed backup; `remove` puts the shortcut back and turns
the switches off again, so the rollback is one command. It is deliberately **not** in the UI — a
once-per-machine act with a documented rollback is not a button to press twice.

Four things about Windows decided the shape, each measured rather than reasoned (D7's rule):

- **The task must start a GUI-subsystem exe** (D20). Task Scheduler exposes no window style, and
  `<Hidden>true</Hidden>` hides the *task in the Task Scheduler UI*, not the window. Under a real
  interactive logon task, `python.exe` showed a visible console for its whole run — and so did the
  venv's `pythonw.exe`, a uv trampoline that re-execs the console interpreter (the pid on screen was
  not the pid the task started). The base interpreter's `pythonw.exe` reported
  `GetConsoleWindow() == 0` with no window visible from outside, so that is the action, against the
  launcher.
- **`CREATE_NO_WINDOW` must be passed alone.** Windows ignores it when `DETACHED_PROCESS` or
  `CREATE_NEW_CONSOLE` is also set; combining them was the first attempt and it put a console window
  on screen. The app's *Start agent* button was re-measured on the same run and is clean — no visible
  window anywhere in `uv.exe → ia-agent.exe → python.exe`.
- **`RestartOnFailure` does not heal a crashed agent** (D21) — which was the stated reason for
  choosing a task over a shortcut. With `PT1M`/3 configured, a killed agent left the task at
  `Last Result: 1`, `Status: Ready`, and nothing restarted for three minutes. So the launcher waits on
  the agent and restarts it itself (5 s → 300 s backoff, reset after two healthy minutes, stopping on
  a clean exit or on a `stop-launcher` sentinel), and the logon trigger repeats every 10 minutes with
  `IgnoreNew` as the outer net for the launcher dying. The repetition net was measured too: a killed
  task was running again 55 s later.
- **`schtasks /End` used to orphan the agent** — it killed the launcher and left the agent serving on
  8787 with a dead parent, so the documented way to stop it left something holding the port the next
  run needs. The launcher now holds the agent in a job object with `KILL_ON_JOB_CLOSE`, and `/End` is
  genuinely "stop everything".

**The load-bearing measurement, and why it did not stop this checkpoint** — a service spawned into a
ConPTY dies with the agent on *every* death: a clean `sys.exit`, a `/F` kill and a `/F /T` tree-kill
all took it. D10 has therefore been false since services moved into pseudo-consoles in CP 2.1, and
the adoption tests missed it because they build two `Supervisor`s in one process, where the pty
handles never close. The fix is measured and works — see **CP 2.6** — and is its own checkpoint. Until
then the loop is: agent dies → its services die → the launcher restarts the agent → the agent restarts
them from their switches. Seconds of downtime, self-healing, and no flow survives it (D22).

**Verified (Claude, live on this machine):** the task's whole process tree
(`pythonw.exe → ia-agent.exe → python.exe → python.exe` + a conhost) with **no visible window**, the
agent answering on 8787, and the three services detected `external` and **untouched** — same pids
before and after. Then the agent killed outright: back in **5 s**, services still untouched. Then
`schtasks /End`: nothing of the task's left running, port closed, services still untouched.
`agent/tests/test_startup.py` (20/20) pins what a later edit could quietly break — the action's PE
subsystem is 2, the flags, the launcher's restart policy, and the job object really killing a child
when its handle closes. The other suites still pass (57/57, 32/32, 49/49).

**Test (yours) — passed:** rebooted the laptop; everything started as expected, no terminal window
anywhere, the agent and three services came up cleanly on their own. `uv run --project agent python
-m ia_agent.startup status` prints the whole picture if anything looks wrong; `… remove` puts the old
shortcut back.

### CP 2.6 — Services that outlive the agent 🟢 ✅ done
Closed the hole CP 2.5 measured (D22): the pseudo-console moved out of the agent into a detached
**service host** process (`services/host.py`, spawned through `services/host_launcher.py`, which
exits immediately so no tree walk from the agent ever reaches the host — D23), so a supervised
service now survives the agent exiting, crashing or being restarted for a code change, which is what
D10 promised and what Phases 3–7 need.

What landed, beyond the stand-in the plan originally described: host takes its spawn parameters as
data (`<name>.spawn.json`) rather than a registry lookup, so the test suite's fake services spawn
through the exact same path as the three real ones; the supervisor tails `<name>.stream` into the
existing `LogRing` (D18's `seq`/`?since=` contract unchanged); resize crosses a Windows named pipe
(stdlib `multiprocessing.connection`) since a file cannot carry it; `<name>.json` now carries
`host_pid`/`host_create_time` plus `exit_code`, the only way the agent learns a host died once its
launcher is gone; `status()["terminal_available"]` is now true for `ADOPTED` as well as
`SUPERVISED`, finally giving **adopted services a real terminal** (D17 no longer applies to them);
and stop/takeover kill the host's tree (which tears its pty and the child down with it), with a
belt-and-braces direct kill of the child pid if it somehow survives that.

`agent/tests/test_supervisor.py` §14 is the new case the plan called for: `fake_agent_process.py`
builds a real `Supervisor` in its own process and spawns a service through the real host path, and
the outer test `taskkill /F`s and separately `taskkill /F /T`s it — host and service survive both,
same pids, and a fresh `Supervisor.adopt()` recovers `terminal_available: true` with real replayed
history. All four suites pass: `test_supervisor.py` 71/71, `test_e2e.py` 32/32, `test_ui_contract.py`
49/49, `test_dependencies.py` 26/26. One Flutter line rides along: `service_terminal.dart`'s
`_detached` getter stopped treating `adopted` as detached, since it no longer is (`flutter analyze`
clean, `flutter test` 11/11).

**Verified live on this machine (Claude):** took all three real services under supervision, killed
`ia-agent.exe` outright — vl-server and wsl-bridge came back `adopted` on the *same pids*, zero
restarts, with their real startup logs (vl-server's model-load banner, from before the kill)
replayed into the terminal. adb showed a pre-existing, unrelated quirk instead: its `nodaemon` mode
forks a detached `fork-server` grandchild that escapes host tracking on its own, twice, regardless
of anything this checkpoint touched — the agent correctly reports it `external` (D11 already
anticipates exactly this shape) rather than losing track of it silently. See D23.

**Test (already run, above) — repeatable from the app:** with all three services supervised, restart
the agent from the app (or kill it) — the tiles should come back reading `adopted`, the services
should never have stopped (same pids), and each terminal should still show its history and keep
receiving new output.

**Phase 2 accepted 2026-07-31** — the user accepted outright, without running the CP 2.6 test
above separately. The five flow switches (turned off during Phase 2 so live flows wouldn't fire
while the pods and helm chart were being worked against) are restored to ON.

---

## Phase 3 — Trigger delays & conditions · solves #2

Goal: change any delay from the UI, see exactly when the next run fires and why it might not.

### CP 3.1 — Typed live config 🟡 ✅ done
`models/meta.py`: generalise `Limit` into `Config` (typed get with defaults for int/float/
bool/str), keep `Limit` as an alias so no existing call site changes. Add every key from
ARCHITECTURE §4.1. Fix the stale `PROFILES/REELS/POSTS` comment in `config.env`.

**What landed** — `Config._DEFAULTS` now carries all nine existing limits plus the eleven trigger
timings, two gates, and two wiring keys from §4.1, all resolving to coded defaults since none are
in `config.env` yet (CP 3.2 starts reading them). `Limit = Config` at module scope, so every
existing call site is untouched. **Q3 answered** — `PROFILES`/`REELS`/`POSTS` genuinely are the
live daily scan caps (`Scan.limit_reached` + `entity_scan_trigger`'s day-pause); the `config.env`
comment claiming otherwise was wrong and is now fixed. See D24. No test suite exists in this repo,
so this was verified by import sanity-check (all five call-site modules import cleanly, alias
identity holds, new keys resolve to their defaults with dotenv's expected warnings for absent
keys) rather than `pytest`.

### CP 3.2 — Config-driven scheduler 🟡 ✅ done
In `controllers/prefect.py`:
- every hardcoded `wait` / `buffer` / `sleep` → `Config.get(...)`;
- `wait_until()` interruptible sleep (TICK granularity, re-reads config, returns wake reason);
- `SCRAPE_BACKPRESSURE_FACTOR` replaces the hardcoded `* 3`;
- **fix** the day-rollover fall-through — re-fetch `Scan`/`Scrape`/`Follow` after
  `wait_day_change()` before evaluating the gate;
- `SCAN_WAIT` cooldown between scan runs (default `0` = today's behaviour, so this is a no-op
  until you set it — see Q2).

**What landed** — `wait_until(self, flow: str, key: str)` (deliberately keyed, not a resolved
`seconds` float — see D25) replaces every hardcoded sleep across all five trigger loops plus
`keep_telegram_alive` and `wait_day_change`. Verified by direct call: `SCAN_WAIT=0` returns
`"elapsed"` immediately (today's no-cooldown behaviour, unchanged), and a short live target
(`TICK=0.05`, `CLASSIFY_POLL_WAIT=0.12`) ticks and re-reads config correctly. The day-rollover fix
is a `continue` right after `wait_day_change()` in `entity_scan_trigger`, `entity_scrape_trigger`,
and `entity_follow_trigger`, so the next loop iteration re-fetches fresh state before evaluating
anything. **Not yet built:** countdown publishing and `run_now`/`skip_wait` command handling —
`wait_until` always returns `"elapsed"` until CP 3.3's `AgentClient` and CP 3.4's heartbeat
endpoint exist for it to check against.

### CP 3.3 — Agent client in the pod 🟡 ✅ done
New `controllers/agent.py`: `AgentClient` with heartbeat (2 s), event emit, notify — every
method swallows failures so the agent being down is invisible to the pipeline. Heartbeat
publishes the per-flow state block from ARCHITECTURE §4.3 and drains commands from the response.

**What landed** — `AgentClient.heartbeat/emit/notify`, each POSTing to the agent and swallowing
every exception (`[]`/`None`/`False` on failure — see D26). Verified against both a genuinely
unreachable port and the real running `ia-agent`, whose `/api/scheduler/heartbeat` and `/api/notify`
don't exist until CP 3.4/6.1 — both 404 cleanly through the same swallow path. `IA_AGENT_URL`
deliberately stays a live `Config` key (CP 3.1) rather than moving to `vars.py`; only
`IA_AGENT_TOKEN` is new there, since it's a secret and `config.env` syncs to the phone. `httpx`
promoted from a transitive to a direct dependency. **Not yet wired into `Prefect.serve()`** — the
2 s heartbeat loop and command draining is CP 3.4's job, once the agent has something to receive it.

### CP 3.4 — Scheduler mirror in the agent 🟢 ✅ done
`POST /api/scheduler/heartbeat`, in-memory state store, command queue, `flows.state` WS channel,
plus staleness detection (no heartbeat for 15 s → scheduler shown as offline).

**What landed** — `ia_agent/scheduler.py`'s `SchedulerMirror` (RLock-guarded per-flow store,
mirroring `ManagedService`'s locking idiom) plus `GET /api/scheduler`,
`POST /api/scheduler/heartbeat`, and `POST /api/scheduler/{flow}/command`. `flows.state`
broadcasts the full snapshot on signature change (online flag, or any flow's switch/phase/
next_trigger_at) — same publish-on-change discipline as `services.status`. A 3s watchdog task
catches the "heartbeats stopped arriving" case that nothing else would notice. See D27.
`agent/tests/test_scheduler.py`, 24/24 (store logic + a live REST/WS round trip against a
throwaway app instance, real services untouched via the same `build_specs` monkeypatch
`test_ui_contract.py` uses). All five existing suites unchanged: 71/71, 32/32, 49/49, 26/26,
20/20. **Deliberately not built here** (this CP is 🟢, agent-only) — nothing on the pipeline side
calls `AgentClient.heartbeat()` yet, so `/api/scheduler` on the real agent reads `online: false`
until a follow-up wires `Prefect.serve()` to send real heartbeats (D27's "How to apply").

**Closed same session:** `Prefect.serve()` now runs `heartbeat_loop()`, a 2s loop posting every
flow's real state block. See D28.

### CP 3.5 — Flows UI 🟢 ✅ done, user-verified
Five flow cards: countdown ring to `next_trigger_at`, the gate reason in plain language, today's
counters against the limit, the switch, **Run now/Skip wait** (respects gates) and **Force run**
(bypasses, with confirmation), last run state + duration + a jump to Prefect's own UI for its logs.

**Prerequisite gap from CP 3.4 (D27) — closed (D28):** `Prefect.serve()` now runs a
`heartbeat_loop()` that posts every flow's real state block every ~2s, so `/api/scheduler` has real
data for this screen to render against. **Command handling** (the actual scope of this CP):
`wait_until` (D25) now wakes on `skip_wait`/`run_now`/`reload_config`/a pending `force_run`;
`force_run` bypasses the rate gate (day-limit/backpressure) and the `ENTITY_*` switch per flow, but
never a no-work gate — see DECISIONS D29 for the full table and every correction it took to get
there. `pause`/`resume` stay accepted by the agent's REST layer but unwired — no button asks for
them.

**What landed beyond the original scope, all from live testing (D29 has the full history):** the
Settings > Limits tab gained a "Timings" group exposing all eleven trigger-timing keys (nothing had
before — `FOLLOW_WAIT` etc. were only editable by hand-editing `config.env`); `SCRAPE_BACKPRESSURE_
FACTOR` renamed to `SCRAPE_RESERVE_FACTOR`; the "triggering" phase renamed to "running" (it was live
for a flow run's entire duration, not a momentary state); a countdown-ring jitter bug (`wait_until`
was recomputing `next_trigger_at` with near-but-not-exact-same-instant precision every tick,
resetting the ring to full every ~5s) and a Force Run responsiveness bug (queued but never checked
while a flow was mid-wait — invisible on Scrape's short waits, completely broken on Follow's long
one) fixed together in `wait_until`; Force Run made unconditionally enabled (manual trigger = ignore
everything, always) instead of only enabling when something was blocking; optimistic "command
sent…" UI feedback so a worker-pickup delay can't invite a double-click; and a maximized-mode title
bar rendering glitch (Windows redrawing native caption chrome under the custom buttons) worked
around by faking maximize via `setBounds` to the real Win32 work area instead of calling
`windowManager.maximize()`.

**Verified without any live Telegram/DB/device/Instagram call** at every step (flow switches stayed
live throughout) via an isolated harness exercising `wait_until`/`_consume`/`_pending`/force-bypass
logic directly against a `Prefect.__new__` instance. The actual pipeline behavior (heartbeats, gate
details, Force Run's live effects) was verified against the real running pod, temporarily pointed at
`feat/control-center` via a new `GIT_BRANCH` env var and rebuilt image (D29) — reverts to normal the
moment this branch merges to `main`.

**Test (run by you, live, several rounds):** countdown re-targets within one TICK on a `FOLLOW_WAIT`
edit; Skip wait fires immediately; switch off reads "skipped: switch OFF"; the scrape card explains
`scraped+follow_queued = 180 ≥ FOLLOW×3 = 180`; Force Run actually runs regardless of switch/limits
on every flow; rings animate smoothly without resetting; Force Run gives instant feedback instead of
a multi-second gap.

---

## Phase 4 — Live logs & flow-aware imagery · solves #7

Goal: the showpiece screen.

### CP 4.1 — Log aggregation 🟢 ✅ done
Prefect log tailer (incremental by timestamp cursor, ~1 s per active run), active-run discovery
from the heartbeat with a `flow_runs/filter` fallback, and the scheduler pod's container log
merged in via the k8s API. Unified log model: ts, source, level, task, message.

**What landed** — `ia_agent/flowruns.py`'s `FlowRunTailer`: heartbeat-first active-run discovery
(a running flow's `last_run.id` *is* its in-progress run, no pipeline change needed) falling back to
Prefect's `flow_runs/filter` when the mirror is offline; a per-run `Ring` (`seq`-replayable, same
discipline as D18's service terminal ring) polled via `logs/filter`, deduped at the `after_`
boundary by log id, with `task_run_id` → name resolved once and cached; the scheduler pod's
container log merged into every currently-active run's ring in append order rather than a
timestamp-sorted interleave, which would have needed a second seq space (D30). New REST —
`GET /api/flow-runs?limit=` · `GET /api/flow-runs/{id}` · `GET /api/flow-runs/{id}/logs?since=`
(§3.1) — and WS channel `flowrun.logs` (§3.2), wired into `app.py`'s lifespan alongside the
scheduler mirror and supervisor.

Two things only live verification against the real cluster caught (D30): the installed
`kubernetes` client's generated bindings never wired up `since_time` for pod log reads at all, so
the cursor is `since_seconds` (relative) with the caller re-filtering the overlap by parsed
timestamp instead; and the same client hands back the literal string `b'...'` — not real bytes,
not decoded text — for that one endpoint, unwrapped via `ast.literal_eval`.

**Verified:** `agent/tests/test_flowruns.py`, 36/36 (Ring replay, both discovery paths, per-run
polling, scheduler-pod merge scoped to only-active runs, eviction, and a live app exercising every
REST endpoint plus a real WS delivery — all against monkeypatched `prefect`/`kube` functions, same
convention as `test_scheduler.py`). `agent/tests/check_flowruns.py` (new, read-only) then ran the
real functions against the live Prefect server and k3s cluster: resolved all five deployment ids,
listed real recent runs, fetched real logs and a real task name, and tailed the real scheduler pod
end to end — nothing it touches can start, stop, or mutate anything. All five prior suites
unchanged (71/71, 32/32, 26/26, 24/24, 20/20); `test_ui_contract.py`'s pre-existing
`terminal_available` `KeyError` reproduces identically on a clean `main`, unrelated to this
checkpoint.

**No UI to test yet** — CP 4.4 is what puts these endpoints on screen. This checkpoint is agent-only
(🟢) and was verified the same way CP 3.4 was: agent-side test suite plus live read-only calls
against the real Prefect/k3s, no GUI involved.

### CP 4.2 — Event pipeline 🟢 ✅ done
`POST /api/events`; **cache image bytes on receipt** (content-addressed under
`%LOCALAPPDATA%\ia-agent\cache`), generate thumbnails, serve `GET /api/images/{key}`; replay ring
buffer; `flow.events` WS channel. Resolve IA_DIR-relative paths against the Windows `IA_DIR`.

**What landed** — `ia_agent/images.py`: `cache(rel_path)` reads `IA_DIR/rel_path` and stores the
bytes under their sha256 (so two events pointing at identical content share one cache entry),
returning `None` rather than raising when the file is already gone — the race CP 4.3's `emit()`
calls will lose sometimes, by design tolerated here rather than treated as an error. `thumbnail(key,
width)` resizes lazily on first request and caches the result alongside the original — most keys are
never viewed at every width the UI might ask for. `ia_agent/events/store.py`'s `EventStore` accepts
events as a loose dict (same choice `SchedulerMirror.heartbeat` made — a validation error here would
be an event the pipeline can never learn was dropped, since `emit()` doesn't read the response),
assigns `seq`/`id`/`ts` when the caller didn't supply them, caches the image inline, and publishes on
`flow.events`. New REST — `POST/GET /api/events[?since=]`, `GET /api/images/{key}`,
`GET /api/images/{key}/thumb?w=` (clamped to 16–2000px) — wired into `app.py` alongside the other
stores.

**Verified:** `agent/tests/test_events.py`, 35/35 — content-addressing (identical bytes → identical
key, different bytes → different key), the missing-file race, thumbnail proportions and width
clamping, the replay ring, and a live app exercising every REST endpoint plus a real `flow.events` WS
delivery, all against a scratch `IA_DIR`/cache directory (never the real ones). All other suites
unchanged (36/36, 24/24, 26/26, 20/20; 71/71 and 32/32 confirmed earlier this session, untouched by
this checkpoint).

**No UI yet** — CP 4.4 puts this on screen; CP 4.3 (cross-repo, `Insta-Automate`) is what starts
calling `POST /api/events` for real.

### CP 4.3 — Flow instrumentation 🟡 ✅ done
Add `emit()` next to the existing log lines at every point in the ARCHITECTURE §5.1 table —
`tasks/ia.py` (`profile_entity_scan`, `post_entity_scan`, `profile_scrape`, `profile_follow`,
`add_new_entity`), `tasks/ollama.py` (`remove_public`, `gender_classify`), and the five flow
bodies for started/completed. **Always relativise paths to `IA_DIR`** — `profile_scrape` and
`profile_follow` currently log absolute paths.

**What landed** — every table row now has a real emit call: `entity.added` (`add_new_entity`),
`scan.started`/`scan.item`/`scan.completed` (`profile_entity_scan` and `post_entity_scan`, the
"which list and why" detail landing in `extra` since that decision only exists inside the task, not
the `entity_scan` flow body), `scrape.started`/`scrape.skipped` (all four real skip reasons: `PUBLIC`,
`NO_POSTS`, `f=<n> < FMIN=<n>`, `f=<n> > FMAX=<n>`) /`scrape.done` (with real parsed
posts/followers/following counters) in `profile_scrape`, `follow.attempt`/`follow.result` (every
terminal branch — `FOLLOWED`/`REQUESTED`/`FOLLOWING`/`FOLLOWED_BY`/`WANTS_TO_FOLLOW`/`FAILED`, the
last with a `reason`) in `profile_follow`, and `classify.access`/`classify.gender` in
`tasks/ollama.py`. The absolute-path bug the plan called out is fixed alongside its emit call:
`profile_scrape`'s "Scrape exported to …" log line and both tasks' `image` fields are now
`IA_DIR`-relative.

**Beyond the table**, all five flow bodies gained a `flow.started`/`flow.completed` pair — a
distinct kind namespace (not `scan.*`/`scrape.*`/etc., which stay task-level) so CP 4.4's run
summary has an unambiguous whole-run boundary with real counters (`entity_scrape`/`entity_follow`:
processed/scraped or followed; `entity_classify`: private/public/female/male/total + duration;
`entity_scan`: a plain status flag; `entity_ingest`: messages processed), landing even on
`entity_scan`'s early "already scanned" return so a started run is never left without a matching
completed.

**`tasks/ollama.py`'s `remove_public`/`gender_classify` are plain sync functions**, not
`async def` like every other instrumented call site — `AgentClient.emit` can't be awaited there.
The first attempt used `asyncio.get_running_loop().create_task(...)` to fire-and-forget from sync
code, and it was wrong: both functions `unlink()`/`move()` the same image on the very next line,
inside a tight loop that never yields back to the event loop until the whole function returns — a
scheduled task would only run after every file in the batch was already gone, exactly the race the
image cache exists to avoid. `controllers.agent.emit_sync` instead makes a genuinely blocking
`httpx.post` call (new module-level function, not a method) — cheap next to the AI inference call
each iteration already makes, and it guarantees the agent has read the bytes before the source file
moves or disappears. See DECISIONS.md D32.

**Also found and fixed, discovered only by live verification against the real Prefect server**: CP
4.1's `run_logs()` defaulted to `limit=500`, but Prefect's `/logs/filter` (and `/flow_runs/filter`)
422 above `limit=200` — invisible to CP 4.1's own test suite (fakes don't enforce Prefect's real
constraints) and to the live `check_flowruns.py` run at the time (which happened to pass an explicit
small `limit=`). Fixed in `agent/src/ia_agent/integrations/prefect.py` with a shared
`MAX_FILTER_LIMIT = 200` clamp in both functions — this is an agent-side fix riding along in this
session, not part of CP 4.3's own scope.

**Verified:** import sanity-check on every changed pipeline module (no test suite exists in this
repo, same precedent as CP 3.1/3.2); a live round trip — `AgentClient.emit` (async) and `emit_sync`
(blocking sync) both pointed at a throwaway agent instance via monkeypatched `Config.get`/
`IA_AGENT_TOKEN` — confirmed both actually reach `POST /api/events` and are readable back from
`GET /api/events`. The limit-clamp fix was verified directly against the real Prefect server
(`run_logs`/`flow_runs_filter` at their old failing size, then passing), and `agent/tests/
test_flowruns.py` (36/36) still passes unchanged. Nothing deployed to the live pod yet — that's a
rebuild the pipeline pod doesn't need until this branch is tested end-to-end, per D29's
`GIT_BRANCH`-pointed rebuild technique.

### CP 4.4 — Live screen 🟢 ✅ done, user-verified
Three panes: log console (auto-follows the active run, level filter, task grouping, sticky
errors) · flow-specific visualization surface (per-kind layouts for the three aspect ratios) ·
run summary with counters and the device pane.

Per-flow surfaces: scan → live-growing strip filmstrip with `added/scanned`; classify → verdict
card stream with running img/s; scrape → before→after morph plus reason chips carrying real
numbers; follow → profile report with outcome; ingest → hero page cards.

**What landed** — `app/lib/features/live/`: a flow-selector row (`ChoiceChip`s, auto-selects
whichever flow is `running` the first time real scheduler data arrives, a manual tap overrides it
after that) above three panes — `LogConsole` (level filter chips, task-change dividers, a sticky
expandable error strip, and auto-follow that respects manual scroll-up), the per-flow
`_VisualizationSurface` switch, and `RunSummary` (phase/today/last-run from the existing scheduler
snapshot, this-run counters summed from event payloads, and a device-pane placeholder explaining
CP 4.5 isn't built yet — D17's "say why, don't show blank" rule applied again). `LiveController`
replays `GET /api/flow-runs/{id}/logs` and `GET /api/events` once per selected flow, then stays
current via the `flowrun.logs`/`flow.events` WS channels, resetting when the flow's `last_run.id`
changes (a new run started) rather than on every heartbeat tick. New `core/flowrun_models.dart`,
`core/flow_event_models.dart`, and `core/agent_image.dart` (fetches `/api/images/{key}[/thumb?w=]`
through `dio` for the auth header a bare `Image.network` can't attach, cached per Riverpod's own
family semantics). `flowTitle`/`phaseLabel` moved from `flow_card.dart` (private) to
`scheduler_models.dart` (shared) rather than duplicated for the Live screen's own use of the same
mapping.

**Found by the new `live_layout_test.dart`, not `flutter analyze`** (same class of bug as D19/CP
2.4 and CP 3.5's countdown/button fixes — overflow is paint-time): `AgentImage`'s placeholder
(icon + label, shown whenever `imageKey` is null) overflowed at the classify surface's row-crop
aspect ratio (1080:198) sized to a card thumbnail — ~18px tall, not enough for icon + spacing +
text. Wrapped in `FittedBox(fit: BoxFit.scaleDown)` so it shrinks to fit instead. 7 new test cases
targeting exactly the "unbounded-length real string in a fixed-width pane" shape `flows_layout_test`
established (a 60-character username, a 40-character digit run with no spaces, six counters at
once), across the log console, run summary and all five surfaces.

**Verified:** `flutter analyze` clean, `flutter test` 23/23 (16 prior + 7 new). Tested live against a
real scrape run in progress. The agent serving the app had to be restarted mid-test — it was still
running pre-session code with none of CP 4.1/4.2's routes, hence an initial round of 404s that
looked like app bugs but weren't (the three-repo split means a code change here needs the actual
long-lived `ia-agent.exe` process restarted to take effect, not just a rebuild). The log console
worked immediately once that was fixed, exactly as expected — it reads CP 4.1's tailer, which is
Prefect's own execution log, no pipeline-side dependency. The visualization surfaces stayed empty as
predicted (CP 4.3's `emit()` calls aren't deployed to the live pod yet).

**Corrected after your live feedback, same session:** the log line rendering was hard to read — you
compared it to Prefect's own log view as the "too far the other way" reference (not asking for that
much chrome, just real readability). Rebuilt `_LogLine` as timestamp + a colored level pill +
message in the theme's normal body font at 1.4 line height, monospace dropped entirely since these
are prose lines, not tabular data (D33 addendum has the full before/after). Also surfaced by the
same live test: a `IA_AGENT_URL not found in config.env` warning flooding the scheduler-pod log
lines — not a new occurrence (it's fired every heartbeat since CP 3.4), just newly visible now that
D30's pod-log merge exists. Fixed at the source: wrote the coded default into the real `config.env`,
since `IA_AGENT_URL` is deliberately outside the app's config schema (D26).

**Visual polish pass, 2026-08-01 (deferred at the time, closed out during the CP 5.1 session):**
once CP 5.1's live-pipeline fixes (D36–D39) gave this screen real per-item events to look wrong
against for the first time, several rounds of your live testing found and fixed real issues — the
scrape card only staying large while genuinely in progress, image aspect-ratio bugs (two of them,
not the same one twice), a "root: entity" label, the outer layout (two columns, log console
`Expanded` and fixed-width sized to its own content), `RunSummary`'s counters computed live per-flow
instead of waiting for the run to finish, device control compacted into the header and showing the
device model instead of its serial, and the scheduler-log left border removed for reading as
inconsistent rather than useful. Full history in D40–D46 (`DECISIONS.md`) and the matching addenda
in `CLAUDE.md`. `flutter analyze` clean, `flutter test` 26/26 throughout.

### CP 4.5 — Device view 🟢 ✅ done, user-verified
Primary: control the native scrcpy window through wsl-bridge, positioned with
`my_modules.win32.snap_window`. Secondary (opt-in, low fps): `adb exec-out screencap` frames
streamed over `device.mirror` so the phone can watch too. See Q6.

**Scoped down after asking, before writing any code:** two forks were real design decisions, not
implementation details, so they were checked rather than guessed. First — the plan's "positioned
with `my_modules.win32.snap_window`" assumes a fixed window title to search for, but scrcpy's title
varies by phone model, and `my_modules`/wsl-bridge are both marked "no changes expected"
(ARCHITECTURE §8), so normalizing the title there wasn't available. **Chosen: find the window by
PID instead** — wsl-bridge's `POST /scrcpy/start` already returns the spawned process's pid, exact
and requiring no cooperation from either repo. Second — the secondary opt-in phone-glance stream has
no consumer yet (Phase 6, mobile pairing, isn't built), so building `device.mirror` broadcast
plumbing now would be untested code with nothing to exercise it. **Chosen: desktop-only this
checkpoint** — the adb-screencap streaming path is deferred to whenever Phase 6 actually needs it.

**What landed** — `ia_agent/integrations/wsl_bridge.py` (thin client for wsl-bridge's existing
`/scrcpy/*` control plane, not modified), `ia_agent/window.py` (`find_window_by_pid`/
`snap_to_known_position` via raw `ctypes.windll.user32` — same approach `my_modules.win32.
snap_window` uses, just keyed by PID via `EnumWindows`+`GetWindowThreadProcessId` rather than title),
and `ia_agent/api/device.py` — `GET /api/device` (serial, bridge reachability, mirroring) and
`POST /api/device/scrcpy/{start|stop}`. `start` refuses to cycle an already-running mirror (matching
`test_wsl_bridge()`'s existing "don't be rude" precedent — cycling would throw a new window on
screen for no reason) and retries the snap for up to 5s since the window doesn't exist the instant
the process does; a snap that never succeeds still reports the start as successful, since the
mirror itself came up fine either way. `snap_to_known_position` only re-asserts scrcpy's own
requested launch position (`--window-x=1 --window-y=45`, already in `my_modules.scrcpy.Scrcpy.
start()`) and reads the window's current size first, so it can never resize or distort the video —
purely defensive against a compositor ignoring the initial launch hint.

Flutter: `core/device_models.dart` + `features/live/device_pane.dart` (`DeviceController` +
`DevicePane`) replaces the CP 4.4 placeholder in `RunSummary`. No WS channel exists for device
state, so a lightweight 5s `autoDispose` poll keeps it current while the Live screen is open. The
pane explains itself when there's nothing to show (bridge unreachable, no `ANDROID_SERIAL`) rather
than presenting dead controls, matching D17's rule. The scrcpy window itself is never rendered
inside the app — it's a real, separate OS window; the pane only starts, stops and reports on it,
with a line saying as much once mirroring is on.

**Verified:** `agent/tests/test_device.py`, 16/16 (every REST branch — already-mirroring skip, the
retry-loop around the snap succeeding after a few tries, snap never succeeding without failing the
start, both `wsl-bridge` failure paths as 502s — against a monkeypatched `wsl_bridge`/`window`, never
the real bridge or a real window). The window-finding mechanism itself was verified against a real
process on this machine: a first attempt using a spawned Notepad as the test subject failed
(`find_window_by_pid` found nothing) — turned out to be Windows 11's own Notepad being a packaged
app where the launched pid isn't the window-owning pid (D11's "the pid you launched is rarely the
pid that matters" pattern, again, just not the one this project already knew about). Switched to
the machine's actual already-running `scrcpy.exe` (found via `psutil`, read-only — nothing was
started, stopped, or moved) and confirmed `find_window_by_pid` locates its real window correctly, in
`agent/tests/check_device.py` (new, read-only, respects the same "don't disturb an active mirror"
rule as `test_wsl_bridge()`). `flutter analyze` clean, `flutter test` 23/23 (unchanged — no new
layout-risk widgets introduced beyond what the existing suite already exercises via `RunSummary`).

**Test (yours) — passed:** the Device pane showed an already-mirroring device immediately, without
touching the existing window, and Stop/Start mirror both worked from the pane. Accepted as done for
now — you noted you're not fully certain about the overall visual polish yet, which stays open for a
later pass rather than blocking this checkpoint.

---

## Phase 5 — Library & curation parity

Goal: review the backlog on a 16-inch screen instead of a phone.

### CP 5.1 — Library API 🟢 ✅ done
Folders, entities, and images with cached counts (invalidated by the `IA_DIR` watcher, seeded
from a background scan — 7.5k files means naive `rglob` per request is not acceptable).
Thumbnail service. `library.changes` WS channel.

**What landed** — `ia_agent/library/folders.py`'s static `FOLDERS` registry (the seven ARCHITECTURE
§1.1 stage directories — `entities` flat, the other six one-subdirectory-per-root) plus
`resolve(path)` mapping an absolute path back to `(folder, root)`; `library/counts.py`'s
`LibraryCounts` (`seed()` — one `os.scandir` per folder plus one per root, ~120 calls today, not a
per-file walk — and `touch(folder, root)`, which recomputes exactly the one pair a change touched
rather than tracking deltas, dropping a root that hits 0 files instead of showing it empty);
`library/watcher.py`'s `watch_library` (`watchfiles.awatch` scoped to the seven known directories,
recursive — the deliberate opposite of `config/watcher.py`'s non-recursive top-level watch, and for
the same reason in reverse: this one needs the churn config's watcher exists to dodge, while never
watching `.thumbs`/`.Trash-0`); and `api/library.py`'s REST surface (`GET /api/library/folders` ·
`GET /api/library/entities?folder=` · `GET /api/library/images?folder=&entity=&offset=&limit=` ·
`GET /api/library/image?path=` · `GET /api/library/image/thumb?path=&w=`), the last two reusing CP
4.2's content-addressed `images.cache`/`thumbnail` unchanged, keyed by path at request time rather
than eagerly hashing every listed file. See D35 for the three design choices (recompute-on-touch,
scoped recursive watching, lazy path-keyed thumbnailing) and their reasoning.

**Verified:** `agent/tests/test_library.py` (32/32) plus new read-only `agent/tests/
check_library.py` against the real `IA_DIR` — `seed()` took 15 ms over the real 7,655 files across
~120 directories. All eight prior suites unchanged. Also verified against the real running agent
(restarted to pick up the new code, same step CP 4.4 needed; the three supervised services stayed
`adopted` with uptime intact across the restart) — every new endpoint hit against the real `IA_DIR`,
plus a live WS connection confirming the channel is reachable.

**No UI yet** — CP 5.3 puts this on screen; CP 5.2 (mutations) is next.

### CP 5.2 — Mutations 🟢 ✅ done
`apply` (move selected to the folder's configured target, delete the rest), `delete`, and queue
add/remove/reorder. Use `send2trash` so semantics match the Python side and mistakes are
recoverable. Every mutation is confirmed and reported.

**What landed** — new `ia_agent/library/ops.py` (`apply`/`delete`) and `ia_agent/library/settings.py`
(per-folder move-target mapping, persisted machine-local at `%LOCALAPPDATA%\ia-agent\library.json`,
seeded with the two real pipeline promotions — `gender_valid → scrape_queued`,
`scraped → follow_queued` — identity for every other folder). New REST: `GET/PATCH
/api/library/move-targets[/{folder}]`, `POST /api/library/apply`, `POST /api/library/delete`, and
on `api/queue.py`: `POST /api/queue/{add|remove|reorder}`. See D47 for the three real design
decisions (send2trash/shutil.move split mirrors the pipeline's own `utils.py`, not the mobile app's
hard-delete; move targets default to the known pipeline shape rather than the mobile app's blank
slate; `config.env`'s write lock moved into `env_file.py` itself so `/api/config` and the new
`/api/queue` mutations can't race each other).

**Verified:** `agent/tests/test_library.py` (65/65, up from CP 5.1's 32) and new
`agent/tests/test_queue.py` (14/14) — unit-level against a scratch tree plus the same coverage again
over live REST, covering the identity-mapped cull, a real cross-folder promotion preserving
`<root>/<name>`, the queue's `check=True` pending-jpeg refusal and forced override, and confirming
`config.env`'s comments/unrelated keys survive every mutation. All eight prior suites unchanged.
Also verified read-only against the real running agent (restarted to pick up the new code; all three
supervised services stayed up across it) — `GET /api/library/move-targets` and `GET /api/queue` hit
against the real `IA_DIR`. No `apply`/`delete`/`add`/`remove` call was made against the real
pipeline data this session — that stays untested live until CP 5.3 puts a confirmable UI in front of
it, matching CP 4.2/4.3's precedent of never mutating the real `IA_DIR` from a verification pass.

**No UI yet** — CP 5.3 puts this on screen.

### CP 5.3 — Library UI 🟢 ✅ done, user-verified
Virtualized grid, keyboard-driven multi-select (arrows, space, shift-range, ctrl-A), zoom
levels, per-folder move targets mirroring the mobile app's mapping, double-tap to copy id,
long-press/context-menu to open the Instagram URL (reuse the `reel-` / `post-` / account
resolution rules).

**What landed** — the Library nav destination (previously a placeholder): `app/lib/features/library/`
is a `FolderRail` (the seven folders with live counts) + `EntityList` (search-filterable roots inside
whichever non-flat folder is selected) + a `LibraryGrid`/`LibraryToolbar` pane. The grid uses
`SliverGridDelegateWithFixedCrossAxisCount` with the count computed from the zoom level rather than
`SliverGridDelegateWithMaxCrossAxisExtent` — deliberately, since keyboard navigation needs an exact
column count to turn Up/Down into "move by one row," which the max-extent delegate doesn't expose.
Pages of up to 200 load as the user scrolls (folders here run to thousands of files); `ctrl+A`
first pages in whatever's left so "select all" really means all, not just what's been scrolled into
view. New `core/instagram_url.dart` ports `Insta.url()`'s `reel-`/`post-`/account resolution rule
(checked against both the pipeline's `controllers/instagram.py` and the mobile app's own
`instagram_url.dart` before writing it, so all three agree) and `core/library_image.dart` is
`agent_image.dart`'s sibling for path-addressed thumbnails (`GET /api/library/image/thumb?path=`),
reusing `BoxFit.contain` per D41's letterboxing-over-cropping lesson. Apply/Delete both confirm with
a dialog naming exactly what happens (moved/kept count, trashed count), matching
`flow_switch_confirm.dart`'s established rule; a per-folder move-target picker sits next to Apply.

**Corrected from your live testing, same session — see D48.** The first version needed Ctrl+click to
add to a selection and let a plain arrow key collapse the selection to just the newly-focused item,
both wrong: a plain click/Space should always toggle (building a batch by clicking, or arrow-then-
spacing through several images), and a plain arrow should only move focus, never touch selection.
Fixed by making focus and selection genuinely independent operations (`moveFocus()` vs `toggle()`)
rather than one derived from the other. Confirmed working on your retest.

**Verified:** `flutter analyze` clean, `flutter test` 32/32 (26 prior + 6 new in
`library_layout_test.dart`, which caught a real `RenderFlex` overflow in the toolbar at the app's
1024px floor before you ever saw it — fixed by splitting the single action row into a breadcrumb row
plus a `Wrap` for the button cluster, which degrades to more rows instead of overflowing at any
width). Built and started for you to test per D19/rule 5 — the GUI itself is yours, not mine, to
drive.

**Test (yours) — the selection mechanics, passed:** opened Library, selected an entity, and confirmed
mouse click-to-toggle and keyboard arrow-then-space both build up a multi-image selection the way you
expected, after the D48 fix above. Apply/Delete against real data, and a real-window resize check,
weren't separately confirmed back to me in this session — worth a look next time you're in the app.

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

**Q1 — Shared queue. ✅ ANSWERED 2026-07-31: keep it shared, no split.**
`ENTITY_QUEUE` is a list of *entity names*, and each `Queue` maps that one ordering onto its own
directory (`SCRAPE_QUEUE_DIR` / `FOLLOW_QUEUE_DIR`). The distinction between scrape and follow
comes from the folder, not the key, so a single priority list is correct by design — an entity you
want prioritised is wanted first at both stages. See DECISIONS D8.

**Q2 — Scan cooldown.** `entity_scan` has no inter-run delay today: the trigger blocks until the
flow finishes, then sleeps 10 s. Scan is the most rate-limit-sensitive flow. Do you want a real
`SCAN_WAIT` cooldown, and if so what default? (Planned as `0` = no behaviour change.)

**Q3 — Scan limits. ✅ ANSWERED 2026-07-31: yes, they are the live daily scan caps.**
`Scan.limit_reached` compares today's counts against `Limit.get("PROFILES"/"REELS"/"POSTS")`, and
`entity_scan_trigger` pauses until the next day when any is reached. The `config.env` comment
claiming otherwise was wrong and is fixed. See CP 3.1, D24.

**Q4 — Startup ownership. ✅ ANSWERED and DONE 2026-07-31: the agent replaces the shortcut.**
`dev-startup.exe.lnk` is deleted (backed up at `backups/2026-07-31-dev-startup/`) and the `ia-agent`
logon task is installed; the agent starts the three services from their `autostart` switches, now on.
`ollama serve` is dropped from the set entirely (D13) and the services' own restart loops stay off in
favour of the agent's (D14). The task runs a GUI-subsystem interpreter so nothing shows a window
(D20) and the launcher, not Task Scheduler, heals the agent (D21). See CP 2.5.

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
