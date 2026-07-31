# MEMORY.md

Durable facts and decisions for this project. One line per entry, newest last.
Full context lives in [CLAUDE.md](CLAUDE.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md),
[docs/PLAN.md](docs/PLAN.md), and [docs/DECISIONS.md](docs/DECISIONS.md).

- **Context files stay in the repo** — `CLAUDE.md`, `MEMORY.md` and `docs/` never go anywhere
  else on the filesystem. User rule, applies to every session.
- **Other repos are feature-branch only** — `Insta-Automate`, `Insta-Automate-Client` and
  `Helmcharts` all work today; changes go on `feat/control-center` (or `feat/lan-agent`) and are
  never merged until the control center is accepted.
- **Architecture** — Flutter Windows app (`app/`) + Python `ia-agent` (`agent/`) in one repo; the
  agent is the Windows startup entry and owns service lifetime. See DECISIONS D1.
- **The scheduler is one file** — every hardcoded delay and trigger gate lives in
  `Insta-Automate/src/insta_automate/controllers/prefect.py`.
- **Two human gates** — `gender_valid → scrape_queued` and `scraped → follow_queued` are manual
  moves; they are the pipeline's real bottleneck and the reason the desktop gets curation parity.
- **Committed secrets** — `Insta-Automate/Dockerfile` holds the Postgres password, the Telegram
  bot token and two Telethon session strings in plaintext; `ia build` regenerates it, so it never
  needed committing. Rotation pending (PLAN Q10).
- **The user drives the app, never Claude** — Claude may build, analyze and *start* the Flutter
  app, then must stop and hand over. No clicking, navigating or screenshotting the GUI: the laptop
  is single-screen with VS Code maximized, so driving the window disrupts the workspace.
  EXPECTATION.md #8, CLAUDE.md rule 5. Backend (agent REST/WS, config round-trips) is still
  Claude's to verify with curl/scripts. **Violated once in the CP 1.3 session — do not repeat.**
- **⚠ All five flow switches are OFF since 2026-07-31, deliberately and temporarily** — set so the
  pods and helm chart can be worked against without flows firing on their own. Must be restored to
  `1` when Phase 2 is accepted. Restore recipe and the exact semantics are at the top of CLAUDE.md.
  Switch OFF blocks `Deployment.trigger()` only: manual Prefect triggers still work, and the
  scheduler's loops keep polling the DB, waiting on the device and pinging Telegram.
- **Phase status** — Phases 0 and 1 complete (CP 0.1–0.3, 1.1–1.4), all user-verified. Phase 2:
  CP 2.1 (supervisor engine, ConPTY terminals, self-heal), 2.2 (probes + functional self-tests) and
  2.3 (dependency panel) done and Claude-verified; CP 2.4 (Services UI, with the dependency panel
  as its second tab) done and user-verified. Only CP 2.5 (agent autostart) left in the phase.
- **`insta-automate` is the scheduler, `insta-automate-worker` runs the flows** — helm `server.yaml`
  runs `ia prefect serve` (trigger loops); `worker.yaml` runs the Prefect worker. Both pods carry
  the same `app: insta-automate` label and one name prefixes the other, so match pods by stripping
  the `-<pod-template-hash>-<suffix>`, never by prefix or label.
- **A Prefect work pool existing is not the same as it being served** — an unattended pool leaves
  flow runs Pending forever, so health checks must assert an ONLINE worker is polling it.
- **vl-server's health is a token count, not a stopwatch** — the 1080×198 fixture costs 231 prompt
  tokens under `--image-min-tokens 64`; Ollama's hardcoded 1024 makes the same crop ~1067 tokens and
  7–12 s of CPU CLIP encode. Assert on tokens (ceiling 800): unlike wall-clock it doesn't move with
  machine load. Warm inference is ~150 ms, cold 420–750 ms, so any timing test must warm up first.
- **Never cycle scrcpy to test wsl-bridge** — `POST /scrcpy/start` calls `stop()` first
  (`wsl_bridge/scrcpy.py:23`), so testing a live mirror kills it and throws a new window onto the
  user's single screen. Test non-destructively when it's already running.
- **The pid that binds a port is not the pid you launched** — uv venv `python.exe` and console
  scripts are trampolines that re-exec the managed interpreter, and `start_vl_server.py` runs its
  own restart loop around `llama-server.exe`. Killing only the socket owner makes the launcher
  respawn it and fight you. Walk the parent chain to the service root; stop at session hosts and
  at the agent's own lineage. D11.
- **Agent restart must never stop a service** — supervised processes outlive the agent; PID files
  (guarded by `create_time` against PID reuse) are what the next run adopts. Stopping is only ever
  an explicit operator action. D1's stated cost, D10.
- **The agent is the only supervisor** — services' own restart loops are switched off
  (`start_vl_server.py --no-autorestart`; adb runs `nodaemon`, not the forking `start-server`).
  Nested supervisors resurrect processes underneath a stop and hide their restart counts in an
  unread terminal tab. D14.
- **Service output is a raw ConPTY stream, never line-stripped** — ANSI, cursor moves and carriage
  returns are exactly what the in-app terminal (`xterm.dart`) needs; a progress bar is one line
  rewritten many times, so splitting on newlines erases it. Under a pipe the child sees
  `isatty()==False` and drops colour entirely — measured, not assumed. D15.
- **`config.env` is the pipeline's, `services.json` is this machine's** — self-heal/autostart
  switches are agent-local and must never be synced to the phone or read by a pod. D12.
- **`ENTITY_QUEUE` is one shared list, by design** — it holds *entity names*; each `Queue` maps
  that ordering onto its own directory, so scrape and follow differ by folder, not by key. Q1
  answered, see DECISIONS D8. Unlisted entities still run, after the listed ones, oldest first.
- **Agent launch avoids a console flash** — `app/lib/core/agent_launcher.dart` uses
  `package:win32`'s `CreateProcess` with `CREATE_NO_WINDOW`, not `dart:io`'s `Process.start`. See
  DECISIONS D5.
- **The user's editor is VS Code** — `code` is on `PATH`. Opening a file means running
  `Code.exe <cli.js> <file>` with `ELECTRON_RUN_AS_NODE=1` (what `code.cmd` does). Running
  `Code.exe <file>` reports success and does nothing. D7.
- **Verify Windows launch paths by exit code before shipping them** — spawn APIs report that a
  *process started*, not that it did the job, so `CreateProcess -> true` hid a total no-op through
  two CP 1.3 test rounds. Two wrong guesses were handed to the user before the shim was read.
- **A terminal replay and the live stream overlap by design** — the agent's ring is written by the
  reader thread the instant a service prints, while the WS batch for those same chunks goes out on
  the next supervisor tick (≤250 ms later). So replay-then-subscribe delivers chunks twice; the pane
  dedupes by `seq` and re-replays with `?since=` after a drop. Overlap is expected, a *gap* is the
  bug. A first version of `test_ui_contract.py` asserted the opposite and failed against correct
  behaviour. D18.
- **`terminal_available: false` has two very different meanings** — for `external`/`adopted` there
  is no output and never was (the ring holds only the agent's own note), so the pane explains
  itself; for a *stopped* supervised service the ring is the real final output, which is exactly
  what self-heal-off exists to let you read. D17.
- **The app's payload contract is pinned by `agent/tests/test_ui_contract.py`** — Dart's casts throw
  where Python's dict access shrugs (`as int?` on a float, `as bool?` on 0/1, a renamed key), so the
  field tables there are transcribed from `app/lib/core/service_models.dart` and
  `dependency_models.dart` and must be kept in step with them.
- **Overflow is a paint-time error, so `flutter test` is part of a UI checkpoint's gate** —
  `flutter analyze` cannot see it and neither can any agent-side test; the CP 2.4 one was found in
  the user's screenshot. `app/test/services_layout_test.dart` renders the widgets at three pane
  widths with the awkward real values. **Test at the size the screen actually produces**: that test
  first used 560 and 1400 px panes and reproduced nothing — the reported bug needs ~1250, the width
  a maximized 1920 window leaves after the rail and the tile list. D19.
- **Never commit a UI checkpoint before the user has tested it** — CP 2.4 was committed with
  "awaiting your test" in the message, which is still a commit and still wrong; the manual test *is*
  the checkpoint. Build, analyze, start, hand over, then wait for the verdict. CLAUDE.md rule 4 and
  EXPECTATION.md #8. **Violated once in the CP 2.4 session — do not repeat.**
- **Always use `AppSnackBar`, never `ScaffoldMessenger` directly** —
  `app/lib/core/app_snack_bar.dart` clears before showing. The default messenger *queues*, so
  several quick edits played back-to-back and looked like a bar that never dismissed (CP 1.3 bug).
