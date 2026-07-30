# Decision log

Newest first. Each entry records what was chosen, what was rejected, and why — so a future
session can tell a settled question from an open one.

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
