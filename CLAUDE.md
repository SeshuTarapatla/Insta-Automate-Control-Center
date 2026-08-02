# CLAUDE.md — Insta-Automate Control Center

Read this first, then [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and
[docs/PLAN.md](docs/PLAN.md). Current state: **Phases 0, 1 and 2 complete and accepted**, **Phase 3
complete and accepted** (CP 3.1–3.5, Trigger delays & conditions), **Phase 4 complete** (CP 4.1–4.5:
log + event aggregation, flow instrumentation, the Live screen, device view — user-verified
2026-08-01. The Live screen's visual polish pass flagged as open at the time happened later the same
day, once CP 5.1's live pipeline fixes (D36–D39) gave it real data to look wrong against for the
first time — D40 through D46, all recorded below and in DECISIONS.md). **Phase 5 (Library & curation
parity) complete and accepted 2026-08-01** — CP 5.1 (Library API), CP 5.2 (Mutations), CP 5.3
(Library UI) and CP 5.4 (Entity view), every checkpoint PLAN.md scoped for this phase (CP 5.1/5.2
agent-only 🟢, CP 5.3/5.4 user-verified 🟢) — see the dedicated paragraphs below. **Phase 6 (Mobile
pairing & notification rework) is open, CP 6.1 (Pairing + notification core) done, agent-only,
🟢, CP 6.2 (Notifier facade) done, cross-repo `Insta-Automate` on `feat/control-center`, 🟡,
CP 6.3 (Desktop pairing & notification center) built, committed, and verified against the real
agent with the pairing round trip backend-mocked (curl standing in for the phone) since CP 6.4
doesn't exist yet, 🟢, CP 6.4 (Mobile client) built across all four slices (pairing, WS +
foreground-service push notifications, compact live flow view, config write-through) and verified
live against the real agent and a real phone, then extended with a notification-routing redesign
(D58) found by actually using it — device-aware `delivered`/`targets` (a phone, not just the
desktop, has to be connected), always-Telegram + tap-to-open for the three per-profile
notifications, and real markdown rendering on both clients — 🟢, then D58's *pipeline* half found
undeployed hours later (D59 — a forgotten `git push` meant the live worker pod kept running
pre-D58 code; fixed the D39 way, push + `ia build` + restart + redeploy; not yet independently
confirmed against a real Telegram delivery). **Phase 6 is explicitly not being accepted yet** —
you flagged other changes/bugs to address first before the next checkpoint, so treat CP 6.1–6.4 as
built and deployed, not signed off — see the dedicated paragraphs
below. **2026-08-02: a live incident (`entity-follow` permanently
frozen "running", zero triggers for hours) uncovered and fixed five chained bugs — see D55 and the
dedicated paragraph below. CP 6.2 is now deployed to the live worker pod for the first time**,
earlier than rule 3's original "wait until accepted" plan, because it was needed for the fix. Phase 2 accepted
2026-07-31 — the user accepted it
outright without a separate CP 2.6 verification pass. The
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

**Addendum, 2026-08-01 (CP 5.1 session): it stayed undeployed for two more sessions by accident.**
The Live screen's visualization surfaces were still blank on every real scrape run you tried after
CP 4.4/4.5 — turned out `feat/control-center` in `Insta-Automate` was never pushed to `origin`
(3 commits behind, `22a706d` — this checkpoint's own commit — among them), and Prefect's deployments
`git_clone` from the GitHub remote, not local disk, so the worker pod had been executing pre-CP-4.3
code the whole time with no instrumentation in it at all. Pushed now (`git push origin
feat/control-center`); no pod restart needed since the worker re-clones on every flow run. See D36.

**Still blank after that — a second, separate gap (D37).** The worker pod (the one that actually
executes `emit()`/`emit_sync()`) never had `IA_AGENT_TOKEN` set at all, only the scheduler pod did —
so every event POST 401'd, and `AgentClient`'s swallow-everything-by-design (D26) meant that failed
completely silently, no error anywhere, even though the flow itself ran for real (180/300 scraped,
confirmed against `/api/flow-runs`). Fixed with `kubectl set env deployment/insta-automate-worker
IA_AGENT_TOKEN=<token>` (confirmed with you first — restarts the worker pod). Both this and the
scheduler's own `IA_AGENT_TOKEN`/`GIT_BRANCH` are manual `kubectl set env` patches, not in the
committed helm chart — CP 7.1 is where they're planned to move into real helm values; until then a
worker redeploy for any other reason will need this patch reapplied.

**Also found: the worker pod's `create-work-pool` init container deletes and recreates the whole
work pool on every pod start (D38)**, not idempotently — the D37 restart triggered it, orphaning all
six deployments (`work_pool_name: None`, stuck `Late` runs, worker online but nothing to hand it).
Fixed with `ia prefect deploy` (re-registers them against the current pool); the init container
itself is unfixed and will repeat this on any future worker restart for any reason.

**D36 was incomplete — corrected as D39.** Even with the branch pushed and deployments healthy, still
zero per-item events. Turned out `git_clone` only refreshes the flow's own top-level file; everything
it imports (`tasks/`, `controllers/`, `models/` — exactly where CP 4.3's `emit()` calls live) stays
frozen at whatever was `pip install`ed into the worker's Docker image at build time. Confirmed by
`kubectl exec`-ing in and inspecting the actually-loaded `profile_scrape` source directly — genuinely
pre-CP-4.3, no `emit()` calls at all, despite the branch being current. Fixed for real this time with
`ia build` (13s, pins the exact pushed commit) + `kubectl rollout restart` on the worker (confirmed
with you first — the biggest action of the session) + `ia prefect deploy` again for D38. Re-verified
post-rebuild: the new pod's installed `profile_scrape` now has all 6 `emit()` calls. Not yet
confirmed against one more real device-driven scrape run.

**CP 4.4 (Live screen) done and user-verified, 🟢.** `app/lib/features/live/`: a flow-selector row
above three panes — `LogConsole` (level filter, task-change dividers, sticky expandable error strip,
scroll-aware auto-follow), the per-flow visualization surface (scan filmstrip, classify verdict
stream with img/s, scrape/follow before→after cards, ingest hero grid), and `RunSummary` (phase/
today/last-run + this-run counters + a device pane, filled in for real by CP 4.5 below).
`LiveController` replays
`/api/flow-runs/{id}/logs` and `/api/events` once, then stays current via `flowrun.logs`/
`flow.events`, resetting on a new `last_run.id` rather than every heartbeat tick. New
`core/agent_image.dart` fetches `/api/images/{key}[/thumb]` through `dio` for its auth header.
`flowTitle`/`phaseLabel` moved from `flow_card.dart` into shared `scheduler_models.dart`. **Found by
the new `live_layout_test.dart`, not `flutter analyze`** (same overflow-is-paint-time class as D19):
`AgentImage`'s placeholder overflowed at the classify surface's 1080:198 row-crop aspect ratio sized
to ~18px tall — fixed with `FittedBox(scaleDown)`.

**Tested live against a real scrape run.** The long-lived `ia-agent.exe` process had to be restarted
mid-test — it predated this whole session and had none of CP 4.1/4.2's routes, producing 404s that
looked like app bugs but were really "the code changed, the running process didn't." The log console
worked immediately after that (Prefect's own execution log, no pipeline dependency); the
visualization surfaces stayed empty as expected (need CP 4.3's `emit()` calls deployed to the live
pod, which hasn't happened). **Corrected after your feedback:** the log line rendering was hard to
read (monospace, 1px line spacing, level as inline color) — rebuilt as timestamp + a colored level
pill + message in the normal body font at 1.4 line height, deliberately far short of Prefect's own
log view's chrome. Also found and fixed: a `IA_AGENT_URL not found` warning flooding the merged
scheduler-pod log lines — not new (fires every heartbeat since CP 3.4), just newly visible because
D30's pod-log merge is what surfaced it. Fixed by writing the coded default straight into the real
`config.env`, since that key is deliberately outside the app's config schema (D26). Verified:
`flutter analyze` clean, `flutter test` 23/23.

**Addendum, 2026-08-01 (CP 5.1 session, D40): two real bugs, only visible once D39's fix made the
Live screen show real data for the first time.** `RunSummary`'s counters panel was merging per-item
`scrape.done` stats (`posts`/`followers`/`following` — one profile's numbers) into the same bucket as
`flow.completed`'s genuine run-level counters (`processed`/`scraped`), last-value-wins — fixed to
only read `flow.completed`. And `LiveController` scoped events to a run with a permissive
`flowRunId == null` fallback (a leftover from before `flow_run_id` injection existed), which let
this session's own diagnostic probe events — and any future orphaned event — leak into every
subsequent run's display forever; fixed by requiring an exact match now that injection is reliable.
`flutter analyze` clean, `flutter test` 23/23 unchanged. Not yet re-verified against a live run.

**Addendum, 2026-08-01 (D41): three more UX fixes, from your live testing against the now-working
data.** All demonstrated against Scrape but checked individually against each of the other four
surfaces rather than applied blindly. (1) The "large latest card" pattern only existed in
`scrape_surface.dart` and `scan_surface.dart` — scan already keyed it off `scan.started` correctly;
scrape kept a subject large even after it resolved, fixed to fall back to the uniform small list the
instant it's `done`/`skipped`. (2) Image cropping was two bugs: `AgentImage`'s default `BoxFit.cover`
lost content on genuinely-approximate aspect ratios (fixed → `BoxFit.contain`, letterboxing instead
of losing content, a no-op for the two surfaces with exact known ratios), and `follow_surface.dart`
had the outright wrong ratio (`1080/2246`, the entity page, instead of `1080/2000`, the actual
scraped-composite shape `follow_queued/` images are). (3) `RunSummary`'s counters now tally live from
per-item events as they stream, dispatched per-flow (`scan` reads the pipeline's own running tally,
`classify`/`follow` count by verdict, `scrape`/`ingest` count specific event kinds) rather than
waiting for `flow.completed`. `flutter analyze` clean, `flutter test` 25/25 — 2 new cases added after
noticing existing fixtures no longer exercised the changed code paths (a real coverage gap, not just
"tests still pass"). Not yet verified against a live run.

**Addendum, 2026-08-01 (D42): the in-progress scrape card's image was still wrong after D41.** It was
still assuming the composite's portrait shape for an image that, while in progress, is only ever the
queued row crop (`1080×198`, same shape as `scanned/`) — fixed by laying the in-progress large card
out as a strip (image on top, details below) instead of forcing a wide image into the portrait Row
every resolved card uses. `scrape.skipped` had the identical bug (never gets a composite either),
fixed the same way. Also added "root: `<entity>`" to both scrape and follow cards — the source entity
a candidate was found under, parsed client-side from the shared `<root>/<user>.jpg` path shape both
flows' images have (new `rootFromImage()` in `surface_common.dart`); not applied to scan/classify/
ingest, whose event/image shapes don't share that same structure. `flutter analyze` clean, `flutter
test` 25/25. Not yet re-verified against a live run.

**Addendum, 2026-08-01 (D43): the Live screen's outer layout, two columns not three.** The fixed
320px `RunSummary` column stretched to fill the window's full height regardless of content, leaving
visible dead space below the device pane while the visualization surface — this screen's actual
point — got squeezed into the middle. Now: a fixed 420px left column holds `RunSummary` sized to its
own content on top (a non-flex `Column` child gets unbounded main-axis space to size itself, verified
empirically rather than assumed) and `LogConsole` in an `Expanded` below taking the rest; the right
side is a single `Expanded` visualization surface picking up both the freed 320px and the old middle
column's share. Verified the specific risk (`SingleChildScrollView` under an unbounded main-axis
constraint, unlike a sliver-based `ListView` which would throw "unbounded height" in the same spot)
by rewriting both `RunSummary` tests to the real constraint shape rather than trusting the old fixed
`height: 700` box was equivalent. `flutter analyze` clean, `flutter test` 25/25. Not yet verified
against a live run / real window.

**Addendum, 2026-08-01 (D44): the wider pane didn't help, since the cards inside it didn't use the
width.** Scrape/follow/classify's card lists are all a single-column `ListView` of `Row`-shaped cards
— each card stretched to the list's full width but its own content didn't, so D43's extra room just
became more empty space, not more visible information. Fixed by capping each card's width and
`Wrap`ping them instead of redesigning the cards — same proven visual design, packed denser. New
`_HistoryWrap` in `scrape_surface.dart`; the same pattern inlined in `follow_surface.dart` (420px
cards) and `classify_surface.dart` (320px). Classify needed one more change: it became a
`StatefulWidget` with `scan_surface.dart`'s own `ScrollController` auto-follow-the-newest pattern
applied verbatim, since the `ListView(reverse: true)` trick that gave it that behavior for free has
no `Wrap` equivalent. `ScanSurface`'s filmstrip and `IngestSurface`'s grid already didn't have this
problem, so left untouched. `flutter analyze` clean, `flutter test` 25/25. Not yet verified against a
live run at the actual (much wider) production width.

**Addendum (D45): the fixed/dynamic direction was backwards on the first attempt, corrected from
your feedback, then tightened again.** First read "give images breathing room" as "images should
grow" and built the log/summary column fixed with images `Expanded` — backwards; you'd meant
breathing room for *logs*, since images already wrap to fill whatever width they get (D44). Swapped
which side is fixed. Picked the fixed image width carefully rather than guessing: the app enforces a
1024×700 minimum window (`main.dart`), and a width fitting two D44 cards (820px) would've squeezed
the log column to ~204px at that floor, so chose 600px instead — then tightened further to exactly
420px (one scrape card + padding + scrollbar allowance, no leftover) once even 600px still showed
visible slack in your next screenshot. Flagged as scrape-specific in code, since follow's cards
(420px) wouldn't fit this tightly — revisit once that flow gets tested. Also reorganized
`RunSummary` into two capped-width blocks in this round (later superseded by D46) — caught a real
bug doing it: capping the details block to 320px made the "many counters" stress test overflow a
700px test height by 10px (the same six chips wrapped into more rows in less width), fixed by
widening to 380px. `flutter analyze` clean, `flutter test` 25/25 each round.

**Addendum (D46), session close-out: three more corrections, Device control compacted into the
header.** Moved out of `RunSummary`'s body into a compact `DeviceBar` sharing the header row with
the flow chips — dropped the status icon, explanatory sentence, and card styling per your ask, kept
just a phone icon, a name, and a `Start`/`Stop` button. `RunSummary` reverts to a plain single column
now that D45's two-block `Wrap` (built specifically to give Device somewhere to sit) has nothing left
to pair with. The name shown is now the device model ("I2201"), not the 15-digit serial — new
`_device_model()` in `ia_agent/api/device.py` reuses `services/selftest.py`'s own `adbutils` lookup,
best-effort, falling back to the serial on any failure. Caught by you, not assumed: the running agent
initially still showed the serial because it hadn't been restarted to pick up the new `/api/device`
field — confirmed via `curl` both before (field absent) and after (`"model":"I2201"`) restarting it,
services still `adopted` with uptime intact. Also removed the left border D30 put on scheduler-merged
log lines — a real distinction (scheduler trigger/gate log vs. the flow's own execution log) that
read as inconsistent alignment rather than useful signal; kept a dimmer text color as a subtler cue
instead of dropping the distinction outright. `flutter analyze` clean, `flutter test` 26/26 (one new
`DeviceBar` case — a long model name in the header's own tighter row). Session closes here.

**CP 4.5 (Device view) done and user-verified, 🟢.** Two design forks were checked before writing
any code rather than guessed: the plan's "position with `my_modules.win32.snap_window`" assumes a
fixed window title, but scrcpy's title varies by phone model and `my_modules`/wsl-bridge are marked
"no changes expected" — **chosen: find the window by PID instead** (wsl-bridge's `/scrcpy/start`
already returns it, exact, no cooperation needed from either repo). The plan's secondary opt-in
phone-glance stream has no consumer until Phase 6 (mobile pairing) exists — **chosen: desktop-only
this checkpoint**, deferring `device.mirror` broadcast plumbing until something can actually use it.
New `ia_agent/integrations/wsl_bridge.py` (thin client, wsl-bridge itself untouched),
`ia_agent/window.py` (`find_window_by_pid`/`snap_to_known_position` via raw `ctypes`, same approach
`my_modules.win32.snap_window` uses, just PID- not title-keyed), and `ia_agent/api/device.py` —
`GET /api/device`, `POST /api/device/scrcpy/{start|stop}` (refuses to cycle an already-running
mirror, matching `test_wsl_bridge()`'s existing "don't be rude" precedent; retries the snap for up
to 5s since the window doesn't exist the instant the process does, and a snap that never lands still
reports the start as successful). `snap_to_known_position` only re-asserts scrcpy's own requested
launch position, reading the window's current size first so it can never distort the video — purely
defensive against a compositor ignoring the launch hint. Flutter: `core/device_models.dart` +
`features/live/device_pane.dart` replace CP 4.4's placeholder — a lightweight 5s poll keeps it
current (no WS channel exists for device state yet), and it explains itself when there's nothing to
show rather than presenting dead controls. The video is never rendered inside the app — it's a real,
separate OS window; the pane only starts/stops/reports on it.

**Verified:** `agent/tests/test_device.py` (16/16, monkeypatched wsl-bridge/window). The
window-finding mechanism was verified against a real process on this machine — a first attempt using
a spawned Notepad failed (`find_window_by_pid` found nothing), turned out to be Windows 11's own
Notepad being a packaged app where the launched pid isn't the window-owning one (D11's pattern,
again, just a target this project hadn't characterized yet). Switched to the machine's actual
already-running `scrcpy.exe` (found via `psutil`, read-only — nothing started, stopped, or moved)
and confirmed the real window is found correctly, in new `agent/tests/check_device.py`. `flutter
analyze` clean, `flutter test` 23/23 unchanged.

**CP 5.1 (Library API) done, agent-only, 🟢.** New `ia_agent/library/folders.py`'s static `FOLDERS`
registry names the seven ARCHITECTURE §1.1 stage directories (`entities` flat — `<id>.jpg` files
directly under it; `scanned`/`gender_valid`/`gender_invalid`/`scrape_queued`/`scraped`/
`follow_queued` one subdirectory per entity root) and `resolve(path)` maps an absolute path back to
`(folder, root)`, doubling as the path-traversal guard for the two new image routes below.
`library/counts.py`'s `LibraryCounts` seeds once at startup (`os.scandir` per folder plus per root —
~120 calls today, not a per-file walk; measured **15 ms** against the real `IA_DIR`'s 7,655 files in
new `agent/tests/check_library.py`) and `touch(folder, root)` **recomputes** exactly the pair a
filesystem change touched rather than tracking a running delta, so a coalesced or dropped watcher
event can never leave a count wrong — see D35. A root that recomputes to 0 files is dropped rather
than shown empty. New `library/watcher.py`'s `watch_library` passes the seven folders directly to
`watchfiles.awatch(..., recursive=True)` — the deliberate opposite of `config/watcher.py`'s
non-recursive top-level-only watch, and for the mirror-image reason: this one needs exactly the
churn that watcher exists to dodge, while still never watching `.thumbs` (the mobile app's own
thumbnail cache) or `.Trash-0` (send2trash's trash, relevant again from CP 5.2), since only the
known seven paths are ever passed to `awatch`. New REST — `GET /api/library/folders` ·
`GET /api/library/entities?folder=` · `GET /api/library/images?folder=&entity=&offset=&limit=` ·
`GET /api/library/image?path=` · `GET /api/library/image/thumb?path=&w=` — the last two reusing CP
4.2's content-addressed `images.cache`/`thumbnail` unchanged, keyed by path at request time (a
virtualized grid only ever renders visible cells, so hashing every listed file up front would be
wasted work) rather than eagerly, and new WS channel `library.changes`. Verified:
`agent/tests/test_library.py` (32/32 — folder resolution and traversal rejection, seed/touch
counting for flat and per-root folders, a drained root dropping out of `entities()`, full REST round
trip, a real file write reaching a `library.changes` WS subscriber) plus `check_library.py` against
the real `IA_DIR`. All eight prior suites unchanged (71/71, 32/32, 49/49, 26/26, 20/20, 24/24, 36/36,
35/35, 16/16). Also verified against the real running agent — restarted to pick up the new code
(same "the code changed, the running process didn't" step CP 4.4 needed; the launcher brought it
back in ~8s per D21, and the three supervised services stayed `adopted` with uptime intact across
the restart) — then every new endpoint hit against the real `IA_DIR`'s real 7,655 files, plus a live
WS connection confirming the channel is reachable. Nothing to test in the GUI yet — CP 5.3 is what
puts this on screen.

**CP 5.2 (Mutations) done, agent-only, 🟢.** New `ia_agent/library/ops.py` — `apply(folder, entity,
selected)` promotes the selected filenames into that folder's configured move target and
`send2trash`s everything else currently in that `(folder, entity)` directory (read fresh from disk
at call time, not trusted from the caller — the same race CP 4.2's image cache exists to dodge
elsewhere); `delete(paths)` trashes an explicit list of `IA_DIR`-relative paths regardless of
folder/entity. Both mirror the pipeline's own `insta_automate.utils.move`/`rm_empty_subdirs` — real
promotions use `shutil.move`, everything discarded goes through `send2trash` — checked against
`ia_manager` (the mobile app) first and deliberately **not** matched to it: the mobile app
hard-deletes the unselected half with no recovery. New `ia_agent/library/settings.py` persists the
per-folder move-target mapping machine-local (`%LOCALAPPDATA%\ia-agent\library.json`, same D12
reasoning as service self-heal/autostart), seeded with the two real ARCHITECTURE §1.1 promotions
(`gender_valid → scrape_queued`, `scraped → follow_queued`) rather than the mobile app's
identity-everywhere default — every other folder still defaults to itself, where "apply" is just
"keep the selection, discard the rest," a real action with no promotion. New REST: `GET/PATCH
/api/library/move-targets[/{folder}]`, `POST /api/library/apply`, `POST /api/library/delete`, and on
`api/queue.py` — `POST /api/queue/add` (rejects a missing `entities/<id>.jpg`, mirroring
`Queue.add()`), `POST /api/queue/remove` (mirrors `Queue.remove()`'s `check=True`: refuses while the
entity still has jpegs pending in either stage directory unless `force: true`), `POST
/api/queue/reorder` (rejects anything that isn't exactly a permutation of the currently queued
names). `config.env`'s write lock moved from `api/config.py`'s own `asyncio.Lock()` into a shared
`config/env_file.py::WRITE_LOCK`, since CP 5.2 is the first time two different routers
(`api/config.py`'s `PATCH`, `api/queue.py`'s new mutations) read-modify-write the same file — a
per-module lock would only have serialized writers within one module. See D47 for the full
reasoning on all four decisions above.

**Verified:** `agent/tests/test_library.py` grew from CP 5.1's 32 checks to 65 (settings
defaults/persistence/validation; `apply()`/`delete()` at the unit level against a scratch tree —
identity-mapped cull, a real cross-folder promotion preserving `<root>/<name>` exactly, rejecting an
absent selection before touching any file, an explicit-path delete, rejecting paths outside the
seven folders — then the same coverage again over the live REST surface). New
`agent/tests/test_queue.py` (14/14, no prior coverage existed for `queue.py` at all) covers
`GET /api/queue` plus add/remove/reorder end to end, including the pending-jpeg refusal and forced
override, a rejected path-shaped entity name, and confirming `config.env`'s comments and unrelated
keys survive every mutation untouched. All eight prior suites unchanged (71/71, 32/32, 26/26, 49/49,
24/24, 20/20, 36/36, 35/35, 16/16). Also verified against the real running agent — restarted to pick
up the new code (same step every checkpoint since CP 4.4 has needed; the three supervised services
stayed up with uptime intact across it) — `GET /api/library/move-targets` and `GET /api/queue` hit
against the real `IA_DIR`/`config.env` (7,007 real `scrape_queued` files across 110 entities).
**Deliberately not exercised live:** `apply`/`delete`/`add`/`remove` were never called against the
real pipeline data this session — those are real, only-partially-reversible actions on the user's
actual curation backlog that nothing asked for; the scratch-tree test suites stand in for that,
matching CP 4.2/4.3's own precedent of never mutating the real `IA_DIR` from a verification pass.
Nothing to test in the GUI yet — CP 5.3 is what puts this on screen.

**CP 5.3 (Library UI) done, user-verified, 🟢.** The Library nav destination (a placeholder since CP
0.3) is now `app/lib/features/library/`: a `FolderRail` (the seven stage folders with live counts) +
`EntityList` (search-filterable roots inside whichever non-flat folder is selected) + a
`LibraryGrid`/`LibraryToolbar` pane, exercising every CP 5.1/5.2 endpoint for the first time. The
grid uses `SliverGridDelegateWithFixedCrossAxisCount`, not `SliverGridDelegateWithMaxCrossAxisExtent`
— deliberately, since keyboard navigation needs an exact column count to turn Up/Down into "move by
one row." Pages of up to 200 load as the user scrolls (folders here run to thousands of files, per
ARCHITECTURE §1.1); `ctrl+A` pages in whatever's left first, so "select all" really means all. New
`core/instagram_url.dart` ports `Insta.url()`'s `reel-`/`post-`/account resolution rule — checked
against both the pipeline's `controllers/instagram.py` and the mobile app's own `instagram_url.dart`
before writing it, so all three agree — and `core/library_image.dart` is `agent_image.dart`'s sibling
for path-addressed thumbnails, reusing `BoxFit.contain` per D41's letterboxing lesson. Apply/Delete
both confirm with a dialog naming exactly what happens, matching `flow_switch_confirm.dart`'s
established rule; a per-folder move-target picker sits next to Apply, backed by CP 5.2's
`GET/PATCH /api/library/move-targets`.

**Corrected from your live testing, same session (D48).** The first version needed Ctrl+click to add
to a selection and let a plain arrow key collapse the selection down to just the newly-focused item
— both wrong, per your own framing: a plain click or Space should always *toggle*, building a batch
by clicking or arrow-then-spacing through several images one at a time, and a plain arrow should only
move focus, never touch selection. Fixed by making focus and selection genuinely independent
operations (`moveFocus()` vs `toggle()`) instead of one derived from the other — `selectOnly()` is
gone entirely. Shift+click/Shift+arrow range-select was correct from the first version and untouched.
Confirmed working on your retest ("Thats better"). See [[feedback-multiselect-toggle]] in memory for
the durable rule this sets for any future multi-select surface in this app.

**Verified:** `flutter analyze` clean, `flutter test` 32/32 (26 prior + 6 new in
`library_layout_test.dart`, which caught a real `RenderFlex` overflow in the toolbar at the app's
1024px floor before you ever saw it — the single action row was split into a breadcrumb row plus a
`Wrap` for the button cluster, which degrades to more rows instead of overflowing at any width).
Built and started for you per D19/rule 5 — you confirmed the corrected selection mechanics live;
Apply/Delete against real data and a real-window resize check weren't separately confirmed back in
this session.

**CP 5.4 (Entity view) done, user-verified, 🟢.** New `ia_agent/library/entity_view.py`'s `fetch(root,
counts, engine=...)` queries Postgres directly (`entity`/`scanned`/`user` tables, read-only) for
scanned → private → female (male shown alongside, not counted forward) → scraped per entity root, on
new `GET /api/library/entity/{root}/yield`. `postgres.py`'s engine getter made public (`get_engine()`,
was `_get_engine()`) as the module's second real consumer, pool bumped 1→2 accordingly.
`LibraryCounts` gained `count_for(folder, root)` for a direct per-root lookup outside its `entities()`
list shape. **"Followed" has no per-entity DB source at all** — `entity_follow` unlinks the image on
every terminal verdict without ever writing a row — so it's approximated as
`scraped − still in scraped/ − still in follow_queued/` using the same live folder counts CP 5.1
already tracks, clamped at 0. Flutter: `core/entity_yield_models.dart` + a new
`features/library/entity_yield_dialog.dart`, opened from a new icon button on `LibraryToolbar`'s
breadcrumb row whenever an entity is selected (the drill-in entry point, not a new nav destination —
Overview/Insights stay reserved for later phases). The funnel is five proportional-width bars, one
hue throughout (magnitude carried by length, not lightness — there's one metric across stages here,
not several series needing color to distinguish them), with the "Followed (est.)" bar captioned to
say plainly that it's an approximation.

**Verified:** `agent/tests/test_entity_view.py` (16/16 — a scratch SQLite engine standing in for
Postgres via `StaticPool` so `asyncio.to_thread`'s worker thread sees the same fixture tables the
main thread wrote, `LibraryCounts` seeded from a scratch `IA_DIR`, the full funnel math, an unknown
root returning `None` not raising, `followed_est` clamped at 0 even against an inconsistent fixture,
then the same coverage again over live REST including the 404 path) plus all nine prior suites
unchanged (71/71, 49/49, 26/26, 32/32, 16/16, 35/35, 36/36, 65/65, 14/14, 24/24, 20/20 — the full
current set). Also verified against the real running agent (restarted to pick up the new code, same
step every checkpoint since CP 4.4 has needed; all three supervised services confirmed still running
across it) — hit against the real Postgres/`IA_DIR` (`sejjjalll`: 2529 scanned → 1544 private → 1044
female, 500 male → 365 scraped → 365 followed_est, nothing left in either queue folder for that root)
and a real unknown-root 404. `flutter analyze` clean, `flutter test` 34/34 (32 prior + 2 new in
`entity_yield_layout_test.dart` — a 60-char root with six-figure counts, and an all-zero funnel).

**Real per-entity follow tracking was scoped and deliberately not built — see D49.** A genuine fix
exists (a small Postgres table written alongside `profile_follow`'s existing `follow.result` `emit()`
calls, riding `entity_follow`'s already-scheduled `db_backup()` → Telegram channel for free) but it is
a cross-repo `Insta-Automate` change, and you judged "followed" a metric you may not use enough to
justify it. The approximation ships as the permanent answer unless that changes.

**Phase 5 accepted 2026-08-01** — CP 5.4 was the last item PLAN.md scoped for this phase, and you
accepted the phase outright straight after reviewing the "followed" approximation tradeoff above,
the same way Phase 2 was accepted without a separate final verification pass.

**Phase 6 (Mobile pairing & notification rework) is open, CP 6.1 (Pairing + notification core)
done, agent-only, 🟢.** Before writing code, Q6/Q7/Q8 were answered (D52): the device mirror stays
desktop-only (no `device.mirror` stream this phase — the consumer, mobile pairing, comes before
the producer, same call CP 4.5 already made for the desktop side); the future Add Entity action
will post to the Telegram entity channel, not the DB, since the existing `NewMessage` handler
already fires ingest instantly on a channel post; and all four candidate notification categories
(limit-reached, new entities classified/scraped, scan-complete/unfollow-prompt, failures) are in
scope, with `NOTIFY_POLICY` and per-tag mute (CP 6.2/6.3) as the actual filters rather than a
smaller taxonomy baked in now. New `ia_agent/pairing.py`'s `PairingStore`: `start()` mints a
6-digit, 120s-TTL, single-use code plus the LAN host/port for the QR payload; `claim()` is the one
endpoint left outside `auth.py`'s bearer check entirely (the phone has no token yet by
construction); devices persist to `%LOCALAPPDATA%\ia-agent\pairing.json` (D12's machine-local
precedent), never listing the token itself. New `ia_agent/notifications.py`'s `NotificationStore`
persists its full history to disk on every mutation — deliberately unlike `events/store.py`'s
memory-only ring (CP 4.2), since an unread "FOLLOW limit reached" is exactly the state a restart
must not drop (D50) — and dedupe replaces a same-key entry only while it's unread, preserving
`tl.bot.notify_transient`'s existing search-and-replace semantics (ARCHITECTURE §6). New REST:
`POST /api/pair/{start|claim}` · `GET /api/pair/devices` · `DELETE /api/pair/devices/{id}` ·
`POST /api/notify` (`{delivered, targets}`, `targets` = live WS subscriber count, the closest
answer the bus's broadcast-to-everyone model can give until per-channel subscription tracking
exists) · `GET /api/notify[?since=&unread_only=]` · `POST /api/notify/{id}/read` ·
`POST /api/notify/read-all`. New WS channel `notifications`. `auth.py`/`api/ws.py` now accept
either the desktop token or any live device token everywhere.

**Found by the pairing test's own first run, not designed in up front (D51):** a device token
could list and revoke *other* paired phones and mint new pairing codes — real overreach for a
phone that has no business touching siblings it didn't pair. Fixed with a route-level
desktop-only check on `/api/pair/start`, `GET /api/pair/devices`, and
`DELETE /api/pair/devices/{id}` specifically, layered on top of the broader middleware check
rather than replacing it.

**Verified:** new `agent/tests/test_pairing.py` (29/29) and `agent/tests/test_notifications.py`
(30/30) — code TTL/single-use/persistence, a device token authenticating like a real bearer token
except where scoped out, dedupe-while-unread, `since=`/`unread_only=` filtering, mark-read
semantics, and a real WS delivery on each new channel. All eleven prior suites unchanged (71/71,
49/49, 65/65, 36/36, 35/35, 32/32, 26/26, 24/24, 20/20, 16/16, 14/14). Also verified against the
real running agent — restarted to pick up the new code (same step every checkpoint since CP 4.4
has needed; all three supervised services confirmed on identical pids across it) — a real pairing
round trip (start → claim with no bearer → device token working → revoke) and a real notify round
trip (post → list → mark read), leaving one read, `test`-tagged notification in the now-real
`notifications.json` as the only trace. **No UI yet** — CP 6.3 is what puts this on screen; CP 6.2
(cross-repo `Insta-Automate` notifier facade) is what makes the pipeline actually call
`POST /api/notify` for real.

**CP 6.2 (Notifier facade) done, cross-repo, `Insta-Automate` on `feat/control-center`, 🟡.** New
`controllers/notify.py`'s `notify()` matches ARCHITECTURE §6's signature exactly; `AgentClient
.notify` already existed from CP 3.3, so this checkpoint is purely the `NOTIFY_POLICY` policy
layer (`telegram_only`/`app_first`/`both`, already in `Config._DEFAULTS` since CP 3.1) plus the
Telegram fallback every call site used to hand-roll. All seven call sites converted:
`tasks/telegram.py`'s four notify functions (the old `notify_transient` helper is gone, folded
into the facade's dedupe handling), `tasks/device.py::wait_for_device`, `tasks/ia.py
::add_new_entity`/`::profile_follow`, and the scrape/follow limit-reached messages.

**Two real edge cases surfaced while wiring this in, both recorded rather than glossed over
(D53).** `notify_profile_unfollow`'s image is a live `ui.profile_header.screenshot()` buffer, not
an `IA_DIR` file like every other image this project passes around — the agent notification
carries no image for that one message (no bytes-upload path exists), but Telegram still shows the
real screenshot regardless of policy, since it receives the original object untouched. And CP
6.1's `delivered` counts any live WS connection, not a client actually watching notifications
(nothing renders the `notifications` channel yet) — a real risk that `app_first` would silently
swallow every notification whenever the desktop app happens to be open, once this branch is ever
deployed. Not fixed now: this branch stays undeployed until the whole control center is accepted
(rule 3), and CP 6.3 will exist well before that point — flagged so whoever revisits
`NOTIFY_POLICY`'s default checks CP 6.3 landed first.

**Verified without touching the real Telegram channel or the real running agent.**
`Insta-Automate` has no test suite (same precedent as CP 3.1/3.2/4.3) — an import sanity-check
across every changed module plus the full `IaFlows` registry, and a throwaway script (18/18)
exercising the facade's policy branching, dedupe search-and-delete, and the `Path`-vs-buffer image
split against `AgentClient.notify`/`IaTelegram.get_client` monkeypatched to recording fakes.
`AgentClient.notify` itself was already proven end to end against a real agent in CP 3.3/CP 6.1.
Nothing deployed to the live pod — same standing precedent as every `Insta-Automate` checkpoint
since CP 4.3.

**CP 6.3 (Desktop pairing & notification center) groundwork: placement decided (D54).** ARCHITECTURE
§9's seven nav destinations have no slot for either piece, and §9's original plan to put the
notification feed inside Overview is blocked on Overview itself, never built past its CP 0.3
placeholder. Checked with you before writing any code, same as CP 4.5/CP 5.4's design forks: pairing
(QR, paired-device list, revoke) becomes a new "Devices" tab in Settings alongside Flows/Limits/
Queue; the notification center becomes a bell icon in the title bar, reachable from every screen.
Neither gets a new nav destination.

**2026-08-02 live incident: `entity-follow` frozen at `phase="running"` for hours, zero flow runs
triggered despite 191 real files queued (D55, full chain in DECISIONS.md).** Root cause:
`wait_for_device()` (`tasks/device.py`) had no exception handling, so a transient adb connection
refusal killed `entity_follow_trigger()`'s `asyncio.create_task()` permanently and silently — the
frozen phase was just the last state written before the task died. Fixed at the source
(`wait_for_device` now treats a raised exception the same as "not connected yet") plus defense in
depth (all five trigger loops and `keep_telegram_alive` now wrapped in try/except, retrying after
one `TICK` instead of dying forever). Chasing why adb kept refusing connections surfaced four more
real bugs, chained: the host's external (non-agent) adb process was bound to `127.0.0.1` only —
unreachable from any pod — because scrcpy's bundled adb.exe (version-mismatched vs the one
actually running the server) kills and restarts the server on every launch, and
`device.start_scrcpy()` fires on every successful device check; fixed with `my_modules.scrcpy`
now pinning `--adb=` to the canonical binary (branch `fix/scrcpy-adb-version-pin` in `my-modules`,
hotfixed live into `wsl-bridge`'s venv pending a real release). Deploying the scheduler fix hit the
same churn mid-restart and produced a genuine `CrashLoopBackOff` (`serve()`'s own unguarded
`wait_for_device()` call) — also taught that `ia build` reuses the same image tag every time, so
`kubectl rollout undo` does **not** actually restore old code once a new build has overwritten that
tag locally. Once recovered, the first real flow run crashed on `ModuleNotFoundError:
insta_automate.controllers.notify` — the worker pod predated CP 6.2 entirely (deliberately never
redeployed per its own checkpoint notes) — restarted with your explicit approval, which re-hit
D38's known work-pool-orphaning init container, fixed the documented way (`ia prefect deploy`).
That command run from a bare local shell turned out to silently deploy from `main` instead of
`feat/control-center` (`GIT_BRANCH` unset locally, unlike the pod), regressing `entity-follow`'s
deployment schema and dropping its `force` parameter — fixed by setting `GIT_BRANCH` explicitly
for the command. **Verified end-to-end for real:** a `force_run` via the agent's REST API (not the
GUI) completed in 92.4s, matching historical successful-run durations; adb held `0.0.0.0`-bound and
`origin: supervised` for the rest of the session. All other four flows confirmed still gating
correctly after every restart. Not yet watched over a long unattended window — see D55 for what's
still a hotfix rather than a real fix (the scrcpy pin) and what's now live earlier than planned (CP
6.2 on the worker).

**CP 6.3 (Desktop pairing & notification center) built on D54's placement, 🟢, awaiting your
test (D56).** No agent-side changes were needed — CP 6.1 already shipped the full REST/WS surface
this checkpoint is purely a Flutter client for. New
`app/lib/features/settings/devices_controller.dart` + `devices_tab.dart` (the "Devices" Settings
tab): a QR/6-digit-code pairing card (`qr_flutter`, payload exactly
`iacc://pair?h=<lan-ip>&p=8787&c=<code>` per ARCHITECTURE §7) that mints a code, counts down its
120s TTL, polls for a claim every 2s (no WS channel exists for pairing — a claim happens on the
phone, so the desktop has nothing to subscribe to), and a paired-device list with last-seen and a
confirm-then-revoke action. New `app/lib/features/notifications/notification_controller.dart` +
`notification_center.dart`: a title-bar bell (unread badge) opening a
`CompositedTransformFollower`-anchored panel — replay-then-subscribe over `GET /api/notify` +
the `notifications` WS channel (D18's established shape), mark-read/mark-all-read, and per-tag
mute persisted client-side via `shared_preferences` (there's no server-side "muted" concept —
`NOTIFY_POLICY` already governs desktop-vs-Telegram routing, this is purely "don't show me this
category").

**Found by the new `notification_center_layout_test.dart`, not `flutter analyze` (D19's
precedent again):** the panel header (title + filter icon + "Mark all read") overflowed by a
consistent 101px regardless of window size or content — fixed by giving the title `Expanded` +
ellipsis instead of a `Spacer()`, so it always yields space to the fixed-size trailing controls.
See D56 for the full account, including a benign `flutter_test` hit-test-warning quirk with
`CompositedTransformFollower` that two tests in the new suite deliberately suppress with
`warnIfMissed: false` (verified not to be masking a real mis-tap).

**Verified:** `flutter analyze` clean, `flutter test` 38/38 (26 prior + 12 new across
`devices_layout_test.dart`/`notification_center_layout_test.dart`), `flutter build windows
--debug` succeeds. Committed. **Testing is real but partial, by design, not an oversight**: the
pairing round trip and the notification bell/panel were confirmed against the real running agent
with the phone side backend-mocked (`curl` playing the part of `/api/pair/claim`), since CP 6.4 —
the actual mobile client — doesn't exist yet. This checkpoint cannot be called fully tested until
CP 6.4 exists and a real phone completes the QR scan → claim → live notification path end to end.

**CP 6.4 (Mobile client) is next — ground rules confirmed with you 2026-08-02, before writing any
code (D57).** It lands in `flutter/Insta-Automate-Client` (pubspec `ia_manager`), **feature branch
only** (`feat/lan-agent`, per rule 3 — never `main`). After each change, build the real APK and
install it on the phone currently connected over adb for testing. If anything needs a human
action (accepting an install prompt, granting a permission, scanning a QR), stop and ask rather
than trying to script around it. **The adb-connected test phone is not the production phone**: its
`IA_DIR` is stale and has no active Syncthing sync to this laptop — it exists purely for
installing/exercising the app, not for seeing real pipeline images or curation state. The user's
own separate phone is the one with real `IA_DIR` sync; that phone is not what CP 6.4 gets tested
against. Keep this distinction in mind when judging whether a test result ("no images show up")
reflects an app bug or just the test device's stale data.

**CP 6.4 (Mobile client) built across all four planned slices, 🟢, each verified against the real
agent and a real phone before moving to the next.** New `ia_manager` code (`feat/lan-agent`): a
`Desktop Pairing` section in Settings (`widgets/pairing_card.dart` — QR scan via `mobile_scanner`
plus a manual host/port/code fallback, `services/agent_provider.dart` persisting the claimed
device token via `shared_preferences`, same trust model as the desktop's own unencrypted token
file); a `flutter_foreground_task`-backed background service
(`services/notification_service.dart`) holding a `services/agent_ws.dart` connection open so
`flutter_local_notifications` can show a real push within about a second, image included, even
backgrounded; a compact read-only `widgets/live_flow_strip.dart` on the home screen (phase per
flow, no controls — editing stays the desktop's job); and `screens/queue_screen.dart`'s one Save
button now tries `PATCH /api/config` through the agent first when paired (falling back to the
existing local `config.env` write only on a genuine connectivity failure, never on a validation
rejection — that's surfaced as an error instead, so a local write can't bypass a rule the agent is
correctly enforcing). `android/app/build.gradle` needed `coreLibraryDesugaringEnabled` for
`flutter_local_notifications`; the manifest gained `usesCleartextTraffic` (the agent is plain
`http://`, deliberately, LAN-only) plus camera/notification/foreground-service permissions. One
real bug caught mid-build, not by `flutter analyze`: the live flow strip overflowed its own row by
2px (D19's precedent again) — fixed by loosening the fixed height. No agent-side changes were
needed for any of this — CP 6.1 already shipped the full REST/WS surface.

**Then extended same-day with a notification-routing redesign (D58), found by actually using
CP 6.4 rather than scoped in advance.** Three real gaps: raw markdown showing as literal text
(messages are built for Telegram's renderer, not the agent's own display); `NOTIFY_POLICY
=app_first`'s `delivered` counting the desktop's own WS connection, not just a phone's — D53's
flagged-and-deferred risk, now a real bug with a phone client actually in the picture; and three
notifications (unfollow-prompt, followed-by, already-known-entity) being about one specific
profile rather than a flow event, needing to always reach Telegram and be tappable to open that
profile. Fixed across all four repos: the agent's `EventBus` (`agent/src/ia_agent/events/bus.py`)
now tags every WS subscriber with the device id that authenticated it, so `targets`/`delivered`
means "a phone got it," never "the desktop happens to be open" — the desktop still receives every
broadcast regardless, just never gates the decision; `GET /api/pair/devices` gained a live
`connected` bool riding the same plumbing. The pipeline's `notify()` (`Insta-Automate`,
`feat/control-center`) gained `url` (the entity's Instagram URL, already in scope at all three
call sites) and `always_telegram` (forces Telegram regardless of phone connectivity, independent
of `NOTIFY_POLICY`). Both Flutter clients got a small hand-rolled markdown-to-plain/rich-text
formatter (no new dependency, matching this app's existing preference — `core/notification_text.dart`
on each side) and tap-to-open wired to the `url` field rather than an inline clickable link, which
would be unreliable to hit inside a truncated, ellipsized message.

**Two corrections from your live desktop testing, same session.** The first version bolded the
stripped text (a real `**bold**` → styled `TextSpan`) — you found plain text reads better, so
desktop's formatter was simplified to exactly match mobile's already-plain approach (same
function shape, bold machinery dropped entirely). And the "followed by" name needed a leading `@`
for visual consistency with the linked profile above it, even though it's not a link itself —
fixed at the pipeline source (`tasks/ia.py`), not the client formatters, since it's message
content: a regex inserts `@` right after Instagram's own `"Followed by "` UI text.

**Verified:** agent — `agent/tests/test_notifications.py` 37/37, `test_pairing.py` 31/31, full
13-suite regression green (698 checks). One real slip caught immediately: the notifications test's
new pairing calls didn't scratch-redirect `PAIRING_DEVICES_PATH` like `test_pairing.py` already
does, briefly writing a fake device into the *real* `pairing.json` — caught, fixed, real file
cleaned up by hand before it could confuse a future session. Live-checked against the real agent
and your actually-connected phone: `connected` true only while its socket was actually open,
`delivered: true` only with it connected. Pipeline — import sanity check plus a throwaway script
(8/8) covering all four device-active/inactive × general/`always_telegram` combinations against a
monkeypatched `AgentClient`/`IaTelegram`. Desktop — `flutter analyze` clean, `flutter test` 39/39;
built and started for you, confirmed live twice (once prompting the two corrections above, once
after). Mobile — `flutter analyze` clean, built, installed on the real test phone, and a real
per-profile-shaped notification (markdown + `url` set) confirmed by you to arrive clean and work
end to end.

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
