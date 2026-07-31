# Decision log

Newest first. Each entry records what was chosen, what was rejected, and why — so a future
session can tell a settled question from an open one.

---

## 2026-07-31 — Phase 2 implementation session (CP 2.1, revised after review)

### D15 · Services are spawned into a ConPTY, and their output is kept verbatim
**Chosen:** `PtyProcess.spawn` (pywinpty) instead of `subprocess.Popen`, with the raw stream stored
as chunks — ANSI escapes, cursor moves and carriage returns intact — and rendered in the app with a
real terminal emulator (`xterm.dart`). The rotating file on disk is the only flattened copy
(`render_plain` strips escapes and keeps the last carriage-return frame).
**Rejected:** pipes with line-oriented storage, which is what CP 2.1 originally shipped.
**Why:** the requirement is a terminal, not a log list, and these panes replace `wt.exe` tabs — so
they have to show what those tabs showed. Measured on this machine: under a pipe the child sees
`isatty() == False` and suppresses colour; under ConPTY it reports `isatty: True` and emits
`\x1b[32m…` and `\rprogress 3/3` exactly as the terminal did. Line-oriented storage
(`line.rstrip("\r\n")`) destroys precisely the bytes a terminal needs — a progress bar is one line
rewritten a thousand times, and splitting on newlines turns it into nothing.
**Cost:** a pseudo-console has one stream, so stdout and stderr merge and can no longer be tagged
separately. Terminal size must be plumbed from the UI to the process (`POST /services/{name}/resize`),
because otherwise anything drawing to the full width wraps at the wrong column. Scrollback is
bounded by bytes (512 KB), not lines, since a line count no longer bounds memory.

### D14 · The agent owns restart; the services' own restart loops are switched off
**Chosen:** one supervisor, at the agent. `start_vl_server.py` is launched with its existing
`--no-autorestart` flag, and adb runs as `-a nodaemon server start` rather than `-a start-server`.
**Rejected:** leaving each service to heal itself.
**Why:** the restart logic was in the wrong place and covered one service of four. Measured before
changing anything: only `start_vl_server.py` retried; wsl-bridge had none; and `adb -a start-server`
forks so the shortcut's tab exits immediately and *nothing* supervises adb at all. Nested
supervisors also fight — the launcher would resurrect llama-server underneath a stop or takeover
(D11) — and a restart count printed to an unread terminal tab is information destroyed at the
moment it is produced, which is exactly the diagnostic needed for "vl-server sometimes crashes".
**Cost:** the flag must stay in the spec; if someone launches `start_vl_server.py` by hand it will
still self-restart and be detected as `external` rather than supervised. No change was needed in the
`Insta-Automate` repo — the flag already existed.

### D13 · `ollama serve` is dropped, not supervised
**Chosen:** the agent supervises three services; `ollama serve` leaves the startup set entirely.
**Rejected:** carrying it over as a fourth supervised service.
**Why:** nothing in the pipeline talks to 11434 — `vars.py` points at `VL_SERVER_URL` on 11500, and
`OLLAMA_URL` is defined but never read. `start_vl_server.py` needs Ollama *installed* (it resolves
the model blob out of `~/.ollama/models` and runs Ollama's bundled `llama-server.exe`), not serving.
`Ollama.lnk` is independently in the Startup folder, so the tab was redundant twice over.
**Cost:** if something outside Insta-Automate ever wants Ollama's own API, it is no longer started
by this path — the Startup shortcut still covers it.

### D12 · Service switches live in `services.json`, not `config.env`
**Chosen:** per-service `self_heal` and `autostart` persist to
`%LOCALAPPDATA%\ia-agent\services.json`, applied over the spec defaults at construction.
**Rejected:** adding them to `config.env` alongside the flow switches.
**Why:** `config.env` is IA_DIR-relative, Syncthing-replicated to the phone and read live by the
flows inside the pods. Which Windows processes *this machine* supervises is meaningless to a pod and
actively wrong to sync to a phone. The two files answer different questions: `config.env` is what
the pipeline does, `services.json` is how this host runs it.
**Cost:** a second settings file, and the Services UI cannot reuse the config screen's plumbing.

### Self-heal semantics (implements the requirement, no separate decision)
`RestartPolicy` (always / on-failure / never) collapsed into one `self_heal` boolean, because that
is what was actually asked for. On: restart on exit *whatever the code*, since none of these
services is meant to return, and also restart a process that stays alive while its probe fails for
`unhealthy_grace` (60 s) — wedging is the failure a crash-only policy never notices. Off: leave it
`failed` with its exit code and terminal intact. Turning the switch back on rescues an
already-failed service rather than waiting for the next crash to prove the switch works.

---

## 2026-07-31 — Phase 2 implementation session (CP 2.1)

### D11 · Takeover targets the *service root*, not the process holding the port
**Chosen:** when a port is held by a process the agent did not start, `_service_root()` walks up
the parent chain from the socket owner and stops at the first session host (`WindowsTerminal.exe`,
`explorer.exe`, `powershell.exe`, …), at the agent's own lineage, or after six hops. Takeover kills
that root's whole tree. The status reports both: `external` is what would be killed, `port_owner`
is what holds the socket.
**Rejected:** killing the port owner alone.
**Why:** `Insta-Automate/scripts/start_vl_server.py` runs its own restart loop around
`llama-server.exe` (5 s backoff, doubling). Killing only llama-server would have the launcher bring
it straight back and fight the agent's takeover. Verified live: the resolution walks
`llama-server.exe (23276) → python start_vl_server.py (23112)` and stops at `WindowsTerminal.exe`
(20840, the `wt.exe` shortcut CP 2.5 retires). `psutil.parent()` compares creation times, so a
recycled PPID cannot redirect the walk into an unrelated process.
**Cost:** a denylist of host process names that needs a new entry if the services are ever launched
from a different shell. The agent's own lineage check is what stops the walk from killing the agent.

### D10 · Agent shutdown leaves supervised processes running
**Chosen:** `Supervisor.shutdown()` cancels the tick loop and returns; it never stops the services.
PID files (with `create_time` as a PID-reuse guard) persist, and the next agent run adopts them,
flagging `stdout_available: false` because the pipes belonged to the previous process.
**Rejected:** stopping supervised services on agent exit (systemd-style ownership).
**Why:** D1's stated cost was that the agent "needs adoption logic so it can restart without
killing a running scrape". Tying service lifetime to agent lifetime would make every agent restart
a pipeline outage — the opposite of what this project is for. Stopping a service stays an explicit
operator action.
**Cost:** a service can outlive the agent that started it, so a stale PID file is possible; the
`create_time` guard makes a stale file discardable rather than dangerous.

### D9 · Supervisor state is guarded by a per-service re-entrant lock
**Chosen:** every operator action (`start`/`stop`/`restart`/`takeover`) holds an `RLock`, and
`tick()` skips a round entirely if it cannot take that lock without blocking. `_spawn()` claims
`origin = SUPERVISED` *before* the blocking `Popen`, not after.
**Rejected:** relying on the GIL and short critical sections.
**Why:** found by the CP 2.1 end-to-end test, not by reading. The API offloads actions with
`asyncio.to_thread` so a slow kill cannot stall the probe loop — which means a tick on the event
loop ran while `start()` was still inside `Popen` on a worker thread. It saw `origin = NONE` with a
freshly-bound port, concluded the process the agent was itself starting belonged to somebody else,
and marked the service `external`. The test caught it as `stdout_available: false` after a
successful start.
**Cost:** the lock is held across the probe `await`, so an action can wait up to one probe timeout
(2 s) before it begins. Bounded, and on a worker thread, so nothing user-facing blocks.

---

## 2026-07-31 — Phase 1 implementation session (CP 1.4)

### D8 · `ENTITY_QUEUE` stays one shared list (answers Q1)
**Chosen:** keep the single `ENTITY_QUEUE` key driving both the scrape and follow priority. The
UI presents it as one priority list, not two.
**Rejected:** splitting into `SCRAPE_QUEUE` / `FOLLOW_QUEUE`.
**Why:** the key holds *entity names*, and `Queue.load_queue()` maps that ordering onto whichever
directory the instance was constructed with — `pref_queue = [self.directory / entry ...]`. The
scrape/follow distinction already comes from the folder, so the shared key is not an oversight:
an entity worth prioritising is worth prioritising at both stages. Splitting would add a second
list to keep in sync for no behavioural gain.
**Cost:** none to the flows (no change). The UI must explain the shared semantics, and must show
per-entity counts in *both* `scrape_queued` and `follow_queued` so the one list reads honestly.
**Noted while reading the code, not acted on:** `pref_queue` maps every listed name into the
directory without an existence check, so a queued entity with no folder at that stage still yields
a `Path` that does not exist. Harmless for ordering, but worth remembering if the flows ever
iterate the queue eagerly. Belongs to `Insta-Automate`, so it is feature-branch territory.

---

## 2026-07-31 — Phase 1 implementation session (CP 1.3)

### D7 · Open `config.env` by replicating the `code` shim, not by running `Code.exe`
**Chosen:** `FileOpener.openForEditing` resolves `code.cmd` on `PATH` to locate the install root,
then launches `Code.exe <cli.js> <path>` with `ELECTRON_RUN_AS_NODE=1` via `Process.start`
(detached), falling back to the shell association, then Notepad.
**Rejected:** `CreateProcess` on `Code.exe "<path>"` — this *silently does nothing*. It starts a
second Electron main process which exits without opening the file, while `CreateProcess` still
reports success, so the failure is invisible to the caller. Also rejected: `cmd /c code "<path>"`,
which re-introduces the console flash D5 exists to avoid.
**Why:** the *Open* button did nothing across two CP 1.3 test rounds. Reading `code.cmd` showed
the shim is not a thin wrapper around `Code.exe` at all — it runs the `cli.js` entry point under
`ELECTRON_RUN_AS_NODE`, and *that* is what hands a file to the running window. Verified by exit
code (`0`) before shipping. `Process.start` is safe here where D5 forbade it, because the flash D5
describes only affects console-subsystem binaries like `uv`/`python`; `Code.exe` is GUI-subsystem.
**Corrects an earlier claim in this entry:** the first version blamed `.env` having no file
association. That was wrong — measured directly, `ShellExecute('open')` on `config.env` returns
`42` (success) on this machine. The association was never the problem.
**Cost:** two path heuristics (`code.cmd` lives in `<install>\bin`; `cli.js` sits under
`resources\app\out`, possibly beneath a version-hash directory, so it is searched for rather than
assumed). The fallback chain covers a layout change.

---

## 2026-07-31 — Phase 1 implementation session (CP 1.1)

### D6 · `/ws` broadcasts every event to every client, no channel filtering yet
**Chosen:** the new `/ws` endpoint (`api/ws.py`, `events/bus.py`) sends every published event,
tagged `{channel, data}`, to every connected client. There is no client-side subscribe protocol.
**Rejected:** building ARCHITECTURE §3.2's full per-channel subscription + replay-cursor model now.
**Why:** `config.changed` is the only channel that exists so far, so subscription filtering has
nothing to filter yet. Building it against one channel risks guessing the wrong shape for the
eight others (`services.status`, `flow.events`, `library.changes`, ...) that show up in later
phases.
**Cost:** every connected client gets every event once more channels exist — revisit when a
second channel lands (Phase 2's `services.status` is the likely trigger) and add subscribe/
unsubscribe + replay then, not speculatively.

---

## 2026-07-31 — Phase 0 implementation session

### D5 · Launch ia-agent via raw Win32 `CreateProcess` with `CREATE_NO_WINDOW`
**Chosen:** the desktop app's *Start agent* action calls `package:win32`'s `CreateProcess`
directly over FFI, passing `CREATE_NO_WINDOW`, instead of `dart:io`'s `Process.start`.
**Rejected:** `Process.start(..., mode: ProcessStartMode.detached)` — `uv`/`python` are
console-subsystem executables, and `dart:io` never exposes Windows' `CREATE_NO_WINDOW` creation
flag, so a bare `Process.start` flashes a visible terminal window every time the button is
pressed.
**Why:** caught during CP 0.3 manual testing — clicking *Start agent* popped a console window,
which is exactly the `wt.exe`-shortcut experience this project exists to replace (see
EXPECTATION.md's no-compromise-on-UI/UX rule and CLAUDE.md §Rules #6).
**Cost:** two new Flutter dependencies (`win32`, `ffi`) and one raw-FFI call site
(`app/lib/core/agent_launcher.dart`) that has to track the `win32` package's API shape (pinned to
6.3.0's extension-type-based bindings at time of writing).

---

## 2026-07-30 — Planning session

### D4 · Desktop gets full curation parity
**Chosen:** the Windows app implements the image review workflow (entity grids, multi-select,
apply-to-next-stage, delete, queue ordering) that today only exists on the phone.
**Rejected:** observability-only, and read-only-viewer-first.
**Why:** the two human gates in the pipeline (`gender_valid → scrape_queued`,
`scraped → follow_queued`) are the pipeline's actual bottleneck, and reviewing 7,566 images on a
phone is the slow path. Doing it at the laptop also makes Syncthing latency irrelevant.
**Cost:** Phase 5 is a substantial phase; the grid must be virtualized and keyboard-driven from
the start.

### D3 · LAN WebSocket notifications with a Telegram backstop
**Chosen:** the phone holds a WebSocket to the agent via an Android foreground service and raises
local notifications; the agent answers `{delivered}` and the flow falls back to
`tl.bot.notify(...)` when nothing was listening.
**Rejected:** FCM (needs a Firebase project and routes metadata through Google) and
Telegram-stays-primary (keeps the delay and the context switch being designed away).
**Why:** the requirement was scoped to "when I'm on the same wifi". Keeping it local avoids a
cloud dependency entirely, and Telegram already works as the away-from-home path.
**Cost:** only works on the LAN, and Android shows a persistent foreground-service notification.

### D2 · Structured flow events, not log scraping
**Chosen:** add a failure-tolerant `emit()` beside the existing `log.info` calls at every
image-producing point, and have the agent cache image bytes the moment an event arrives. Backed
by a filesystem watcher for everything not covered by an event.
**Rejected:** parsing paths out of Prefect log messages with regex.
**Why:** `entity_classify` unlinks public profiles and moves the rest, and `entity_follow`
unlinks the image immediately after logging it. A log-scraping UI races those deletions and shows
holes. Events also carry verdicts, skip reasons with real numbers, and counters that the log
lines only partly contain.
**Cost:** a real diff in `Insta-Automate` (`tasks/ia.py`, `tasks/ollama.py`, the five flow
bodies), on a feature branch.

### D1 · Flutter UI + Python `ia-agent`, both in this repo
**Chosen:** a FastAPI agent at `agent/` becomes the single Windows startup entry, replacing the
`wt.exe adb … ; start_vl_server.py ; wsl-bridge.exe` shortcut. It supervises the three core
services, ingests flow events, and serves both the desktop app and the paired phone. The Flutter
app is a pure client.
**Rejected:** Flutter-only (services would die with the window, and the pods would lose their
notify endpoint whenever the UI is closed) and extending `wsl-bridge` (all the work would land in
an external repo, and wsl-bridge would stop being a supervisable core service by becoming the
supervisor).
**Why:** services must outlive the UI; the phone needs the same API the desktop uses; and Python
already owns every integration required (`adbutils`, `telethon`, `my_modules.*`, the Prefect
client).
**Cost:** two processes to keep alive instead of one; the agent needs adoption logic so it can
restart without killing a running scrape.
