# Decision log

Newest first. Each entry records what was chosen, what was rejected, and why — so a future
session can tell a settled question from an open one.

---

## 2026-07-31 — Phase 3 implementation session (CP 3.1, typed live config)

### D24 · `Limit` is generalised into `Config` by aliasing, not renaming call sites

**Chosen:** `insta_automate.models.meta.Config` replaces `Limit` as the real class — typed
`get(key)` returning `int | float | bool | str`, inferred from the type of each key's own default
(bool checked before int, since `bool` is an `int` subclass in Python). `Limit = Config` at module
scope, so every existing call site (`scan.py`, `scrape.py`, `follow.py`, `entity_follow.py`,
`entity_scrape.py`, `controllers/prefect.py`, `tasks/ia.py`) keeps importing and calling `Limit`
unchanged. `_DEFAULTS` now carries every key from ARCHITECTURE §4.1 — the nine existing limits plus
eleven trigger timings, two gates (`SCRAPE_BACKPRESSURE_FACTOR`, `SCAN_LIST`), and two
control-center wiring keys (`IA_AGENT_URL`, `NOTIFY_POLICY`) — all absent from `config.env` today
and resolving to their coded defaults with no error, exactly as designed: CP 3.2 is what starts
reading them from the scheduler.

**Q3 answered: yes, `PROFILES`/`REELS`/`POSTS` are genuinely the live daily scan caps.**
`Scan.limit_reached` (`models/scan.py`) compares today's counts against `Limit.get(...)` for all
three, and `entity_scan_trigger` (`controllers/prefect.py:150-166`) pauses the trigger loop until
the next day when it fires. `config.env`'s own comment claimed the opposite — that these "only
bound Scan's schema" — which was simply wrong; corrected in the same commit.

**Rejected:** a parallel `Config` class living beside `Limit` with call sites migrated one by one —
unnecessary churn across five files for a rename that changes no behaviour, and the alias gets
identical type-checking (`Limit.get("FOLLOW")` still returns `int` for every key actually in use
today, since none of the new keys are read anywhere yet).

**Why:** the plan (`docs/PLAN.md` CP 3.1) specifies keeping `Limit` as an alias explicitly, and
`SCRAPE_BACKPRESSURE_FACTOR` in particular has no reader yet — CP 3.2 replaces the hardcoded `* 3`
in `entity_scrape_trigger` with it.

**How to apply:** any new trigger-timing or gate key CP 3.2 needs should be added to
`Config._DEFAULTS` with a same-typed default, not read directly from `config.env` — that's what
keeps an absent key from ever being an error.

---

## 2026-07-31 — Phase 2 implementation session (CP 2.6, services outlive the agent)

### D23 · The pty moves to a detached host, spawned through a launcher that exits immediately

**Chosen:** a new process, `services/host.py` (run as `python -m ia_agent.services.host <name>`),
owns the ConPTY that used to live in the agent. It never has the agent as its *live* parent: the
agent spawns `services/host_launcher.py`, which starts the host and exits within milliseconds, so
by the time anything tree-kills the agent, the host's `ppid` points at an already-dead launcher and
is unreachable from that walk — the same mechanism D22's own experiment measured. Two channels
cross the process boundary, kept deliberately separate: the raw output stream
(`%LOCALAPPDATA%\ia-agent\run\<name>.stream`, truncated fresh per spawn, tailed into the existing
`LogRing` so the `seq`/`?since=` contract, D18, does not change) and resize, over a Windows named
pipe (`multiprocessing.connection`, stdlib only) — the one thing a file cannot carry. A third file,
`<name>.json`, extends the old PID-file schema with `host_pid`/`host_create_time` and `exit_code`:
once the exit-immediately launcher is gone, the agent has no OS-level wait() relationship to the
host, so this file is the *only* way it learns the exit code.

Host takes its spawn parameters (cmd/cwd/env/rows/cols) from a small `<name>.spawn.json` the
supervisor writes just before launching it, rather than looking a `ServiceSpec` up by name in the
registry. Host needs none of `ServiceSpec`'s probe/self-test callables — only the supervisor probes
and tests — and taking them as data keeps host usable for whatever a caller wants run in a pty,
which is what let the test suite spawn its fake services through the exact same path as the three
real ones instead of a special case.

**Rejected:** a job object granting the host `KILL_ON_JOB_CLOSE`-style protection (unnecessary —
Windows does not kill a child when its immediate parent exits, it only orphans it, so plain process-
tree topology is enough); resolving the host's spec via `registry.build_specs()` by name (would have
made the test suite's dummy services unspawnable through the real path, which is exactly the
structural gap D22 says let the old adoption test miss the bug); and keeping the resize path on the
same file as output (a file has no way to signal "this pty's grid changed" to a process that already
has it open for writing).

**Why:** measured, cross-process this time. `agent/tests/fake_agent_process.py` builds a real
`Supervisor` in its own process, spawns a service through the real host path, and the outer test
(`test_supervisor.py` §14) `taskkill /F`s and separately `taskkill /F /T`s that process — the host
and the service it owns survive both, with the same pids, and a fresh `Supervisor.adopt()` recovers
`terminal_available: true` with the real output intact. This is the test D22 says the old two-
Supervisors-in-one-process adoption test structurally could not be, because in that shape the pty
handles never actually closed. Verified live on this machine too: took all three real services under
supervision, killed `ia-agent.exe` outright, and vl-server/wsl-bridge came back `adopted` on the
same pids with zero restarts and their real startup logs (including vl-server's model-load banner
from *before* the kill) replayed into the terminal.

**Known interaction, not a bug:** the job object in `ia_agent_launcher.pyw` (D21) has no breakaway
flags, so the host — like everything else the agent spawns — is a member of it. That job's handle
only closes when the launcher itself ends (`schtasks /End`, or the launcher dying), never on a plain
agent crash or restart, which is the case this checkpoint and D21's backoff loop both cover. So
`schtasks /End` remains "genuinely stop everything" (already the documented behaviour, D21) and will
also stop supervised services now; a routine agent crash or restart will not.

**Also observed, not caused by this change:** adb's `-a nodaemon server start` forked a detached
`adb -L tcp:5037 fork-server server` grandchild that escaped the host's process entirely, twice,
independent of anything this checkpoint did to the agent. Both the wrapper and its host ended up
gone while the fork kept the port, which the agent correctly reports as `external` (D11 already
anticipates exactly this shape) rather than silently losing track of it. Not a CP 2.6 regression —
`registry.py`'s adb spec is untouched — and not this checkpoint's to fix.

**Cost:** two more files under `%LOCALAPPDATA%\ia-agent\run\` per service (`.spawn.json`,
`.stream`, alongside the richer `.json`), one more stdlib IPC surface to reason about, and adoption
now starts a tailer thread instead of doing nothing — a small amount of always-on complexity in
exchange for D10 finally being true.

---

## 2026-07-31 — Phase 2 implementation session (CP 2.5, agent autostart)

### D22 · Supervised services die with the agent today, and the fix is CP 2.6
**Chosen:** ship CP 2.5 knowing that anything the agent supervises dies when the agent dies, and
close the hole in its own checkpoint (CP 2.6) with a detached host process that owns the
pseudo-console. Until then the loop is: agent dies → its services die → the launcher restarts the
agent → the agent restarts them from their `autostart` switches. Seconds of downtime, self-healing,
and no flow survives it.
**Rejected:** accepting it permanently (every agent restart across Phases 3–7 would take adb,
vl-server and wsl-bridge with it, and any flow running at that moment); and building the host
inside CP 2.5 (a supervisor rework plus three test suites, with the reboot test hostage to it).
**Why:** measured, not reasoned. A service spawned into a ConPTY dies whenever the agent's handles
close — on a clean `sys.exit`, on `taskkill /F`, and on `taskkill /F /T` alike. So D10's promise
("supervised processes outlive the agent; PID files are what the next run adopts") has been false
since services moved into pseudo-consoles in CP 2.1, and the adoption tests never caught it because
they build two `Supervisor`s inside one process, where the pty handles never close. The fix is also
measured: with the pty owned by a small detached host, the service survived a clean exit, a `/F`
kill, and a `/F /T` tree-kill (that last one only when the host is orphaned through a launcher, since
a tree walk otherwise reaches it), and its raw output kept appending to a file across the kill —
which is what a replay needs.
**Cost:** D10 is aspirational until CP 2.6, and CP 2.4's "restart the agent mid-scrape" claim does
not hold yet. The plan says so at both places.

### D21 · The launcher heals the agent; Task Scheduler does not
**Chosen:** `agent/scripts/ia_agent_launcher.pyw` starts the agent, waits for it, and restarts it on
any non-zero exit with 5 s → 300 s backoff (reset once the agent has been up two minutes), stopping
only on a clean exit or when `%LOCALAPPDATA%\ia-agent\stop-launcher` exists. The task's logon trigger
repeats every 10 minutes with `MultipleInstancesPolicy: IgnoreNew` as the outer net for the launcher
itself dying. The launcher holds the agent in a job object with `KILL_ON_JOB_CLOSE`.
**Rejected:** `RestartOnFailure`, which is what a logon task was chosen for in the first place; and a
launcher that spawns and exits, which would leave Task Scheduler with nothing to track.
**Why:** all three parts are measurements. `RestartOnFailure` (`PT1M`, count 3) did **not** restart a
killed agent — the task recorded `Last Result: 1`, went to `Ready`, and sat there for three minutes.
The repetition trigger did: a killed task was running again 55 s later. And `schtasks /End` killed
only the launcher, leaving the agent serving on 8787 as an orphan whose parent was gone — so the
documented way to stop the agent left something holding the port the next run needs. The job object
closes that: when the launcher dies, by `/End` or otherwise, the agent and its uv trampolines go
with it.
**Cost:** a supervisor of the supervisor, in a file that runs on the base interpreter and therefore
cannot import anything from the agent. `schtasks /End` is now genuinely "stop everything", which also
means it is not a way to restart the agent alone.

### D20 · The logon task runs a GUI-subsystem interpreter, never the agent directly
**Chosen:** the task's action is the **base** interpreter's `pythonw.exe` (`sys.base_prefix`, PE
subsystem 2) against the launcher `.pyw`, which then starts `ia-agent.exe` with `CREATE_NO_WINDOW`
and redirects its output to `%LOCALAPPDATA%\ia-agent\logs\startup.log`.
**Rejected:** `ia-agent.exe` with the task's `Hidden` setting (that flag hides the task in the Task
Scheduler UI, not the window); the venv's `pythonw.exe`; and `CREATE_NO_WINDOW` combined with
`DETACHED_PROCESS`.
**Why:** Task Scheduler exposes no window style, so what matters is the subsystem of the exe it
starts. Measured under a real interactive logon task: `python.exe` showed a visible console for its
whole run, and so did the venv's `pythonw.exe` — it is a uv trampoline that re-execs the console
interpreter, and the pid that appeared on screen was not the pid the task started (the same
trampoline shape as D11). The base `pythonw.exe` reported `GetConsoleWindow() == 0` and no window was
visible from outside. `CREATE_NO_WINDOW` is passed alone because Windows ignores it when
`DETACHED_PROCESS` or `CREATE_NEW_CONSOLE` is also set — the first attempt combined them and put a
console window on screen, which is the exact thing this checkpoint exists to remove.
**Cost:** the task depends on a path under `%APPDATA%\uv\python\…` that a uv toolchain upgrade can
move, so `startup.py status` re-checks it and `install` must be re-run if it changes. The agent's own
stdout is only readable in `startup.log`.

---

## 2026-07-31 — Phase 2 implementation session (CP 2.4, Services UI)

### D19 · The panels above the terminal are capped; the terminal keeps a floor
**Chosen:** the detail pane is `LayoutBuilder` → a `ConstrainedBox(maxHeight: available − 220 − 16)`
holding a `SingleChildScrollView` of the header/stats/switches/test panels, then `Expanded` for the
terminal. Layout regressions are caught by `app/test/services_layout_test.dart`, which renders the
widgets at three pane widths with deliberately awkward values and fails on the first pixel over.
**Rejected:** the plain `Column` + `Expanded(terminal)` this shipped with (overflowed by 199 px at
the minimum window); scrolling the whole pane with the terminal at a guessed fraction of the
viewport (leaves dead space under the terminal in a tall window); and `SliverFillRemaining`, which
collapses the terminal to nothing exactly when the panels are the ones overflowing.
**Why:** at the 1024 px minimum window the pane is ~550 wide, the stat chips wrap onto four rows and
every card's text wraps with them — the panels genuinely want more height than the window has, so
`Expanded` was being handed negative space. Capping them with a *maximum* rather than a share is
what keeps both ends honest: cramped, they scroll and the terminal still gets 220 px; roomy, they
take their natural height and the terminal gets every remaining pixel with no gap.
**Cost:** two scroll regions in one pane at small sizes. Accepted because the terminal is the thing
you are watching, and it staying put while the panels scroll is the behaviour you want.
**Worth remembering:** this was found because the user's screenshot showed a 43 px overflow in the
metrics row and the test written to chase it found three more. Overflow is a *paint-time* error —
`flutter analyze` cannot see it, and neither can any agent-side test. The first version of that test
used 560 and 1400 px panes and reproduced none of it: the reported bug needs ~1250 px, the width a
maximized 1920 window leaves. Test at the size the real screen produces, not at round numbers.


### D18 · The agent's ring is the terminal's source of truth; the client dedupes by `seq`
**Chosen:** the pane replays `GET /services/{name}/logs` on mount, holds back any live chunks that
arrive while that request is in flight, merges both by sequence number, and drops anything it has
already rendered. A dropped WebSocket re-replays from `?since=<last rendered>`. Navigating away and
back rebuilds the emulator from the server rather than keeping it alive off-screen.
**Rejected:** trusting the live stream to continue exactly where the replay stopped, and keeping the
terminal widget alive across navigation to preserve scrollback.
**Why:** measured, not assumed — the ring is written by the reader thread the instant the process
prints, while the WS batch for those same chunks is published on the next supervisor tick, up to
250 ms later. So replay-then-subscribe reliably delivers the same chunks twice; a first attempt at
`test_ui_contract.py` asserted the opposite and failed against correct behaviour. Overlap is
harmless and a gap is not, so the client absorbs the overlap and the test now pins both properties
(no gap, full coverage of every sequence number).
**Cost:** re-opening the Services tab re-fetches up to 512 KB of scrollback. Cheap on localhost, and
it means there is exactly one copy of the truth.

### D17 · A pane with nothing to render explains itself instead of rendering the ring
**Chosen:** `external` and `adopted` services show a card naming why there is no output and what to
do about it (take over / restart), never a terminal. A *stopped* service is treated differently: its
ring is genuine output, so it keeps the terminal with a banner saying this is history and, where
there is one, the exit code.
**Rejected:** gating purely on `terminal_available`, which is what the endpoint offers.
**Why:** an external service's ring is not empty — it holds exactly one chunk, the agent's own dim
note that the port was taken by someone else. Rendering it would produce a "terminal" whose entire
contents are one line about itself. That is the state all three real services are in today, so it is
the first thing the screen shows. Meanwhile `terminal_available` is also false for a supervised
service that exited, where the output is exactly what you want to read — which is the whole point of
being able to switch self-heal off (D12).
**Cost:** one more piece of client-side state to keep in step with the origin enum; the rule is
"detached (external/adopted) → explain; otherwise render whatever the ring has".

### D16 · The dependency panel is the Services screen's second tab
**Chosen:** Services is two tabs — *Supervised* (the three services, master–detail with the
terminal) and *Dependencies* (CP 2.3's ten read-only checks).
**Rejected:** waiting for the Overview screen, which ARCHITECTURE §9 earmarks for a dependency
strip.
**Why:** CP 2.3 shipped `GET /api/dependencies` with no UI, and Overview is not in Phase 2 — the
panel would have stayed invisible until Phase 7. Both tabs answer one question about one machine
("is this laptop able to run the pipeline?"), and the split is honest about the difference that
matters: one tab has buttons because the agent owns those processes, the other has none because it
does not.
**Cost:** Overview will later show a condensed version of the same data; this stays the detailed
view rather than being moved.

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
**Measured limit, found 2026-07-31 by doing it:** this holds for a *graceful* exit only. Killing the
agent's **process tree** takes every supervised service with it — all three were taken over during
the CP 2.4 test, and killing the agent that way left the machine with no adb, no vl-server and no
wsl-bridge (restarted by hand; PID files were left behind, which is exactly the stale-file case the
`create_time` guard exists for). Not yet measured: whether killing the agent process *alone* (Task
Manager's "End task") does the same, which it plausibly does since each service is attached to a
pseudo-console the agent owns. **CP 2.5 has to answer that before it turns on restart-on-failure**,
because a logon task that restarts a crashed agent would otherwise cycle all three services with it.

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
