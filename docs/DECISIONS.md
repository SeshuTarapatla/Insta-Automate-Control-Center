# Decision log

Newest first. Each entry records what was chosen, what was rejected, and why — so a future
session can tell a settled question from an open one.

---

## 2026-08-02 (continued) — Live retesting of D60–D65 found four more real issues, one a production incident

The same session kept going once you started actually exercising the D60–D65 fixes end to end —
each round of testing surfaced something the first pass hadn't, including one bug (D68) that
required uninstalling the live Helm release to stop.

### D69 · Window position needed a real unit conversion, not just a hardcoded offset; plus a Stop button, a real auto-follow bug, and one design revert

**Window position, round two.** D67's first attempt positioned the app next to scrcpy using
scrcpy's own launch geometry (`--window-x=1`, width derived from the phone's aspect ratio at
`--window-height=1480`) fed directly into `windowManager.setPosition`. Still a visible gap after
rebuilding — root cause: those figures are scrcpy's *physical* pixels (a native SDL app), while
`window_manager`/`screen_retriever` both work in Flutter's *logical* pixels. On this machine's
150%-scaled display that's a real ~1.5x error, confirmed by back-calculating the actual on-screen
pixel positions from a screenshot (predicted physical x≈1020 for a logical x=680 target, observed
≈1039 — matching the scale factor almost exactly). Fixed by dividing by `Display.scaleFactor`
(queried live via `screen_retriever`, itself confirmed to genuinely compute this via
`FlutterDesktopGetDpiForMonitor`, not a stub). A further few-pixel residual (likely DWM's own
invisible border/shadow around a borderless window) was tuned by hand against the real screen
rather than reasoned about further — landed at `-5` logical px, adjusted directly by you after
`-2` still showed a hair of a gap.

**Window sizing was a second, separate bug**, found on the very next screenshot: the app was
still leaving the whole right edge of the screen unused. Cause: `main.dart` restored a previous
manual resize's *size* even though position was already being freshly computed — an old saved
width (from before scrcpy was ever part of the picture) simply wasn't wide enough to reach the
screen's edge. Given the ask ("make sure this space is actually taken by our app when it starts")
is explicitly about *every* launch behaving identically, the whole `WindowGeometry`
save/restore mechanism was removed rather than partially preserved — a persisted preference
that's designed to always be overridden by a fresh computation isn't worth the complexity of
keeping around half-used. `core/window_geometry.dart` deleted.

**A third bug, found by you clicking "Classify" several times while Scrape was actively
running and seeing nothing happen:** `LivePage`'s postFrameCallback (a one-time "catch up on
data that arrived before this page mounted" nudge) was actually re-firing on *every* rebuild —
including the rebuild caused by the manual click itself, since `selectedFlowProvider` is one of
`LivePage`'s own `ref.watch`ed dependencies. Each click's own rebuild immediately re-ran
`_maybeAutoSelect`, saw Scrape still running, and silently re-selected it back within the same
frame — a real bug, not the "auto-follow overrides a stale click" behavior chosen in D67, since
here the override was firing off the click's *own* rebuild rather than any genuine new scheduler
data. Fixed with a `_didInitialCatchUp` flag so the postFrameCallback only ever fires once; all
subsequent auto-follow behavior now comes exclusively from `ref.listen`'s reaction to *real*
`flows.state` broadcasts, which still correctly overrides a manual click the moment something
actually changes.

**A fourth item was a design revert, not a bug:** the Scan surface's newest-at-top,
no-scroll-needed ordering (D67) had been copied onto Classify too, unintentionally — you'd only
asked for the "one entry per row, no wasted space" layout change there, not the ordering change.
Classify reverted to its original oldest-at-top / auto-scroll-to-the-newest-at-the-bottom pattern,
keeping D67's layout fix (full-width image, caption below).

**New feature: a Stop button**, requested directly out of the D68 incident below — there was
genuinely no way to halt a run already in progress from the control center short of uninstalling
the whole Helm release. New `prefect.cancel_flow_run()` (agent) sets a flow run to `CANCELLING`
via Prefect's REST API — the same transition the Prefect UI's own Cancel button triggers — exposed
as `POST /api/flow-runs/{id}/cancel`. `forceRunFlow`'s confirmation-dialog pattern was extracted
into a new shared `core/force_run.dart` (deduplicating what used to be a private copy inside
`FlowCard`) alongside a new `stopFlowRun`, and both now appear on the Flows screen's cards and the
Live screen's header, visible only while that flow's `phase == 'running'`.

**Verified:** `flutter analyze` clean, `flutter test` 39/39 across every round in this section. Agent:
all 13 suites green (475 checks) after the new cancel endpoint; `test_flowruns.py` unaffected.
Built and started for you between every round, live-retested by you each time — the window
position/sizing, the Classify-click bug, and the Stop button were all confirmed fixed live in this
same session.

### D68 · A same-session regression: the disabled-profile guard (D64) was silently skipping every real profile, PRIVATE or PUBLIC — a real production incident

**What happened:** once D64/D66/D67's Insta-Automate changes were redeployed and you resumed
testing for real, every single profile `entity_scrape` touched was logged and skipped as
`"UNAVAILABLE"` — including profiles you could see, live on the mirrored phone, rendering
completely normally (a real, existing, PRIVATE Instagram profile with its own private-account
banner visible). This wasn't a rare edge case; it broke scraping outright, for every profile, and
you had to **uninstall the `insta-automate` Helm release** to stop it — the harshest stop
available, used precisely because D69's Stop button didn't exist yet.

**Root cause:** D64's guard checked only `ui.profile_tabs_container.wait(timeout=5)` — a
PUBLIC-profile-only signal (`controllers/device.py`'s own `_profile_entity_access` uses it
exactly that way, `elif self.ui.profile_tabs_container.exists: return EntityAccess.PUBLIC`). A
legitimate PRIVATE profile never has that element either — it shows a lock/banner instead — and
PRIVATE is **scrape's own dominant, expected case**: the very next check in the same function,
`if user.access == EntityAccess.PUBLIC: skip`, exists precisely because scrape only wants PRIVATE
profiles. D64's guard was checking the wrong half of a two-sided condition, so it treated the
majority of real, working input as if it were the rare disabled-page case it was written for.

**Fixed by reusing `IaDevice._profile_entity_access()` directly** (already implements the correct
three-way PRIVATE/PUBLIC/neither check) instead of re-deriving a partial version of the same
logic — called once, early, with its result carried forward into `User.access` rather than
re-querying it a second time later in the function (which the pre-D64 code did, at the default
30s timeout). `None` (neither signal ever appears) is the only case that still means genuinely
unavailable.

**The verification gap that let this ship:** D64's own throwaway script never modeled the
private-banner case at all — its `FakeUI` had only `profile_id`/`profile_tabs_container`, so it
was structurally incapable of catching this regardless of how many cases it ran. The corrected
script explicitly exercises all three real outcomes of `_profile_entity_access` (PRIVATE must
proceed unskipped, PUBLIC must proceed unskipped by *this* guard then get skipped by the
pre-existing separate check, `None` must skip as `UNAVAILABLE` without ever reaching
`User.from_ui`) — 6/6 passing this time actually means something.

**Recovery, in order:** committed + pushed the fix, `GIT_BRANCH=feat/control-center ia build`,
`helm install insta-automate` (the release you'd removed — chart's `values.yaml` needed no
changes), restored the two manual `kubectl set env` patches (`IA_AGENT_TOKEN` on both
deployments, `GIT_BRANCH` on the scheduler — neither is in the committed Helm chart, so a
reinstall from scratch loses them, not just a restart) and `GIT_BRANCH=feat/control-center ia
prefect deploy` again (the worker's `create-work-pool` init container recreates the pool on every
pod start, D38's already-documented behavior). Verified live: both pods' installed source
confirmed via `kubectl exec` to have the fix, env vars intact, scheduler reporting `online: true`
with every flow gating normally. **Not yet re-confirmed against a real scrape run** — the
recovery was verified structurally (code present, pods healthy, gates sane) but no profile was
actually scraped again in this session to watch it succeed end to end.

### D67 · Ingest/Scan/Classify surfaces redesigned from a second round of live feedback; the Live screen's stale-flow-content bug found and fixed

**Ingest never had the image it was trying to show.** `IngestSurface` assumed `entities/<id>.jpg`
(the event's own `image` field) would usually exist — it doesn't, ever, at ingest time:
`export_entity()` (the only code that writes that file) is called from `scan_entity_init`, a
*later* flow, not from `add_new_entity` itself. Every ingest card was rendering a permanent
"image unavailable" placeholder that read as broken. Rather than build a new screenshot-capture
pipeline change (scoped and explicitly deferred — a real feature addition needing live phone
testing, not a bug fix), `IngestSurface` was rebuilt as a metadata card: a type-based icon,
the entity id, its URL, and type/access badges — all already present in `entity.added`'s own
`extra` field, no pipeline change needed.

**Scan's ordering, corrected again from your own clarification:** the vertical layout (D62) still
auto-scrolled to the bottom on new items — you'd actually meant the newest item to render
pinned at the top with nothing older ever needing to be scrolled to see it, closer to a
live activity feed than a chat log. Re-implemented without `reverse: true` (that flag is
specifically the chat-message "newest anchored at the bottom" pattern, not what was wanted here) —
newest-first is now just the first item in a plain top-down `ListView`. Also switched from two
images per row (an unintended side effect of `Wrap` at this pane's width) to one full-width image
with its caption below, matching what "one entry per row" actually meant.

**A real, separate `LiveController` bug:** switching flows (Ingest → Scan, auto-followed) left the
log console and visualization surface showing Ingest's *stale* content under the Scan tab for
several seconds, self-correcting only once you manually navigated away and back. Cause:
`AsyncNotifier`'s default `skipLoadingOnRefresh` behavior keeps showing the previous value while
a dependency-triggered rebuild is still in flight — exactly what a widget watching
`liveControllerProvider` with a plain `.when(loading: ...)` sees. Fixed by explicitly forcing
`state = const AsyncValue.loading()` at the top of `build()` whenever the *flow itself* changed
(not just its logs/events), so a real flow switch always shows a genuine loading state instead of
another flow's leftover data.

**New: a Force Run button on the Live screen's header** (your own request — "convenient to not
have to switch tabs just to trigger a flow and watch its logs"), working on whichever flow is
currently selected, reusing `FlowCard`'s existing confirmation-dialog logic (now shared, see D69).

**Verified:** `flutter analyze` clean, `flutter test` 39/39. Confirmed live: Ingest → Scan → Scan →
Classify all auto-followed correctly in your retest (this is what first surfaced D66's still-open
gap, addressed separately below).

### D66 · Message-triggered ingest never surfaced as `phase: "running"` in the scheduler snapshot

Root cause, found from your own retest: `entity_ingest_message_trigger` (the Telethon `NewMessage`
handler that fires instantly on a channel post — the "real-time" ingest path ARCHITECTURE
describes) calls `entity_ingest_trigger()` directly, bypassing `entity_ingest_time_trigger()`'s
loop entirely — the *only* place that calls `self._set_state("entity-ingest", phase="running",
...)`. The flow itself ran correctly; the scheduler snapshot simply never reflected it, so nothing
reading `phase` (the Live screen's auto-follow, in particular) could tell it was happening. Fixed
by setting `phase="running"` (then back to `"idle"` on completion) directly inside the message
handler too, tagged with `_current_flow.set("entity-ingest")` for D63's log-routing to pick up
correctly as well.

---

## 2026-08-02 — Seven bugs from live use, fixed in one session: real research first, then real redeploys

You listed seven things wrong with the app from actually using it (two screenshots included).
Three parallel Explore agents root-caused all seven before any code was touched — worth recording
because two of the seven turned out not to be what they looked like at a glance: the "Follow
button" cards in the Scan screenshot were native Instagram row-crop screenshots, not an app bug,
and the notification code was already correct — the real problem was D59's own flagged loose end
(never independently confirmed against a real Telegram delivery).

### D65 · scrcpy's `--adb=` flag doesn't exist — D55's fix silently failed every launch since the day it landed

**The report:** screen mirroring stopped working after D55's adb-churn fix, which the user
correctly suspected was related rather than coincidental.

**First finding: the fix's own mechanism was still intact but fragile.** `wsl-bridge`'s
`pyproject.toml` had no `rev`/`branch` pin on `my-modules` at all — its `uv.lock` was resolved to a
commit from *before* D55's fix, a live-venv hotfix one `uv sync` away from silently reverting.
Fixed by pinning `my-modules = { git = "...", rev = "<commit>" }` explicitly rather than trusting
the unpinned default to keep resolving to the right thing — the same durable-pin-over-live-hotfix
upgrade D55 itself deferred ("pending a real release").

**Second, bigger finding, only surfaced by actually starting a real mirror and reading the
process list: D55's fix never worked at all.** `scrcpy 3.3.4` has no `--adb=<path>` CLI flag —
running the exact command `my_modules.scrcpy.Scrcpy.start()` builds gets `scrcpy: unknown option
-- adb=...`, invisible in production because the class's own `Popen(..., stdout=DEVNULL,
stderr=DEVNULL)` swallows it. scrcpy only exposes this via the `ADB` **environment variable**
(confirmed against `scrcpy --help`'s own "Environment variables" section). D55's commit shipped
without ever launching a real mirror to confirm it worked — the churn-fix half (adb server binding
to `0.0.0.0`) was real and tested; this half wasn't. Fixed with a new commit on the same
`fix/scrcpy-adb-version-pin` branch (`94b308a`, still unmerged): `env["ADB"] = ADB` passed to
`Popen`, flag removed. Manually verified the raw command against a real error message before
writing the fix, then re-verified the corrected version against the real phone — mirror launches,
positions correctly (`snapped: true`, previously `false`), and is trackable through
`/api/device` for the first time since D55.

**Also found and fixed: a live orphaned mirror.** A `scrcpy.exe` process was running with no flags
at all — not launched through wsl-bridge's own `/scrcpy/start`, using the wrong bundled adb,
invisible to `GET /scrcpy/`. Killed with the user's confirmation first (a real on-screen window).

**Verified end to end:** stop wsl-bridge (agent-supervised) → `uv sync` → start via the agent →
`POST /api/device/scrcpy/start` → `snapped: true`, `/api/device` reports `mirroring: true` →
`POST /api/device/scrcpy/stop` → confirmed zero `scrcpy.exe` processes remain. This is the first
session this mirror has been proven to actually work end to end since CP 4.5.

### D64 · Disabled/unavailable Instagram profiles now skip gracefully instead of crashing `entity_scrape`

`profile_scrape` (`tasks/ia.py`) called `User.from_ui()` unconditionally once a profile page's app
bar populated — but a disabled/unavailable account still shows a username in the app bar while
having none of the post/follower/following elements `User.from_ui` reads without an `.exists`
guard (unlike `name`/`bio`, two lines above it, which already have one). Uncaught, this burned all
3 of `@ia_task()`'s retries (~90s) then hard-failed the whole `entity_scrape` run, aborting every
other queued profile in it too — a single bad profile in the queue could silently stop a run that
had nothing else wrong with it.

No live disabled profile was available to inspect Instagram's actual "account unavailable" page
copy/resource-ids, so rather than guess a new selector, the fix reuses the existing, already-proven
`profile_tabs_container` (`controllers/device.py`, already used by `_profile_entity_access` to mean
"this is a normal loaded profile") as a pre-check before `User.from_ui()` runs — a missing element
now short-circuits into the same `scrape.skipped(reason=...)` event pattern already used for
PUBLIC/NO_POSTS/FMIN/FMAX, rather than raising. **Flagged as best-effort**: verified by a throwaway
script (`.fn()`-level, every dependency faked) proving both branches — a missing
`profile_tabs_container` skips cleanly with `reason: "UNAVAILABLE"` and never reaches
`User.from_ui`, a present one falls through unaffected — but never exercised against a genuine
disabled account, since none was in the queue this session.

### D63 · Scheduler-pod log lines are now tagged by flow at the source, not broadcast to every active run

The Live screen's log pane showed other flows' trigger/gate lines mixed into whichever flow was
selected (`agent/flowruns.py`'s `_poll_scheduler_pod` sent every scheduler-pod line into *every*
currently-active run's ring — never attempted per-flow filtering at all), plus a duplicated
timestamp/level (`my_modules.logger`'s `RichHandler` already renders `[date] time LEVEL ... file:
line` into the raw text, and the app's `LogConsole` renders its own pill in front of that same
text).

Chose the real fix over an agent-only text-matching heuristic (checked with the user first) because
a heuristic provably misattributes real lines — Classify's own "Scanned entities found to classify"
gate-check line mentions "classify" but is Classify's own log, not Scan's; text content isn't a
reliable signal for *who logged it*, only a `contextvars.ContextVar` set once per trigger-loop task
is. `controllers/prefect.py` gained `_current_flow` + a `logging.Filter` that prefixes every record
from within a loop's task context with `[entity-scan]` etc. — one `_current_flow.set(...)` line per
trigger loop, no changes needed to individual `log.info`/`log.error` call sites or to `Deployment`,
since asyncio tasks each carry their own copy of the contextvar. `flowruns.py::_poll_scheduler_pod`
was rewritten to reconstruct Rich's wrapped multi-line records (a known, previously-unhandled gap
its own docstring already flagged), strip the baked-in prefix/suffix, route by the extracted tag to
only that flow's active run(s), and drop untagged lines (the startup banner, telegram-keepalive)
rather than broadcasting them — there's no consumer for a flow-agnostic scheduler stream today.

**Verified:** `agent/tests/test_flowruns.py` grew from 34/36 (2 pre-existing checks failed
immediately after the rewrite — correctly, since the old fixture's untagged lines are now
correctly dropped) to 39/39 after updating the fixture to the real tagged/wrapped shape and adding
checks for cross-flow isolation and wrap-reconstruction. All 13 agent suites green (698+ checks).
Bundled into one `Insta-Automate` commit with D64 and one redeploy cycle, deliberately, to avoid
two separate live pod restarts for two related fixes in the same session.

### D62 · Scan filmstrip changed from horizontal to vertical

`scan_surface.dart`'s row-crop images (1080:198 — wide, short) scrolled left-to-right in a fixed
180px-wide `ListView.separated(scrollDirection: Axis.horizontal)`. D44 had called this "not a
problem" for a different concern (cards not using pane width) and never actually evaluated
direction against what the user wanted — this session's explicit feedback overrides that. Converted
to the same vertical `SingleChildScrollView` + `Wrap` + scroll-to-`maxScrollExtent`-on-new-item
pattern already proven in `classify_surface.dart`, rather than inventing a new one.

### D61 · Live screen's auto-follow-the-running-flow only ever fired once, not "only for Scrape"

`live_page.dart`'s `_autoSelected` was a one-shot latch, not a per-transition flag — the first flow
observed `running` (usually Scrape, the shortest cycle) set it `true` permanently, silently
disabling auto-select for every later flow change for the rest of the session. Nothing was actually
scrape-specific anywhere in the surrounding code; the symptom was just "whichever flow happened to
run first, forever." Fixed by renaming the flag to mean only "the user manually picked a tab"
(`_userSelected`, set solely in the chip's `onSelected`) and re-checking whether the *currently
selected* flow is still running before ever considering an auto-switch — so the view now follows
every flow transition, not just the first one, until a real manual click opts out.

### D60 · Bugs 1 & 5 (Telegram fallback / missing hyperlink) were D59's own flagged loose end, not new bugs — closed for real this time

Investigation confirmed all of D59's four code paths were already correct (`notify()`'s fallback
logic, `EventBus`'s device-tagging, all three per-profile call sites' `url=`/`always_telegram=True`)
— D59 itself had already written "not yet independently confirmed: a real Telegram delivery
post-fix." This session did that confirmation for real: `kubectl exec`-ed into both pods and
grep-confirmed the D58/D59 code was genuinely loaded (it was — the pods hadn't gone stale again),
then called `notify()` directly inside the worker pod with zero paired devices connected. Result:
`delivered=False` (correctly reflecting zero real phone connections) → fell through to Telegram →
**user confirmed the message actually arrived.** The historical "Scan complete" entries with
`url: null` visible in `GET /api/notify`'s replay are pre-D58/D59 history sent by the stale pod
D59 already documented, not a live recurrence — every entry after this session's redeploy carries
`url` correctly.

Landed as part of the same commit + redeploy cycle as D63/D64, plus this session's own two additional
Insta-Automate fixes — `GIT_BRANCH=feat/control-center` was set explicitly for **both** `ia build`
and `ia prefect deploy` this time (the user flagged, correctly, that `ia build` needed the same
discipline `ia prefect deploy` already required after D55/D59 — `ia build` in fact resolves the
branch from the locally checked-out branch via `git branch --show-current`, not `GIT_BRANCH`, but
setting it explicitly regardless is the safer standing habit and was verified either way: the
generated Dockerfile's `pip install git+...@feat/control-center` was checked against the exact
commit hash before trusting it).

---

## 2026-08-02 — D58's pipeline half never reached the live worker pod; found from your own report

### D59 · A forgotten `git push` meant the worker pod kept skipping Telegram — same undeployed-code shape as D36/D39, different specific cause

**The report:** you noticed the three "always Telegram" notifications had stopped arriving on
Telegram, despite D58 landing that exact behavior hours earlier.

**Root cause, confirmed before touching anything:** D58's `Insta-Automate` commit
(`3e2186a`, `feat/control-center`) was created with `git commit` but never `git push`ed — the
worker pod's Prefect deployments `git_clone` from GitHub, not local disk, so it was still running
the pre-D58 `notify()` with no `always_telegram`/`url` at all (confirmed by `kubectl exec`-ing in
and reading the installed source directly, same technique as D39). Combined with the *agent* half
of D58 — already live, since `ia-agent.exe` is a local process I'd already restarted — correctly
computing `delivered` from real phone connectivity instead of "any WS client, desktop included,"
the live pipeline now saw `delivered=True` almost continuously (your phone's foreground service
holds a connection open most of the time) with no `always_telegram` override yet deployed to force
Telegram anyway. Every notification, not just the three per-profile ones, had been silently
skipping Telegram whenever your phone was connected — this is D53's original risk, made worse by
the agent-side fix landing before the pipeline-side override that was supposed to compensate for
it in the one case (per-profile notifications) where losing Telegram matters most.

**Fixed the same way as D39: push, `ia build`, restart, `ia prefect deploy`.** `git push origin
feat/control-center`, `ia build` (pinned the new commit, confirmed via the build log), `kubectl
rollout restart deployment/insta-automate-worker`, then verified the *new* pod's installed
`notify()` actually has `always_telegram`/`url` before doing anything else. The restart re-hit
D38's known work-pool-orphaning init container as expected — fixed the documented way,
`GIT_BRANCH=feat/control-center ia prefect deploy` (D55's exact lesson: a bare local shell
defaults to `main` without it). All 5 real flows + `sample-flow` confirmed `READY` against
`insta-automate-pool` afterward, and the scheduler's live state showed no crashes, normal gate
reasons across the board.

**Not yet independently confirmed:** a real Telegram delivery post-fix — there's no way to force
one without waiting for a genuine per-profile event (a follow, an already-known entity, an
unfollow-prompt) or a general notification while the phone happens to be connected. Flagged for
whoever picks this back up to watch for.

**The durable lesson, worth restating since this is at least the third time this exact shape has
bitten a session (D36, D39, now D59):** a local `git commit` is not deployed. Every checkpoint that
touches `Insta-Automate` needs an explicit "did I push, and does the live pod actually have this"
check before calling the work done — D58's own write-up asserted verification without that check,
which is exactly how this slipped through for hours undetected.

---

## 2026-08-02 — CP 6.4 built, then a notification redesign found by actually using it

### D58 · Device-aware notify routing, plus per-profile notifications get a real tap target and clean text — spans all four repos

CP 6.4 (mobile client) shipped all four planned slices (pairing, WS + foreground-service push
notifications, compact live flow view, config write-through) and each was verified live against
the real agent and a real phone — see the session's build log. Using it for real (both the
desktop's notification bell and the new phone notifications) surfaced three problems serious
enough to fix before calling the notifications phase done, per your explicit instruction:

**1. Markdown showed as raw text.** `**[@user](url)**`-shaped messages are built for Telegram's
renderer, but the same string is stored/shown verbatim by the agent — the desktop's notification
center displayed the literal asterisks and brackets.

**2. Routing was actually wrong, not just imprecise — this is D53's deferred risk, now real.**
`NOTIFY_POLICY=app_first`'s `delivered` meant "at least one live WS subscriber," which included
the *desktop app itself*. Once a phone client existed, having the desktop open at all would
silently swallow every notification that should have gone to Telegram. Fixed at the source:
`EventBus` (`agent/src/ia_agent/events/bus.py`) now tags every subscriber with the device id that
authenticated it (`None` for desktop), `subscriber_count(devices_only=True)` counts only phones,
and `NotificationStore.publish()` uses that count for `targets`/`delivered`. `ws.py` computes the
device id by calling `pairing_store.authenticate(credential)` a second time after the existing
`is_authorized()` check (harmless for desktop — no device token matches it). `EventBus.publish()`
itself is unchanged — the desktop still receives everything; it's a passive viewer that never
gates delivery or blocks Telegram either way. Small bonus riding the same plumbing: `GET
/api/pair/devices` now reports a live `connected` bool per device (cross-referencing
`EventBus.device_ids()`), not just `last_seen` — real confirmation of "actively connected," which
is the exact distinction you drew a line under ("don't confuse with simple pair").

**3. Three notifications are about one specific profile, not a flow-level event** — found by
auditing every `notify()` call site in `Insta-Automate`: `notify_profile_unfollow` ("scan
complete, you can unfollow"), `profile_follow`'s followed-by branch ("X is followed by Y"), and
`add_new_entity`'s already-exists branch (the third one, not in your original two — confirmed with
you before including it). These get two things the other seven call sites don't: a new
`always_telegram=True` param on `notify()` (independent of `NOTIFY_POLICY`) that forces Telegram
delivery regardless of whether a phone is connected, since these are judged consequential enough
to always leave a Telegram record; and a `url` field (the `Entity.url` already in scope at each
call site — no extra lookup needed) that flows agent-ward as the notification's tap target on
both clients, rather than relying on an inline clickable link inside possibly-truncated text.

**Rendering approach — deliberately not a markdown package on either client.** Both apps already
prefer small hand-rolled parsing for narrow needs (desktop's `FileOpener` instead of
`url_launcher`, e.g.) — new `core/notification_text.dart` (desktop) and its mobile twin
(`notification_text.dart` in `Insta-Automate-Client`) both strip `[text](url)` down to `text` and
drop `**` entirely rather than rendering it bold; the link itself is dropped from display
regardless since navigation is now the whole tile's job via the `url` field, not a fragile
inline-span tap target inside a 3-line ellipsized `Text`. **First version bolded the stripped
text on desktop — corrected from your live feedback**: plain text reads better here, so desktop's
formatter was simplified to exactly match mobile's (same function, same output shape), dropping
the now-unused bold-`TextSpan` machinery entirely. Mobile's tap-to-open is wired through a second
`FlutterLocalNotificationsPlugin` instance in the main isolate (tapping a notification is
inherently a main-isolate/UI event regardless of which isolate posted it), reusing the app's
existing `url_launcher` dependency and exact launch convention already used everywhere else in
that app (`queue_entity_card.dart` etc.).

**Also from your live feedback: the "followed by" name needed a leading `@` for visual
consistency with the linked profile above it**, even though it's not itself a link. Fixed at the
pipeline source (`tasks/ia.py`'s `profile_follow`), not the client formatters, since it's message
*content* — a regex inserts `@` right after Instagram's own `"Followed by "` UI text
(`ui.followed_by.get_text()`), before whatever name(s) follow. On Instagram's own multi-name
phrasing ("Followed by X and 3 others") only the first name gets the `@`, accepted as a minor
edge case since this is cosmetic polish, not a second link target.

**Verified:** agent — `agent/tests/test_notifications.py` grew to 37/37 (new cases distinguish a
desktop-only subscriber from a device one, and prove the desktop still receives the broadcast
despite `delivered=false` — the actual regression test for the bug), `test_pairing.py` to 31/31
(the new `connected` field flips true/false around the WS lifecycle); the full 13-suite agent
regression (698 checks total) stayed green. One real mistake caught before it stuck: the first
version of the `test_notifications.py` pairing addition didn't scratch-redirect
`PAIRING_DEVICES_PATH` like `test_pairing.py` already does, so it briefly wrote a fake "test
phone" into the *real* `%LOCALAPPDATA%\ia-agent\pairing.json` — caught immediately, fixed, and the
real file cleaned back up by hand. Live-checked against the real agent + your actually-connected
phone afterward: `GET /api/pair/devices` showed `connected: true` only for the live phone,
`POST /api/notify` reported `delivered: true` with it connected.

Pipeline — no test suite (standing precedent since CP 3.1); import sanity-check across every
changed module, plus a throwaway script (8/8) exercising all four `notify()` combinations
(device-active/inactive × general/`always_telegram`) against a monkeypatched `AgentClient`/
`IaTelegram`, confirming exactly which channel(s) fire in each case. Nothing deployed to the live
pod — same standing precedent as every `Insta-Automate` checkpoint since CP 4.3.

Desktop — `flutter analyze` clean, `flutter test` 39/39 (38 prior + 1 new: a per-profile
notification with markdown and a long username renders without overflow, the raw `**[`/`](https`
syntax never appears literally, and the open-link icon shows). Built and started for you per
rule 5 — confirmed live by you, twice: once against the original bold rendering (which prompted
the plain-text correction above) and again after the fix plus the `@`-prefix change, both times
against a real notification posted through the real agent.

Mobile — `flutter analyze` clean (no test suite exists for this app, matching CP 6.4's own
precedent that real verification here is on-device, not unit tests). Built, installed on the
connected test phone, and confirmed live against the real agent: a real per-profile-shaped
notification (`**[@user](url)**` message, `url` field set) arrived with clean readable text and
no raw markdown, and — per your report — worked end to end.

---

## 2026-08-02 — Session resume: CP 6.3 status reconciled, CP 6.4 ground rules set

### D57 · CP 6.3's "not committed yet" note was stale relative to the actual commit; CP 6.4 ground rules confirmed before writing any code

**The docs and the repo had drifted.** `CLAUDE.md` and `DECISIONS.md` (D56, below) both still read
"awaiting your test" / "not yet committed, per rule 4" even though commit `b2dd16b` — the same
commit that carried that text — was already on `main` with a message describing real verification.
Resolved by asking the user directly rather than guessing which side was right. Answer: the
verification described in the commit message did happen (pairing + notification bell against the
real agent), but it doesn't make CP 6.3 *fully* tested — that requires the phone side, which was
backend-mocked with `curl` standing in for `/api/pair/claim` because CP 6.4 (the actual mobile
client) doesn't exist yet. `CLAUDE.md` corrected to say exactly that instead of either extreme.

**CP 6.4 ground rules, confirmed before any code:**
- Work happens in `flutter/Insta-Automate-Client` (pubspec `ia_manager`) on `feat/lan-agent` only
  — never `main` — per rule 3, re-confirmed rather than assumed.
- After each change, build a real APK and install it on the phone currently connected over adb;
  that's the test loop for this checkpoint, not `flutter test`/`flutter analyze` alone (those
  still run, but an Android foreground-service WebSocket and real notification delivery need a
  real device).
- Any step needing a human — accepting an install prompt, granting a permission, actually scanning
  the QR — stops and asks rather than being scripted around.
- **The adb-connected test phone is not the user's production phone.** Its `IA_DIR` is stale, with
  no active Syncthing sync to this laptop — it's a coding/testing device only. The user's own,
  separate phone is the one with real `IA_DIR` sync, and CP 6.4 is not tested against it. A test
  result like "no images render" on the test phone may just mean stale local data, not an app bug
  — check which is which before treating it as a regression.

---

## 2026-08-02 — Phase 6 implementation session (CP 6.3, Desktop pairing & notification center)

### D56 · Built on D54's placement decision with no new agent code; a real header-row overflow was caught by the new layout test, not by `flutter analyze`

**CP 6.3 needed no agent-side changes at all** — CP 6.1 already shipped the full REST surface
(`/api/pair/*`, `/api/notify*`) and the `notifications` WS channel; this checkpoint is purely the
Flutter client on top of it. New `app/lib/features/settings/devices_controller.dart` +
`devices_tab.dart` (the "Devices" Settings tab D54 placed pairing in) and
`app/lib/features/notifications/notification_controller.dart` + `notification_center.dart` (the
title-bar bell). `core/pairing_models.dart` and `core/notification_models.dart` mirror the
agent's JSON shapes; `core/relative_time.dart` is a small shared "3m ago" formatter for both the
paired-device list's last-seen and the notification center's timestamps.

**QR payload is exactly `iacc://pair?h=<lan-ip>&p=8787&c=<code>`, per ARCHITECTURE §7** — no new
format decision needed, `qr_flutter` (already the planned dependency per §9) renders it directly
from `PairingCode.qrPayload`. The pairing card has no dedicated Riverpod controller beyond
`DevicesController` (start/list/revoke) — the mint→countdown→poll-for-claim→celebrate state
machine is local `StatefulWidget` state (`_PairingPhase`), since none of it is data anything else
on screen needs; polling for a claim is a 2s timer diffing device ids against a snapshot taken at
mint time, because CP 6.1 never wired a WS channel for pairing (a claim happens on the *phone*,
so the desktop has nothing to subscribe to — this was already flagged as a known gap in CP 6.1's
own notes).

**Per-tag mute is client-side only, persisted via `shared_preferences`** (the same store
`WindowGeometry` already uses) — there is no server-side "muted" concept, since `NOTIFY_POLICY`
already governs desktop-vs-Telegram routing (§6) and this is purely "don't show me this category
in the center." `unreadNotificationCountProvider` (the bell's badge count) excludes muted tags so
a muted category stops drawing attention to itself, matching what "mute" should mean.

**Found by the new `notification_center_layout_test.dart`, not `flutter analyze` (D19's
precedent, again):** the panel's header row (`Text('Notifications')` + `Spacer()` + filter
`IconButton` + "Mark all read" `TextButton`) overflowed by a consistent 101px regardless of window
size or notification content — reproducing on both the long-message test and the all-muted-empty
test, which share nothing but that header. Fixed by wrapping the title in `Expanded` +
`TextOverflow.ellipsis` instead of `Spacer()`, so the flexible title always yields space to the
fixed-size trailing controls rather than the row ever demanding more width than it's given.

**Also worth knowing for whoever touches this test file next:** `CompositedTransformFollower`'s
global position resolves at paint/composite time, which `flutter_test`'s hit-test-based tap
warning doesn't always account for on the frame right after an `OverlayEntry` is inserted —
tapping the bell and the panel's own filter icon both print a benign "would not hit test" warning
even though the tap genuinely lands (confirmed by asserting the `FilterChip`s the tap was
supposed to reveal actually appear). `warnIfMissed: false` is used at both call sites for that
reason, not to paper over a real mis-tap.

**Verified:** `flutter analyze` clean, `flutter test` 38/38 (26 prior + 12 new across
`devices_layout_test.dart` and `notification_center_layout_test.dart` — a 52-char paired device
name, the QR/code panel at the app's 1024px minimum window, a 400-char notification message with
no spaces, a long tag name in the filter row, and the all-tags-muted empty state). `flutter build
windows --debug` succeeds. **Not yet user-verified** — per rule 5, Claude built, analyzed, and
started the freshly built exe for you to test against the real running agent (real pairing round
trip with a phone once CP 6.4 exists, or manual-code entry for now; revoke; the notification
center against whatever `POST /api/notify` traffic the now-live CP 6.2 facade produces) — this
checkpoint is not committed yet, per rule 4.

---

## 2026-08-02 — Live incident: FOLLOW frozen "running" for hours, five things found chained together

### D55 · An uncaught adb exception froze `entity-follow`'s trigger loop forever; chasing why led to four more real, chained bugs

**The report:** the Flows screen showed `entity-follow` stuck at "running" for many minutes with zero flow runs triggered, despite 191 real files sitting in `follow_queued/`.

**Root cause #1 — the actual freeze.** `entity_follow_trigger()` (`controllers/prefect.py`) sets `phase="running"` then calls `wait_for_device()`, whose polling loop (`tasks/device.py`) had no exception handling around `IaDevice.connected()`. A transient adb connection refusal raised `AdbConnectionError` straight out of the loop, which killed the whole `asyncio.create_task()`-launched trigger loop permanently and silently (`Task exception was never retrieved` — never surfaced anywhere). The frozen `phase="running"` was simply the last state written before the task died; `heartbeat_loop()` kept re-broadcasting it forever since nothing was left to update it. Confirmed via Prefect's API: literally zero `entity-follow` flow runs since the scheduler pod's last restart, and the pod's own logs never printed another `entity-follow` line after that traceback.

**Fix:** all five trigger loops plus `keep_telegram_alive` wrapped in try/except (log, set a visible `"error"` gate, retry after one `TICK`) — general resilience, not just entity-follow. More importantly, `wait_for_device()` itself now treats a raised exception from `IaDevice.connected()` the same as "not connected yet" rather than propagating, fixing every caller (including `serve()`'s own unguarded startup call) at the source.

**Root cause #2 — why adb was refusing connections at all, found deploying the fix.** The host's currently-running adb server was bound to `127.0.0.1` only — not `0.0.0.0` — making it *unreachable from any pod, always*, not intermittently. The agent's own supervised adb command includes `-a` (all interfaces), but the live process was `origin: external`, started by something else without `-a`. Root: scrcpy's Windows build prefers an `adb.exe` sitting next to `scrcpy.exe` over PATH; the winget-installed scrcpy's bundled copy (v36.0.0) differs from the one actually running the server (v36.0.2, from `platform-tools`/PATH). adb's version-mismatch behavior kills and restarts the server on every scrcpy launch — and `device.start_scrcpy()` fires on every successful `wait_for_device()`, so once retries were made resilient (the fix above), *every* brief reconnect immediately re-triggered scrcpy, which killed the connection again in a tight ~30-45s cycle. This is the same pattern you'd already noticed in Services ("Take over" holding only "a minute or so" before reverting to `external`).

**Fix:** `my_modules.scrcpy.Scrcpy.start()` now passes `--adb=<path>`, pinned to whatever `shutil.which("adb")` resolves (the same binary the agent's own service spec already treats as canonical) — stops scrcpy from ever reaching for its mismatched bundled copy. Committed to `my-modules` on a new branch (`fix/scrcpy-adb-version-pin`), **not merged to main** (repo hygiene, same as every other cross-repo change). Made live immediately with a direct hotfix — copying the fixed file into `wsl-bridge`'s already-installed venv copy and restarting the (agent-supervised) `wsl-bridge` service — since `wsl-bridge` pins `my-modules` via an unpinned git dependency and a proper release wasn't warranted mid-incident. **This bypasses the normal git-dependency pipeline; a future `uv sync` in `wsl-bridge` will silently revert it** until `fix/scrcpy-adb-version-pin` is actually released and `wsl-bridge`'s lockfile updated. Flagged here so it isn't forgotten.

**Root cause #3 — deploying the scheduler fix nearly caused a worse outage.** Rebuilding and restarting the scheduler pod (`ia build` + `kubectl rollout restart`) hit the live version-mismatch churn described above at the worst possible moment: `serve()`'s own top-level `wait_for_device()` call (pre-fix, unguarded) raised on every single pod startup attempt for several minutes, producing a genuine `CrashLoopBackOff` — the entire scheduler down (all five flows), not just Follow. **Learned live: `ia build` re-tags the same image name every time (`insta-automate:3.6.27-python3.12`, no digest/commit suffix), so `kubectl rollout undo` does not actually restore the previous code** — the "old" ReplicaSet's pod spec references the same tag string, which the node's local image cache had already overwritten. Rolling back was a no-op in practice; only actually fixing `wait_for_device()` (root cause #1's real fix) stopped the crash loop. Worth remembering next time a rollback is reached for after `ia build`.

**Root cause #4 — the worker pod was 6+ checkpoints stale.** Once the scheduler recovered, `entity-follow` finally created a real flow run — which crashed instantly with `ModuleNotFoundError: insta_automate.controllers.notify`. CP 6.2 (the notifier facade, committed and pushed to `feat/control-center` days ago) was, per its own checkpoint notes, deliberately never deployed to the live worker pod. `git_clone`'s pull step only refreshes the flow's own top-level file, not what it imports (D39's exact precedent) — the worker's baked Docker image predated CP 6.2 entirely. **Decided with you mid-incident, not assumed:** restarting the worker now deploys CP 6.2 to production for the first time, earlier than the original "wait until the whole control center is accepted" plan (rule 3) — you approved it explicitly since it's what's actually needed for Follow (and anything downstream of `notify()`) to run at all. Restarting re-triggered D38's already-documented work-pool-orphaning init container; fixed the same documented way (`ia prefect deploy`).

**Root cause #5 — found only while fixing #4: `ia prefect deploy` run from a bare local shell silently deploys from `main`, not the feature branch.** `IaFlows.deploy_all()` builds each deployment's `parameter_openapi_schema` by cloning from `GitRepository(url=GIT_URL, branch=GIT_BRANCH or None)` — a **separate** git fetch from the worker pod's own `git_clone` pull step, and my local shell had no `GIT_BRANCH` set (that's a pod-only `kubectl set env` patch, D37/D39), so it silently fell back to `main`. `entity_follow`'s `force` parameter — added on `feat/control-center`, never merged to main per rule 3 — was invisible to that schema, so the very `ia prefect deploy` meant to fix #4 regressed entity-follow's own deployment, making every `run_deployment(parameters={"force": ...})` call fail validation (`SignatureMismatchError`) even though the actual flow body executed by the worker (sourced correctly via the pod's own `GIT_BRANCH`-aware `git_clone`) has always had `force`. Fixed by re-running with `GIT_BRANCH=feat/control-center` set explicitly. **Any future `ia prefect deploy` run from a local shell (not the pod) needs `GIT_BRANCH=feat/control-center` set first**, or it will quietly break whichever deployment's signature has diverged from `main` — worth a CP 7.1-style fix (read `GIT_BRANCH` from `config.env`/a committed default rather than requiring it in the caller's shell) but not done here, mid-incident.

**Verified end to end, live, no shortcuts:** after all five fixes, a `force_run` command (via the agent's REST API, not the GUI) produced a real `entity-follow` flow run that reached `COMPLETED` in 92.4s — matching historical successful-run durations. ADB held `origin: supervised`, bound `0.0.0.0`, same PID, for the rest of the session (well past the ~30-45s churn window it was breaking at before). Scheduler heartbeat back to `online: true`, sub-2s freshness. All other four flows (`scan`/`scrape`/`classify`/`ingest`) confirmed still gating correctly (`no_work`/`backpressure`) after every restart.

**Shipped, not yet verified over a long unattended window:** the scrcpy pin is a venv hotfix on `wsl-bridge`, not a real release — needs `fix/scrcpy-adb-version-pin` actually merged/released and `wsl-bridge`'s dependency bumped before it survives a `uv sync`. CP 6.2 is now live on the worker for the first time (earlier than rule 3's original plan) — everything downstream of `notify()` (limit-reached messages, unfollow prompts, etc.) is now actually running in production and should be watched.

---

## 2026-08-02 — Phase 6 implementation session (CP 6.3 groundwork, checked before writing any code)

### D54 · Pairing UI lives in a new Settings tab; the notification center is a title-bar bell icon — neither gets a new nav destination

**The gap:** ARCHITECTURE §9's seven nav destinations (Overview · Flows · Live · Services · Library · Insights · Settings) have no slot for either piece PLAN CP 6.3 scopes ("QR screen, paired-device list with last-seen and revoke, notification center with history and per-tag mute"). §9 originally imagined the notification feed living inside Overview, but Overview itself was never built past its CP 0.3 placeholder — no checkpoint in PLAN.md ever scoped it — so building the notification center "inside Overview" would mean building a minimum Overview screen first, unscoped work nothing asked for yet.

**Chosen, asked before any code was written (matching the CP 4.5/CP 5.4 precedent of checking real design forks rather than guessing):**
- **Pairing (QR code, paired-device list, revoke) is a new "Devices" tab in Settings**, alongside the existing Flows/Limits/Queue tabs — no shell changes, fits the established multi-tab pattern for "things backed by machine-local config," which pairing already is (CP 6.1's `pairing.json`).
- **The notification center is a bell icon in the title bar**, opening a dropdown/panel with history, unread state, and per-tag mute — reachable from every screen without requiring Overview to exist, and it's the standard place a user already expects to find this.

**Rejected:** a new top-level nav destination for pairing (grows the rail past ARCHITECTURE's planned seven for a screen that's mostly a one-time setup action), and building notifications inside Overview (blocked on unscoped work).

**Not yet built — this is groundwork only.** CP 6.3 itself starts from this placement decision.

---

## 2026-08-02 — Phase 6 implementation session (CP 6.2, Notifier facade)

### D53 · `notify()`'s Telegram fallback keeps the old search-and-delete dedupe by message text; a live screenshot buffer only reaches Telegram, not the agent; and a real risk was found and flagged, not silently shipped

**`controllers/notify.py`'s `_notify_telegram` reproduces `notify_transient`'s exact old mechanism — search the notify channel for messages with the *same text* as the new one, delete them, then send — rather than inventing a real dedupe-key concept on the Telegram side.** Telegram has no notion of an abstract dedupe key; the two callers that used to route through `notify_transient` (`notify_new_entities_classified`/`_scraped`) always had constant message text, so "same text" and "same dedupe key" were already the same test. Passing `dedupe=` on the limit-reached calls too (whose text embeds a changing count) is safe by construction: the search simply never matches anything, identical to those calls getting no Telegram-side dedupe before this facade existed.

**`notify_profile_unfollow`'s image is a live `ui.profile_header.screenshot()` `BytesIO`, not a file under `IA_DIR` — the one call site that doesn't fit `emit()`'s established IA_DIR-relative-path convention.** The agent's `/api/notify` (CP 6.1) can only cache a path it can read itself; there is no bytes-upload path, and building one for a single call site was out of scope for this checkpoint. `_relative_image()` returns `None` for anything that isn't a `Path`, so the agent-side notification for this one message simply carries no image — Telegram, which receives the original object untouched, still gets the real screenshot regardless of `NOTIFY_POLICY`, since `_notify_telegram` never goes through the relativizing helper.

**Found while wiring this in, not before: `POST /api/notify`'s `delivered` (CP 6.1) counts *any* live WebSocket connection on the shared bus, not a client actually watching notifications — because no such consumer exists in the app yet (CP 6.3 hasn't shipped a notification center).** Under the default `app_first` policy, if the desktop app happens to be open and connected to `/ws` for any reason (Live screen, Flows screen — anything), every `notify()` call across the whole pipeline would read `delivered: true` and skip Telegram, even though nothing currently renders it anywhere. That would be a real, silent loss of every limit-reached/unfollow-prompt/entities-classified message during normal daily use of this very app. **Not fixed here** — the honest fix (per-channel subscription tracking in `events/bus.py`, flagged as future work in its own docstring since CP 4.2) is bigger than this checkpoint, and it doesn't matter operationally yet: this branch (`feat/control-center`) is never deployed to the live pipeline pod until the whole control center is accepted (CLAUDE.md rule 3), and CP 6.3's notification center will exist well before that point. Recorded here so whoever revisits `NOTIFY_POLICY`'s default — or considers merging this branch — checks that CP 6.3 has actually landed first, or narrows `delivered` before then.

**Verified without touching the real Telegram channel or the real running agent.** `Insta-Automate` has no test suite (same precedent as CP 3.1/3.2/4.3) — verification was an import sanity-check across every changed module (`controllers/notify.py`, `tasks/telegram.py`, `tasks/device.py`, `tasks/ia.py`, `flows/entity_scrape.py`, `flows/entity_follow.py`, plus the full `IaFlows` registry and `controllers/cli` to catch indirect breakage) and a throwaway script exercising the facade's actual branching logic (18/18 — `app_first`/`telegram_only`/`both` routing, dedupe search-and-delete, the `Path`-vs-`BytesIO` image split, a missing-file `Path` dropped exactly like the old `img.exists()` guard) against `AgentClient.notify` and `IaTelegram.get_client` monkeypatched to recording fakes, never the real network calls. `AgentClient.notify` itself was already proven end to end against a real agent instance in CP 3.3/CP 6.1; nothing new here re-tests that path. Nothing deployed to the live pod — same standing precedent as every `Insta-Automate` checkpoint since CP 4.3.

---

## 2026-08-02 — Phase 6 implementation session (CP 6.1, Pairing + notification core)

### D52 · Q6/Q7/Q8 answered before writing code — device mirror stays desktop-only, Add Entity posts to Telegram, and every candidate notification category ships

**Q6 — device mirror stays desktop-only, the opt-in phone-glance stream is not built this phase.** CP 4.5 already made this call for the desktop side (D-numbered decision at the time, see PLAN CP 4.5); asked again now that mobile pairing gives a phone a real place to receive a stream, the answer was the same: build the consumer (this phase) before the producer (`device.mirror` broadcast plumbing), not the other way around.

**Q7 — the desktop app's future Add Entity action posts to the Telegram entity channel, not the DB directly.** Zero pipeline changes needed: the existing `NewMessage` handler already fires ingest instantly on a channel post. Matches PLAN's own recommendation. Not implemented this checkpoint (CP 6.1 is pairing/notifications only) — recorded now so whichever checkpoint builds it doesn't re-litigate the choice.

**Q8 — all four candidate notification categories are in scope: limit-reached, new entities classified/scraped, scan-complete/unfollow-prompt, and failures (device disconnected, flow failed, service down).** No category was cut. This doesn't mean every one pushes to a phone unconditionally forever — `NOTIFY_POLICY` and per-tag mute (CP 6.2/6.3) are the actual on/off switches — but the notification *store* built this checkpoint needed to know up front that `tags` is a real, load-bearing field on every entry, not an afterthought, since muting by tag only works if the right tags were being attached from day one.

### D51 · Device tokens are trusted everywhere a desktop token is, except managing pairing itself

**`auth.py`'s bearer check now accepts two token classes with no per-endpoint distinction by default** — the desktop token (file-based, same-machine trust) or any current, non-revoked device token (`PairingStore.authenticate`). Building both into one `is_authorized()` helper, shared by the HTTP middleware and the `/ws` handshake (which `BaseHTTPMiddleware` never wraps — same reason the desktop token needed its own WS-side check from CP 0.2 onward), keeps the two paths from drifting.

**Caught by the pairing test's own first run, not designed in up front: a device token could list and revoke *other* paired phones, and mint new pairing codes.** `/api/pair/start`, `GET /api/pair/devices`, and `DELETE /api/pair/devices/{id}` are desktop-console actions — a phone has no legitimate reason to enumerate or kick off siblings it didn't pair. Fixed with a route-level `_require_desktop()` check in `api/pair.py` that compares the request's credential against the desktop token specifically, layered on top of (not instead of) the outer middleware's already-broader check. `/api/pair/claim` stays reachable with **no** bearer at all — the phone claiming a code has none yet by construction (§7) — everything else a phone will actually need (CP 6.4: config, notifications, live flow view) is left open to both token classes rather than building a scoping system for endpoints that don't exist yet.

### D50 · Notification history is a persisted store, not an in-memory ring like flow events

**`events/store.py`'s `EventStore` is memory-only by design — a flow run's per-item images are worthless the moment the next run starts, so a restart losing them costs nothing.** A notification is the opposite kind of state: "FOLLOW limit reached" sitting unread is exactly what a restart must not silently discard. `notifications.py`'s `NotificationStore` writes its full history to `%LOCALAPPDATA%\ia-agent\notifications.json` on every mutation (add, mark-read), capped at `MAX_HISTORY=1000` so indefinite uptime can't grow the file without bound — same atomic temp-file-then-replace pattern every other `*.json` settings file in this agent already uses (D12's precedent).

**Dedupe replaces a prior notification with the same key only while it's still unread; once read, a repeat is a new occurrence.** This preserves `Insta-Automate`'s existing `tl.bot.notify_transient` search-and-replace semantics (ARCHITECTURE §6) rather than inventing new ones: "SCRAPE limit reached (180/300)" then "(250/300)" is one evolving fact worth collapsing to its latest value, but once you've acknowledged it, a fresh limit-reached notification tomorrow is a distinct event, not an edit.

**`delivered`/`targets` in `POST /api/notify`'s response is the live WS subscriber count at publish time, not per-channel subscription tracking.** `events/bus.py`'s `EventBus` broadcasts every channel to every connected socket today (its own docstring already flags per-client filtering as future work, "once there is more than one channel competing for bandwidth") — so "how many subscribers got this" is honestly answered by "how many sockets are connected," and a `subscriber_count()` method was added to the bus rather than building real per-channel accounting for a distinction that doesn't exist anywhere yet.

**Verified:** new `agent/tests/test_pairing.py` (29/29 — code TTL/single-use, device-token auth working on an ordinary bearer-protected route, the pairing-management scoping fix above, persistence across a fresh `PairingStore`, a real WS connection authenticated with a device token instead of the desktop token) and `agent/tests/test_notifications.py` (30/30 — defaults, image caching reusing CP 4.2's `images.cache` unchanged, dedupe-while-unread, `since=`/`unread_only=` filtering, mark-read/mark-all-read, persistence across a fresh `NotificationStore`, a live `notifications` WS delivery). All eleven prior suites unchanged (71/71, 49/49, 65/65, 36/36, 35/35, 32/32, 26/26, 24/24, 20/20, 16/16, 14/14). Also verified against the real running agent — restarted to pick up the new code (same step every checkpoint since CP 4.4 has needed; all three supervised services confirmed on identical pids across it) — a real pairing round trip (start → claim with no bearer → device token authenticating → revoke) and a real notify round trip (post → list → mark read) against the live `%LOCALAPPDATA%\ia-agent`, leaving one read, tagged `test` notification in the now-real `notifications.json` as the only trace.

---

## 2026-08-01 — Phase 5 implementation session (CP 5.4, Entity view)

### D49 · "Followed" stays a folder-count estimate — no Postgres ledger, deliberately, after weighing where the exact fix belongs

**The gap is real: no per-entity "followed" record exists anywhere.** `entity_follow` sends the request and unlinks the image on every terminal verdict — nothing is ever written to Postgres, so `entity_view.fetch()` can only approximate: `scraped − still in scraped/ − still in follow_queued/`. That's what shipped. Confirmed via your live test as "okay" with the one caveat that it can't be exact, especially for anything followed before this checkpoint existed (unrecoverable — the image is gone, no record was ever kept).

**The exact fix was scoped, not guessed at, before being set aside.** `profile_follow` already emits a `follow.result` event with a real `verdict` for every attempt (`Insta-Automate/tasks/ia.py`), so a real fix is genuinely small: one new SQLModel table, one `session.merge()` alongside the existing `emit()` call sites, no migration system to fight (this repo's schema is a bare `SQLModel.metadata.create_all()`, `controllers/postgres.py` — additive and idempotent). Where to persist it was the real question — weighed against IA_DIR-as-file, agent-local JSON (D12's precedent for machine-local settings), and Postgres — and Postgres won decisively: `entity_follow` already calls `db_backup()` at the end of every run, which `pg_dump`s the whole database to the Telegram backup channel (`db_restore()` to bring it back). Any new table rides that exact mechanism for free — zero new backup infrastructure for you to set up, unlike an agent-local file, which would need one from scratch to survive a laptop reset.

**Set aside anyway, on your call: not worth a cross-repo `Insta-Automate` change for a metric you said you may not use.** This project's own working rules already say not to design for hypothetical requirements — "followed" isn't what the funnel exists to answer (that's scanned → private → female → scraped, "which source entities are worth queueing," per PLAN CP 5.4's own framing), and every cross-repo change carries real weight here (unmerged on `feat/control-center` until the whole control center is accepted, per rule 3). The approximation ships as-is, undocumented as anything other than what it says on the label (`entity_view.py`'s own docstring already spells out exactly what it can't distinguish). If real per-entity follow tracking becomes worth it later, the design above is the one to build: a small Postgres table, written at the same `follow.result` call sites, backed up for free by the flow that already runs.

---

## 2026-08-01 — Phase 5 implementation session (CP 5.3, Library UI)

### D48 · Focus and selection are separate axes, keyboard and mouse both toggle rather than replace, and range-select anchors from whatever was last touched

**Corrected from your live testing, not guessed up front.** The first version required Ctrl+click to add to a selection (plain click replaced it, matching a common "single-select-by-default" file-manager convention) and treated a plain arrow key the same way `selectOnly` treated a plain click — moving focus *and* collapsing the selection to just the new item. Both read as wrong once you tried the actual workflow: "clicking it should toggle the selection... why do I need to press ctrl," and "arrows move the focussed image and space should do the same thing toggle the selection" — arrow-then-space-then-arrow-then-space needs each Space to *add* to the batch, which `selectOnly` made impossible since the very next arrow press had already thrown away the previous pick.

**Fixed by treating focus and selection as genuinely independent state**, not derived from each other: `LibrarySelectionNotifier.moveFocus()` (plain arrow — focus only, selection untouched) is now a distinct operation from `.toggle()` (plain click *or* Space — adds/removes the touched item from whatever's already selected, and becomes the new range anchor). `selectOnly()` is gone entirely; nothing in the UI ever collapses a selection down to one item anymore except `.clear()`. Shift+click/Shift+arrow (`.selectRange()`) were correct from the first version and untouched — they already extended from an anchor rather than replacing it, which is the same "add, don't replace" principle the fix applied everywhere else.

**Ctrl is no longer read from the tile's tap handler at all** (`LibraryTile.onPrimaryTap` dropped its `ctrl` parameter) — a plain click's meaning no longer branches on a modifier, so there was nothing left for it to gate. See [[feedback-multiselect-toggle]] for the durable UX rule this establishes for any future multi-select surface in this app.

**Verified:** `flutter analyze` clean, `flutter test` 32/32 throughout (both before and after the fix — the layout suite checks overflow, not selection semantics, so a dedicated interaction test wasn't warranted for a same-session correction verified live by you). Confirmed working via your own retest ("Thats better") before this checkpoint's docs were written up.

---

## 2026-08-01 — Phase 5 implementation session (CP 5.2, Mutations)

### D47 · Apply/delete mirror the pipeline's own `send2trash`/`shutil.move` split, move targets are a machine-local mapping seeded with the real pipeline shape, and `config.env` writers now share one lock

**`send2trash` for the discarded half, `shutil.move` for the promoted half — matching `insta_automate.utils.move`/`rm_empty_subdirs`, not the mobile app.** Checked the mobile app (`ia_manager`) first, since it already implements this exact review workflow: its `_applyAction` hard-deletes the unselected half via `File.delete()` — no trash, no recovery — while the pipeline's own `utils.py` already uses `send2trash` for every deletion it makes (`move(..., replace=True)`, `rm_empty_subdirs`). PLAN CP 5.2 says "use send2trash so semantics match the Python side," which settles the conflict in the pipeline's favor: `library/ops.py`'s `delete()` and `apply()`'s discarded half both go through `send2trash`; the promoted half uses a plain `shutil.move`, exactly like `utils.move`. A curation mistake from the desktop app is now recoverable from the Recycle Bin — the mobile app's is not.

**Move targets are a new machine-local setting (`library/settings.py`, `%LOCALAPPDATA%\ia-agent\library.json`), not `config.env` — same D12 reasoning as service self-heal/autostart.** The mobile app's `SettingsProvider._folderMappings` is a fully user-configurable per-folder dictionary defaulting to *identity* (apply = "keep selected, delete the rest," no promotion) until the user points a folder somewhere else. This project already knows the real two real human-review promotions ARCHITECTURE §1.1 documents (`gender_valid → scrape_queued`, `scraped → follow_queued`), so `settings._DEFAULT_TARGETS` seeds those directly rather than shipping the mobile app's blank-slate default — a user who never opens a settings screen for this (CP 5.3 hasn't built one yet) still gets the correct behavior on day one. Every other folder defaults to itself, which is a real, useful action on its own: "keep what I selected, discard the rest," with no promotion.

**`apply()` reads the batch fresh from disk rather than trusting the caller's file list.** The caller supplies `selected` (filenames to keep); "the rest" is computed from a real `os.scandir` of that `(folder, entity)` directory at call time, the same authoritative read `GET /api/library/images` would give right now — so a stale client-side selection (a file that arrived or left mid-review, the exact race CP 4.2's image cache exists to dodge elsewhere) can't silently trash or promote something the caller never saw.

**`config.env`'s write lock moved from `api/config.py`'s own `asyncio.Lock()` to a shared `env_file.WRITE_LOCK`.** CP 5.2 is the first time a second router (`api/queue.py`'s new add/remove/reorder) does its own read-modify-write of `config.env` alongside `api/config.py`'s existing `PATCH`. A per-module lock would only serialize writers *within* that module — two concurrent requests, one to `/api/config` and one to `/api/queue/add`, could still race each other's read-modify-write and silently drop one's change. Moved the lock into `config/env_file.py` itself, the one module both routers already import, so every writer serializes against every other one regardless of which endpoint it came in on.

**`POST /api/queue/remove` mirrors `Queue.remove()`'s default `check=True` refusal, not a bare wholesale delete.** The pipeline's own `Queue.remove(entity, check=True)` refuses to drop an entity from `ENTITY_QUEUE` while it still has jpegs waiting in either stage directory, unless the caller explicitly passes `check=False` — removing it from the priority list wouldn't stop the pipeline from working through the backlog, only from doing so *first*, which is a surprising side effect to hide behind an unqualified "remove." The new endpoint takes the same shape: a 409 naming the pending count, with a `force: true` field for a caller (the future UI, with a confirmation dialog) that means it.

**Verified:** `agent/tests/test_library.py` grew from CP 5.1's 32 checks to 65 (settings defaults/persistence/validation, `apply()`/`delete()` unit-level against a scratch tree — identity-mapped cull, real cross-folder promotion preserving `<root>/<name>`, rejecting an absent selection before touching anything, trashing an explicit path list, rejecting paths outside the seven folders — plus the same checks again over the real REST surface). New `agent/tests/test_queue.py` (14/14) covers `GET /api/queue` plus add/remove/reorder end to end, including the `check=True` pending-jpeg refusal, the forced override, a rejected path-shaped name, and confirming `config.env`'s comments/unrelated keys survive every mutation (the same guarantee `env_file.save()` already gave CP 1.1's `PATCH /api/config`). All eight prior suites unchanged (71/71, 32/32, 26/26, 49/49, 24/24, 20/20, 36/36, 35/35, 16/16). Also verified against the real running agent — restarted to pick up the new code (same step every checkpoint since CP 4.4 has needed), all three supervised services confirmed still running with uptime intact across it, `GET /api/library/move-targets` and `GET /api/queue` hit against the real `IA_DIR`/`config.env` (7,007 real `scrape_queued` files across 110 entities, correctly read-only — **no `apply`/`delete`/`add`/`remove` call was made against the real pipeline data in this session**, since those are real, only-partially-reversible actions on the user's actual curation backlog that nothing in this session asked for; the unit + REST test suites' scratch-tree coverage is what stands in for that live check, matching CP 4.2/4.3's own precedent of never mutating the real `IA_DIR`).

---

## 2026-08-01 — Phase 5 implementation session (CP 5.1, Library API)

### D46 · Device control compacted into the header, its model shown instead of the raw serial —
and the scheduler-line border removed for looking inconsistent rather than useful

**Three more small, real corrections from your live testing, landing together as the session's
close-out.** All Live-screen polish, none touching the agent's actual data surfaces (D36–D39) or
the event/counter logic (D40/D41) — those stay as they were.

**Device control moved out of `RunSummary`'s body into a compact `DeviceBar` in the header row**,
sharing the space next to the flow-selector chips rather than a bordered card competing with the log
console for room. Simplified at the same time, per your ask: dropped the status icon, the explanatory
sentence, and the card styling — just a phone icon, a name, and a `Start`/`Stop` button. `RunSummary`
reverts to the single column it had before D45's two-block `Wrap` (that redesign existed specifically
to give Device somewhere to sit beside the details+counters block; once Device left entirely, the
extra structure was no longer doing anything and a plain `Column` is simpler).

**The name shown is now the device model, not the raw 15-digit serial** — "I2201" reads at a glance,
the serial doesn't. New agent-side `_device_model()` (`ia_agent/api/device.py`) reuses the exact
`adbutils` lookup `services/selftest.py`'s own adb functional test already established
(`AdbClient(...).device(serial=...).prop.model`), best-effort — `None` on any failure (adb down,
device not attached), in which case the bar falls back to the serial rather than showing nothing.
**Caught by you, not assumed working:** the first version genuinely worked but the running agent
hadn't been restarted to pick up the new `/api/device` field yet — same "the code changed, the
process didn't" pattern this whole project keeps hitting — confirmed via `curl` against the live
endpoint both before (`model` key entirely absent) and after (`"model":"I2201"`) the restart, with
the three supervised services confirmed still `adopted` with uptime intact across it.

**The left border on scheduler-merged log lines (D30) is gone.** It marked which lines came from the
scheduler pod's own trigger/gate log (merged into the flow's ring) versus the flow's own execution
log — a real distinction, but you read the resulting ragged left edge as inconsistency rather than
signal. Kept one subtler cue instead of dropping the distinction entirely: those lines still render
in a dimmer text color, which doesn't disturb the shared left edge every line now has.

**Verified:** `flutter analyze` clean, `flutter test` 26/26 (25 prior + one new `DeviceBar` case — a
long model name in the header's own, tighter row, since some real phones report far more than
"Pixel 7"). Agent-side `test_device.py` 16/16, `/api/device`'s new field confirmed live against the
real device. Session closes here — Phase 5 is CP 5.1 done, CP 5.2 (mutations) next.

### D45 · Live screen layout, corrected twice more from your own testing: images fixed and tight,
not logs — and the direction was backwards on the first attempt

**Round one (backwards):** first read your "give images breathing room" as "images should grow" —
built D43 with the visualization surface `Expanded` and the log/summary column fixed. **Corrected
immediately** once you clarified: you'd said breathing room was for *logs*, and images — which
already wrap to fill whatever width they get (D44) — don't need to keep growing. Swapped which side
is fixed: log console (in an `Expanded` left column) now gets whatever the window has left; the
visualization surface is the fixed side. Picked the fixed width carefully rather than guessing large:
the app enforces a 1024×700 minimum window (`main.dart`), and an 820px image column (fitting two
D44 cards) would have squeezed the log column to ~204px at that floor — chose 600px instead, leaving
~424px for logs at the true minimum (matching what was already proven safe pre-D43), generous well
beyond that.

**Round two (still not tight enough):** even at 600px, D44's `Wrap` only fit one 380px scrape card
with real slack beside it — visible, still "wasted," per your next screenshot. Tightened to exactly
420px: one `_ScrapeCard` (380) plus the surface's own 16px padding on each side plus a scrollbar
allowance, no rounder number left over. Flagged in code as tuned to scrape specifically (the only
flow tested this session) — follow's own cards are wider (420, D44) and wouldn't fit this tightly;
revisit once that flow gets a real test, per your own stated plan.

**`RunSummary` was also reorganized in this round** (superseded later, same session, by D46 once
Device left `RunSummary` entirely) — worth recording because it's what caught a real bug: capping
the details+counters block to 320px to sit beside a Device block made the "many counters" stress
test overflow a 700px test height by 10px, since the same six chips now wrapped into more rows in
less width than they'd had before. Widened to 380px, confirmed clean — a genuine, would-have-shipped
overflow in an edge case (many counters after a long run id) that only surfaced by rerunning tests
after a width change, not by inspection.

**Verified, each round:** `flutter analyze` clean, `flutter test` 25/25 both times, before D46
superseded the `RunSummary` half of this entry.

### D44 · D43 widened the pane, but the cards inside it didn't use the width — `Wrap` instead of `ListView`

**Found immediately by you testing D43's fix**: the visualization surface really was wider, but
scrape/follow/classify's card lists are all a single-column `ListView` of `Row`-shaped cards (image
left, text right) — each card stretches to the *list's* full width but its own content doesn't, so
the extra room D43 freed just became more empty space to the right of every card, not more visible
information. Every scrape run so far had been tested at the *old*, narrower pane width, so this was
never visible until now.

**Fixed by capping each card's width and `Wrap`ping them, not by redesigning the cards.** A
`SizedBox`-capped `_ScrapeCard`/`_FollowCard`/classify card inside a `Wrap` fills a wide pane with
*more cards side by side* instead of one stretched-and-underfilled card per row — same visual design
each card already had (proven to work at that width by D41/D42's own testing), just packed more
densely. New `_HistoryWrap` in `scrape_surface.dart` (shared between the "all resolved" and the
in-progress branch's history list, both of which needed it); the same pattern inlined directly in
`follow_surface.dart` (420px cards, wider than scrape's 380 — its outcome badge can read
`WANTS_TO_FOLLOW`) and `classify_surface.dart` (320px, since its cards are simpler).

**`ClassifySurface` needed one more change than the other two: it became a `StatefulWidget`.**
`ScrapeSurface`/`FollowSurface` show resolved history that a person browses at their own pace, so a
plain `Wrap` in a `SingleChildScrollView` is enough. Classify streams fast enough to show its own
img/s rate, and the previous `ListView(reverse: true)` got auto-follow-the-newest for free from that
trick alone — a `Wrap` has no equivalent, so it needed the exact `ScrollController` + "did the count
change → animate to `maxScrollExtent`" pattern `scan_surface.dart` already established, applied here
verbatim rather than invented fresh.

**Checked, not applied everywhere:** `ScanSurface`'s own filmstrip is already a horizontally-scrolling
`ListView` of fixed-width items — structurally the same fix already, nothing to change. `IngestSurface`
already uses a `GridView` for the identical reason. Only the three single-column `Row`-card lists had
the gap.

**Verified:** `flutter analyze` clean, `flutter test` 25/25 (existing fixtures, unchanged — `Wrap` is
a standard widget with no custom sizing logic to add new overflow risk, and the existing 700px-wide
overflow tests still validate the worst case, a single card per row). Not yet verified against a live
run / real window at the actual (much wider) production width.

### D43 · Live screen: two columns, not three — summary sizes to content instead of stretching

**The layout itself was the last complaint**, once the data and per-flow visuals were actually
correct: the fixed 320px `RunSummary` column stretched to the window's full height regardless of how
little content it actually had, leaving visible dead space below the device pane, while the
visualization surface — the actual point of this screen, per its own docstring ("the showpiece
screen") — was squeezed into whatever was left between two other panes.

**Chosen: two columns, not three.** Left column (still a fixed 420px) is now a `Column`, not a
`Row` slot: `RunSummary` on top, sized to its own content (a non-flexible `Column` child gets
unbounded main-axis space to size itself — confirmed empirically in the test below, not just assumed
— so it never stretches further than it needs), and `LogConsole` in an `Expanded` below it taking
whatever height that leaves. The right side is now a single `Expanded` visualization surface, which
picks up both the freed 320px and log console's old share of the middle — a real, meaningful width
increase for the panel that actually needed it.

**Summary goes on top, not bottom** — a status glance (phase, today's count, last run, the counters,
device state) reads naturally as "here's where things stand" before "here's the detail log," matching
the same top-to-bottom priority `RunSummary`'s own internal ordering already uses.

**Verified the specific risk this change introduces, not just the width number.** `SingleChildScrollView`
(what `RunSummary` is built on) behaves differently under an unbounded main-axis constraint than
under the fixed `height: 700` every existing test gave it — genuinely worth checking rather than
assuming, since `ListView`/`CustomScrollView` (sliver-based scrollables) throw exactly this shape of
error ("Vertical viewport was given unbounded height") in the same situation. Rewrote both
`RunSummary` tests to reproduce the real constraint shape (`Column(children: [RunSummary(),
Expanded(...)])` inside a bounded outer height, not just `RunSummary()` alone in a fixed box) —
confirmed clean, since `SingleChildScrollView` (unlike its sliver-based cousins) measures its child
directly rather than needing a bounded viewport to lay out lazily. Also widened both `RunSummary`
tests from 320 to 420px to match the column's real new width — 320 was still a technically-valid
(narrower, stricter) case, but no longer representative of what production actually gives it.

**Verified:** `flutter analyze` clean, `flutter test` 25/25 (no new test count — two existing
`RunSummary` cases rewritten to the real constraint shape and width rather than added to). Not yet
verified against a live run / real window.

### D42 · The in-progress scrape card's own image ratio was still wrong, and roots are worth naming

**Found immediately by you testing D41's fix**: the still-in-progress card looked right structurally
(large, correctly scoped) but its image was a tall blank box — because it was still assuming the
scraped composite's portrait shape (`1080/2246`, actually the *entity-page* ratio, not even the
composite's own `1080/2000`) for an image that, while still in progress, is only ever the queued row
crop (`scrape_queued/<root>/<user>.jpg`) — the same wide `1080×198` shape `scanned/`/`gender_valid/`
already are. **Fixed properly this time by rethinking the layout, not just the number:** a wide strip
image doesn't belong squeezed into the portrait Row every resolved card uses, so the in-progress large
card now lays out as a strip on top with the details below, instead of forcing a wide image into a
narrow portrait box. Checked the small/resolved cards too while in there: `scrape.skipped` never gets
a composite either — it was *also* silently assuming the composite ratio for a row-crop image, fixed
to use `1080/198` for skipped specifically (only `scrape.done`, which genuinely has a composite,
keeps `1080/2000`).

**Added "root: <entity>" to both scrape and follow cards** — the source entity a candidate was found
under, i.e. the parent directory in `scrape_queued/<root>/<user>.jpg` / `follow_queued/<root>/<user>.jpg`.
New `rootFromImage()` in `surface_common.dart` (shared, since both flows have the identical
`<root>/<user>.jpg` shape) parses it from whichever event's `image` field is on hand — every event on
a given card carries the same relative path regardless of kind, so which one doesn't matter. Scoped
to scrape/follow only, not scan/classify/ingest — scan's own event already exposes the root directly
as `entity` (it's scanning that root's followers/following, not looking it up from a path), and
classify/ingest's row-crop images don't share this same `<root>/<user>.jpg` two-level structure in a
way that would read the same.

**Verified:** `flutter analyze` clean, `flutter test` 25/25 (no new test count — extended the existing
in-progress-card and follow-verdict fixtures with real `image` paths rather than adding new tests,
since the existing ones were the right places to exercise a long root name for overflow; the shared
`_event()` test helper gained an `image` parameter it didn't have before to make this possible). Not
yet re-verified against a live run.

### D41 · Three Live-screen UX requests, checked per-flow rather than assumed universal

**Your framing mattered here** — all three requests were demonstrated against Scrape (easiest flow
to trigger for testing) but explicitly asked to be applied "wherever relevant," not copy-pasted onto
every surface regardless of fit. Checked each of the other four surfaces before touching anything:

**1. "Large latest card" should track in-progress, not merely most-recent.** Confirmed this pattern
(a big card for the newest item, small history below) only exists in `scrape_surface.dart` and
`scan_surface.dart` — classify/follow/ingest render every item uniformly already, nothing to change
there. `scan_surface.dart` already keys its big banner off `scan.started` specifically (decoupled
from the completed-items filmstrip), so it was already correct. Only `scrape_surface.dart` kept the
latest subject large even after it resolved to `scrape.done`/`scrape.skipped`. Fixed: large is now
conditional on the latest subject still lacking a `done`/`skipped` event; the instant it resolves,
the surface falls back to one uniform small-card list, newest first, no special casing.

**2. Image cropping was two separate bugs, not one.** `AgentImage`'s default `fit: BoxFit.cover`
crops to fill an assumed aspect ratio — fine when the ratio is exact, lossy when it's approximate.
Checked all five real source images (ARCHITECTURE §1.1) against what each surface assumes: `scanned/`
row crops (1080×198 exact) and `entities/<id>.jpg` (1080×2246 exact) match their surfaces exactly —
`scrape_surface.dart`'s `done` card (`1080/2000`) is a *deliberate approximation* of a genuinely
variable height (`profile_scrape` composites a screenshot crop plus a resized avatar, so real height
drifts around ~2000 per profile) — no fixed constant will ever be exact there. `follow_surface.dart`
was outright wrong, not approximate: `1080/2246` (the entity-page ratio) for an image that's actually
`follow_queued/`'s scraped composite (~1080×2000, confirmed by reading `profile_follow`'s own `img`
parameter in `tasks/ia.py`) — a real second bug, not the same one twice. Fixed both: `AgentImage`'s
default is now `BoxFit.contain` (letterboxes instead of cropping — a no-op for the two exact-ratio
surfaces, and correct instead of lossy for the two approximate/wrong ones), and
`follow_surface.dart`'s aspect ratio corrected to `1080/2000` to match scrape's.

**3. Live incremental counters, computed per-flow rather than one generic rule.** The previous design
(D40) read only `flow.completed`'s aggregate, so "Counters this run" stayed empty until the whole run
finished — exactly the "wait for the end" the request was about. There is no single generic
"count something" rule that fits every flow, because each flow's per-item events carry different
shapes: `entity-scan`'s `scan.item` already carries the pipeline's own running `added`/`scanned`
tally per event (just read the latest one, no client-side counting needed); `entity-classify`/
`entity-follow` have no built-in running tally, but their per-item events carry a `verdict`, so a
live count-by-verdict client-side is exactly right (`PRIVATE`/`PUBLIC`, `FEMALE`/`MALE`, or the six
follow verdicts); `entity-scrape` has no `verdict` field, so `processed`/`scraped` are derived by
counting `scrape.done`/`scrape.skipped` occurrences directly; `entity-ingest` similarly counts
`entity.added` occurrences. New `_liveCounters(flow, events)` in `run_summary.dart` dispatches on
`flow` rather than guessing generically, incrementing live as each new per-item event streams in via
WS — no more waiting for `flow.completed` at all for this panel (that event kind is no longer read
here; its counters were always redundant with what client-side tallying now produces sooner).

**Verified:** `flutter analyze` clean, `flutter test` 25/25 (23 prior + 2 new — an in-progress-card
large-layout case for scrape, since the only prior `ScrapeSurface` test's fixture happened to always
resolve its latest subject and so no longer exercised the large-card path at all once this fix
landed; and a follow-verdict-tally case for `RunSummary`, since the prior "many counters" test read
`flow.completed` directly and would have silently tested nothing — an empty "No counters yet." —
under the new per-flow logic. Both gaps were caught by rereading what each test's fixture would
actually now exercise, not just by "tests still pass"). Not yet verified against a live run.

### D40 · Two Live-screen bugs found by real data, once real data finally existed

**Found the moment D39's rebuild made the visualization surface show anything at all** — the Live
screen never had real events to look wrong against until tonight, so these were latent since CP 4.4.

**1. `RunSummary`'s "Counters this run" mixed per-item facts into a run-level summary.** `scrape.done`
carries `counters: {posts, followers, following}` — one profile's own stats, meant for that profile's
card in the visualization surface. `_EventCounters` (`run_summary.dart`) merged *every* event's
`counters` map indiscriminately, last-value-wins per key — so after scraping two different profiles,
the panel showed one of their `posts`/`followers`/`following` (whichever `scrape.done` happened to
land last) labeled as if it were a whole-run fact. Meaningless at the run level either way — summing
follower counts across unrelated profiles isn't meaningful, and neither is showing one profile's
count and implying it represents the run. **Fixed:** only `flow.completed`-kind events (CP 4.3's
"unambiguous whole-run boundary" event, emitted exactly once per run with genuine aggregates like
`processed`/`scraped`) contribute to this panel now. Per-item counters stay exactly where they
already belonged — the per-card display in the visualization surface — and aren't duplicated here.

**2. Stale/orphaned events leaked into every run's display, forever.** `LiveController` scoped events
to the current run with `event.flowRunId == null || event.flowRunId == runId` — a permissive
fallback written back when `flow_run_id` injection didn't exist yet (pre-`f494553`), so *something*
would show up rather than nothing. Now that injection is reliable (confirmed by D39's real event
data), that fallback is pure liability: any event that ever got recorded with a null `flow_run_id` —
this session's own diagnostic probes among them — matches *every* run's filter forever, since `null`
never stops satisfying the OR. Concretely: two ad-hoc diagnostic events posted while chasing D39 sat
in the ring and showed up as phantom "scraping..." cards on the very next real run, alongside the two
genuine ones. **Fixed:** removed the null fallback in both the REST replay (`_fetchEvents`) and the
live WS handler (`_handleWsEvent`) — a `FlowEvent` now only belongs to a run if its `flow_run_id`
actually matches. The in-memory event ring itself was also cleared (an agent restart — it's pure
ephemeral debug/display state, nothing persisted depends on it) to flush the diagnostic events
already sitting in it; real runs going forward stay correctly scoped without needing that.

**Verified:** `flutter analyze` clean, `flutter test` 23/23 (unchanged — no new layout-risk surface,
existing `live_layout_test.dart` coverage still exercises both widgets). Not yet re-verified against
a live run with the fix in place — needs a rebuilt/restarted app and one more real scrape to confirm
the panel now shows only `processed`/`scraped` and the surface shows only the current run's cards.

### D39 · **D36 was incomplete.** Correction: git-based deployment only refreshes the flow's own
top-level file — everything it imports (`tasks/`, `controllers/`, `models/`) stays frozen at
whatever was baked into the worker's Docker image, and needed a real rebuild all along

**Found after D38's fix still didn't produce any per-item events** — `flow.started`/`flow.completed`
fired (proving connectivity, auth, and event storage all worked, per D37/D38), but every per-item
`scrape.started`/`scrape.skipped`/`scrape.done` call inside `profile_scrape` — which CP 4.3 genuinely
added, confirmed present in the pushed source — never arrived. Diagnosed by `kubectl exec`-ing into
the worker pod and directly inspecting what Python actually had loaded:
`inspect.getsource(insta_automate.tasks.ia.profile_scrape)` showed a **version with zero `emit()`
calls at all** — pre-CP-4.3 — and `inspect.getsource(AgentClient.emit)` showed the version *before*
`f494553`'s `flow_run_id` injection. Both came from `/usr/local/lib/python3.12/site-packages/
insta_automate/`, i.e. **whatever was `pip install`ed into the image at build time**, not the branch
the deployment's `git_clone` step pulls.

**The actual mechanism, now understood precisely:** Prefect's `flow.from_source(GitRepository(...))`
does clone the branch fresh on every flow run, and it does load the flow's own entrypoint file
(`entity_scrape.py` etc.) directly from that clone via its file path — so code written *directly in
the flow body* genuinely does refresh with every push (this is why `flow.started`/`flow.completed`,
called inline in the flow body, worked immediately after D36). But that file's own `from
insta_automate.tasks.ia import profile_scrape` and `from insta_automate.controllers.agent import
AgentClient` are ordinary absolute imports, resolved through normal Python import machinery against
whatever's already on `sys.path` — which is the image's site-packages install, since nothing in the
`git_clone` pull step (just a bare clone, no `pip install -e`, no `sys.path` manipulation) makes the
cloned copy of `tasks/`/`controllers/`/`models/` take precedence. **A `git push` alone is therefore
only sufficient for changes made directly in a flow's own top-level file** — everything CP 4.3
actually touches (`tasks/ia.py`, `tasks/ollama.py`, `controllers/agent.py`) needed an image rebuild
all along, which is exactly what D29's original technique already did for CP 3.5 — this session just
hadn't re-learned that lesson before D36.

**Fixed:** `ia build` (from `D:\Coding\Insta-Automate`, on `feat/control-center`, clean tree) — 13s,
`uv pip install git+...@feat/control-center` inside the Dockerfile pins the exact pushed commit
(`f4945537...`, confirmed in the build log) — then `kubectl rollout restart deployment/
insta-automate-worker` (confirmed with you first, given the scope: a real image build + redeploy,
bigger than anything else this session) to pick up the freshly retagged local image
(`imagePullPolicy: IfNotPresent`, same tag `insta-automate:3.6.27-python3.12`, so Rancher Desktop's
shared image store is enough — no registry push needed). D38's `create-work-pool` breakage recurred
on this restart too (expected now — every worker restart does this) and was fixed the same way,
`ia prefect deploy` again. **Verified the fix landed**, not just assumed: `kubectl exec`'d into the
new pod and re-ran the same `inspect.getsource` check — `profile_scrape` now shows 6 `emit()` calls
including `scrape.started`/`scrape.done`, `AgentClient.emit()` now injects `flow_run_id`. Have not
yet re-verified against one more real, device-driven scrape run — that needs you to trigger it.

**How to apply, going forward:** for any future `Insta-Automate` change to land on the live worker,
check *where* the change is. A flow's own top-level file (the `@flow`-decorated function's own body)
refreshes on push alone. Anything it imports from `tasks/`, `controllers/`, or `models/` needs
`ia build` + a worker rollout — always, no exceptions, regardless of how "just a small pipeline
change" it feels like. This also means: don't trust "the deployment's `pull_steps` point at the
right branch" or "the branch is pushed" as proof that live behavior changed — the only real proof is
introspecting what's actually loaded in the running pod (`inspect.getsource`, as done here) or
observing the actual downstream effect (an event landing), the same discipline D36/D37 already
established, just needed one more layer of "don't stop until you've verified the real signal."

### D38 · The worker pod's `create-work-pool` init container is destructive, not idempotent —
restarting the worker pod for any reason orphans every deployment

**Found immediately after D37's fix**, when you Force Ran Scrape again and the worker never picked
it up at all (stuck `SCHEDULED`/`Late` forever, despite the worker showing `ONLINE` and its queue
`READY`). Cause: the worker pod's init container named `create-work-pool` logs, on every pod start,
literally `Deleted work pool 'insta-automate-pool'` followed by `Created work pool
'insta-automate-pool'!` — a **delete-and-recreate**, not a create-if-missing. The restart I did for
D37 (`kubectl set env`, which recreates the pod) triggered this init container, which gave the pool
a brand-new UUID. Every existing deployment (`entity-scrape` etc.) still pointed at the old,
now-deleted pool id, so all six showed `work_pool_name: None` / `status: NOT_READY` — invisible
unless you specifically query a deployment's own record, since the pool itself still shows `READY`
and the worker still registers and polls it fine.

**Fixed:** `ia prefect deploy` (the CLI wraps `IaFlows.deploy_all()` — an existing, dedicated command
for exactly this) run once inside the scheduler pod (confirmed with you first). Re-created/
re-attached all six deployments against the current pool id; all show `READY` again. No pod restart,
no image rebuild. The one flow run that was created while broken (`ruddy-wolf`, `aeb50e85-...`)
stays orphaned permanently — a deployment reassociating later doesn't retroactively fix a run's own
already-stored (now-dangling) queue reference — but that's cosmetic, it just sits as `Late` forever
and nothing depends on it clearing.

**Left open, not fixed:** the `create-work-pool` init container's delete+recreate behavior itself is
unchanged — it lives in the Helmcharts repo's worker pod spec (not audited this session; whoever
touches `Helmcharts/Insta-Automate/templates/worker.yaml` next should look at what actually runs
there and consider making it idempotent, since **any** future worker pod restart — a crash, an OOM,
a routine redeploy, not just a deliberate `kubectl set env` — will silently repeat this exact
breakage until someone notices flow runs aren't being picked up and re-runs `ia prefect deploy` by
hand. Worth an ARCHITECTURE/PLAN note whenever CP 7.1 (ops panel) or a Helmcharts session happens.

**How to apply — chain lesson from D36/D37, continued:** each fix this session revealed the next
problem only once verified end-to-end against real behavior, not just "the config looks right now."
D36 fixed the branch, D37 fixed the missing secret, D38 was caused *by* fixing D37 (restarting a pod
to apply an env var is not a no-op action in this cluster). When debugging a live pipeline gap here,
expect fixing one layer to surface the next, and re-verify with a real trigger after every change
rather than assuming the chain is closed.

### D37 · The worker pod never had `IA_AGENT_TOKEN` — every `emit()` call was 401ing silently

**Found immediately after D36**, when you ran a real Force Run of Scrape after that fix and still
saw nothing: the flow genuinely completed (180/300 scraped, up from 145 — confirmed against
`/api/flow-runs`), but `GET /api/events` on the real agent showed **zero events ever recorded**.
`kubectl exec` into both pods directly (not the deployment spec — the actual running containers)
showed why: the **scheduler** pod has `IA_AGENT_TOKEN` set (matching the real agent's token) and
`GIT_BRANCH=feat/control-center`; the **worker** pod — the one that actually executes `profile_scrape`/
`profile_follow`/`gender_classify` and every `emit()`/`emit_sync()` call CP 4.3 added — had neither.
`IA_AGENT_TOKEN` is deliberately env-only, never `config.env` (D26, since it's a secret), so with it
unset the worker's `vars.IA_AGENT_TOKEN` resolves to `""`, every event POST goes out with an invalid
bearer token, the agent's `BearerAuthMiddleware` 401s it, and `AgentClient`'s entire design (D26) is
to swallow every failure silently so a down agent never disturbs the pipeline — which also means a
*misconfigured* agent connection disturbs nothing either, including never producing an error to
notice. Both env vars were originally set only on the scheduler pod, apparently by hand (neither
appears anywhere in the Helmcharts repo's templates), during some earlier session's live testing —
and the worker never got the same patch.

**Fixed:** `kubectl set env deployment/insta-automate-worker IA_AGENT_TOKEN=<same token>` (confirmed
with you first, since it restarts the worker pod). No image rebuild — same reasoning as D36, it's
just a pod env var. Confirmed the new pod (`...-75fd88d98c-fq2v9`) actually has it post-rollout.
**Not fixed / left open:** this was a manual `kubectl set env` patch, same as the scheduler's own
`IA_AGENT_TOKEN`/`GIT_BRANCH` — neither is in the committed helm chart, so a future `helm upgrade`
without carrying these forward would silently reintroduce this exact bug on the worker (and revert
the scheduler's `GIT_BRANCH` override, which is intentional per D29 — that one's *supposed* to reset
on a real deploy). Phase 7's CP 7.1 (`ops panel`) is where `IA_AGENT_URL`/`IA_AGENT_TOKEN` are
planned to move into helm values properly (ARCHITECTURE, CP 7.1) — until then, if the worker pod
ever gets redeployed for any other reason, this patch needs reapplying.

**How to apply — same lesson as D36, one layer deeper:** "the deployment config points at the right
branch" and "the code that branch clones is current" were both necessary but not sufficient — the
pod actually executing that code also needs the right *runtime* configuration (here, a secret env
var) or its calls fail in a way `AgentClient`'s own swallow-everything design makes structurally
invisible. When a live symptom persists after fixing one plausible cause, don't stop at "that must
have been it" — verify the actual downstream signal (here, `GET /api/events` actually gaining
entries) before declaring it fixed.

### D36 · `feat/control-center` in `Insta-Automate` was never pushed — the Live screen's
visualization surfaces were blank for two sessions because of it, not because of anything missing

**The bug:** you reported the Live screen's middle pane ("visualization surface") reading "No scrape
activity yet for this run" on every real scrape you'd tried since CP 4.4 landed. CLAUDE.md already
predicted this for CP 4.4's own test session ("CP 4.3's `emit()` calls aren't deployed to the live
pod yet"), so the first hypothesis was that nothing had changed. It had — the scheduler pod's
deployments already had `GIT_BRANCH=feat/control-center` set and Prefect's own `git_clone` pull step
confirmed every deployment (`entity-scan`, `entity-classify`, `entity-scrape`, `entity-follow`,
`entity-ingest`) was configured to clone that branch. The actual cause: that pull step clones from
**`https://github.com/SeshuTarapatla/Insta-Automate.git`** (the GitHub remote), not the local
`D:\Coding\Insta-Automate` working copy — and local `feat/control-center` was 3 commits ahead of
`origin/feat/control-center`, including `22a706d` (CP 4.3's own flow-instrumentation commit). So
every real flow run since CP 4.3 was written had been executing whatever code predates it, cloned
fresh from GitHub on each run, with zero `emit()` calls anywhere in it — not a partial rollout, a
complete no-op.

**Fixed:** `git push origin feat/control-center` from `D:\Coding\Insta-Automate` (confirmed with the
user first — still a feature branch, not `main`, consistent with the repo's own "other repos are
feature-branch only, never merged" rule, but pushing to a shared remote is still a step worth a
yes/no). No pod restart or redeploy needed — the worker's `git_clone` step runs fresh on every flow
run, so the very next scrape/scan/classify/follow picks up the real code.

**How to apply — the general lesson:** when a cross-repo checkpoint's own session notes say
"verified via a live round trip against a throwaway agent instance" or "nothing deployed to the live
pod yet," that means exactly what it says — a later session must not assume a prior session's
"looks deployed" (an env var present, a deployment's `pull_steps` pointing the right direction) is
the same as "the code the remote clones is actually current." When something that should be visible
in the live app stays stubbornly blank across multiple real runs, check what the *actual remote git
state* is before re-checking the agent/app code — a local-only commit is invisible to anything that
clones over HTTPS.

### D35 · Recompute-on-touch counts, folder-scoped recursive watching, path-keyed lazy thumbnails

**Cached counts invalidate by recomputing the touched pair, not by tracking deltas.**
`LibraryCounts.touch(folder, root)` always re-`scandir`s the one directory a filesystem change
pointed at and replaces whatever was cached for it, rather than adjusting a running +1/-1 counter.
A watcher batch that coalesces multiple rapid changes into one event, or drops one under load, can
never leave a delta-tracked count permanently wrong — a recompute-on-touch count is only ever as
stale as "since the last touch," and the next touch always corrects it. Cost is a non-issue: even
`scrape_queued`'s busiest real root today is ~136 files, and a full `seed()` across the whole real
`IA_DIR` (433 + 7,042 + 180 files across ~120 directories) measured at **15 ms** in
`check_library.py` — nowhere near where per-touch `scandir` cost would matter. A root's count
recomputing to 0 drops it from the per-entity dict entirely rather than keeping an empty tile —
mirrors the "explain why, don't show something dead" instinct behind D17, just for a count instead
of a terminal pane.

**The watcher passes the seven known stage directories to `watchfiles.awatch()` explicitly, and
watches each recursively** — the opposite of `config/watcher.py`'s deliberately non-recursive
top-level-only watch of `IA_DIR`. That earlier choice was about *dodging* the library folders'
churn; this one exists *because of* it. Passing the seven paths directly rather than watching
`IA_DIR` itself means `.thumbs` (the mobile app's own thumbnail cache) and `.Trash-0` (send2trash's
trash, relevant again from CP 5.2) never wake the watcher, without needing an exclude filter.

**Thumbnails are generated lazily, keyed by path at request time, reusing CP 4.2's
content-addressed `images.cache`/`thumbnail` unchanged** — rather than eagerly hashing every listed
file up front. A virtualized grid (CP 5.3) only ever renders the handful of cells actually on
screen, so hashing and caching bytes for files nobody has scrolled to yet would be pure waste.
Content-addressing already means a file later moved by CP 5.2's `apply`/`delete` mutations doesn't
invalidate an already-cached thumbnail — same bytes, same key, regardless of where the file now
lives (or whether it still exists at all).

**Verified:** `agent/tests/test_library.py` (32/32 — folder taxonomy resolution including
path-traversal rejection, seed/touch counting for both flat and per-root folders, a root dropping
out of `entities()` at zero files, full REST round trip, and a real filesystem write reaching a
`library.changes` WS subscriber) plus new read-only `agent/tests/check_library.py` against the real
`IA_DIR` (seed timing, real entity listing, a real image cached and thumbnailed). All eight prior
suites unchanged (71/71, 32/32, 49/49, 26/26, 20/20, 24/24, 36/36, 35/35, 16/16). Also verified live
against the real running agent: restarted it to pick up the new code (same "the code changed, the
running process didn't" step CP 4.4 needed, D21's launcher brought it back in ~8s), confirmed the
three supervised services stayed `adopted` with uptime intact across that restart, then hit every
new endpoint (`folders`, `entities`, `images` with pagination, `image`, `image/thumb`, the
path-traversal 400) against the real `IA_DIR`'s real 7,655 files and confirmed the WS channel is
live (received real `flows.state` heartbeats over the same socket; no `library.changes` frame
happened to fire in the listening window since nothing was actively scanning/classifying at the
time — already covered end-to-end by the test suite's own real-file-write check).

---

## 2026-08-01 — Phase 4 implementation session (CP 4.5, Device view)

### D34 · Window found by PID, not title; the phone-glance stream deferred until Phase 6 can use it

**Chosen, checked with you before writing any code rather than guessed** (both were real forks, not
implementation details): the plan describes positioning the scrcpy window with `my_modules.win32.
snap_window`, which searches by exact window title — but scrcpy's title varies by phone model, and
both `my_modules` and wsl-bridge are marked "no changes expected" (ARCHITECTURE §8), so normalizing
the title at the source wasn't available. New `ia_agent/window.py` finds the window by **PID**
instead — wsl-bridge's `POST /scrcpy/start` already returns the spawned process's pid, exact, no
cooperation needed from either repo. Uses the same raw `ctypes.windll.user32` approach `snap_window`
already does (no new `pywin32` dependency), just `EnumWindows`+`GetWindowThreadProcessId` to match by
pid rather than `FindWindowW` by title.

**The plan's secondary, opt-in low-fps `device.mirror` stream (so a paired phone can glance at the
mirror) is deferred entirely** — Phase 6 (mobile pairing) doesn't exist yet, so there is no consumer
for that channel today. Building the `adb exec-out screencap` capture loop and broadcast plumbing
now would be untested code with nothing to exercise it until Phase 6 lands; scoped this checkpoint to
the primary desktop path only.

**`POST /api/device/scrcpy/start` refuses to cycle an already-running mirror** — same "don't be rude"
reasoning `test_wsl_bridge()`'s existing selftest already established (D-less precedent, just
followed here): `wsl-bridge`'s own `start()` calls `stop()` on the way in, so restarting an active
mirror would throw a new window on screen and interrupt whatever the mirror was being used for. The
snap is retried for up to 5s after a successful start, since the window doesn't exist the instant the
process does — and a snap that never lands still reports the start itself as successful, since the
mirror came up fine regardless of whether the agent could reposition it. `snap_to_known_position`
only re-asserts the exact position `my_modules.scrcpy.Scrcpy.start()` already requests at launch
(`--window-x=1 --window-y=45`) and reads the window's current size first, so it is purely defensive
(a compositor/DPI quirk ignoring the launch hint) and can never resize or distort the video.

**Found while verifying the window-finding mechanism against a real process, not a mock:** the first
attempt spawned a throwaway Notepad and called `find_window_by_pid` on its launched pid — found
nothing. Windows 11's own Notepad turned out to be a packaged app where the pid `subprocess.Popen`
returns is not the pid that owns the window (confirmed via `EnumWindows` dumping every visible
window's owning pid — a different, unrelated pid owned "Untitled - Notepad"). This is exactly D11's
"the pid that binds a port/owns a window is rarely the pid you launched" pattern, just a target this
project hadn't characterized yet — Notepad, not anything this project spawns. Switched to the
machine's actual already-running `scrcpy.exe` (found via `psutil` by name, read-only — nothing
started, stopped, or moved) and confirmed: `where scrcpy` resolves to the exact same path as the
running process's `.Path`, i.e. a real winget-installed native exe with no shim/trampoline in the
chain, and `find_window_by_pid` correctly locates its window. The mechanism is verified correct for
its real target; Notepad was simply the wrong thing to test it against.

**Verified:** `agent/tests/test_device.py` (16/16 — every REST branch: already-mirroring skip, the
snap retry loop succeeding after several tries, a snap that never succeeds not failing the start,
both wsl-bridge failure paths as 502s — against a monkeypatched `wsl_bridge`/`window`, never the real
bridge or a real window). `agent/tests/check_device.py` (new, read-only) then confirmed the real
mechanism against the machine's actual scrcpy process, as described above. `flutter analyze` clean,
`flutter test` 23/23 unchanged (no new layout risk beyond what `RunSummary`'s existing test coverage
already exercises).

---

## 2026-08-01 — Phase 4 implementation session (CP 4.4, Live screen)

### D33 · The Live screen resets on a new run id, not on every heartbeat tick; a shared flow-name lookup instead of a duplicate one

**Chosen:** `LiveController` watches `selectedFlowProvider` (rebuilds `build()` on a flow switch)
but only `ref.listen`s `flowsControllerProvider` — a heartbeat arrives roughly every 2s and would
otherwise force a full `logs`/`events` refetch on nearly every tick for no reason, since almost none
of those change anything relevant. The listener compares `flows[currentFlow]?.lastRun?.id` against
what was last seen and only re-fetches when that id actually changes (a new run started), mirroring
`FlowsController`'s existing "listen for the interesting change, don't rebuild on every emission"
shape rather than inventing a new one.

**`flowTitle`/`phaseLabel` moved from `flow_card.dart` (private) into `scheduler_models.dart`
(shared)** rather than copied — the Live screen's `RunSummary` needs the exact same flow-name and
phase display strings `FlowCard` already has, and a second copy would drift the moment either one's
labels changed. `flow_card.dart` updated to use the shared versions; `flutter test` (23/23,
including the pre-existing `flows_layout_test.dart`) confirms the refactor didn't change `FlowCard`'s
behavior.

**`AgentImage` fetches through `dio`, not `Image.network`** — the images endpoint is bearer-token
gated (same auth as every other agent call), and `Image.network` has no way to attach one. A
`FutureProvider.family<Uint8List, (String key, int? width)>` does the fetch and lets Riverpod's own
caching avoid re-requesting a key already seen at a given width, rather than building a bespoke
image cache.

**Found only by the new `live_layout_test.dart`, not `flutter analyze`** (D19's overflow-is-
paint-time lesson, again): `AgentImage`'s "image unavailable" placeholder (icon + label) overflowed
when shown at the classify surface's 1080:198 row-crop aspect ratio sized to a card thumbnail —
~18px tall, nowhere near enough for icon + spacing + text at their natural size. Every other surface
happened to use taller aspect ratios and never triggered it, which is exactly why a real widget test
matters here rather than eyeballing one or two surfaces. Fixed with `FittedBox(fit:
BoxFit.scaleDown)` around the placeholder's `Column`. Seven new test cases target the same
"unbounded-length real string in a fixed-width pane" shape `flows_layout_test.dart` established: a
60-character username, a 40-character no-space digit run standing in for a pathological detail
string, and six counters shown at once.

**Verified:** `flutter analyze` clean, `flutter test` 23/23 (16 prior unchanged + 7 new). No flow
ran live during this session, so the log console (works today — CP 4.1's tailer reads Prefect's own
execution log, no pipeline-side dependency) and the visualization surfaces (need CP 4.3's `emit()`
calls actually deployed to the live pod, which hasn't happened) are both left for a real end-to-end
check once something runs.

**Corrected after your live test, same session: `_LogLine`'s original rendering was hard to read.**
The first version packed level + message into one `RichText` span with 1px of vertical padding
between lines, everything in monospace, the level shown as inline colored text rather than a
badge — dense in a way that read fine to me reviewing the code but not in the running app with a
real 62-line scrape log. You compared it against Prefect's own log view as the "too far the other
way" reference point — not asking for that level of chrome (no task-run sidebar links), just real
readability. Rebuilt as a row: a fixed-width timestamp, a colored level *pill* (background tint +
bold text, not inline color), and the message in the theme's normal body font at 1.4 line height —
monospace dropped entirely, since these are prose log lines, not aligned tabular data. Scheduler-
sourced lines (D30) keep a visual distinction but as a muted left border accent instead of italics,
which was adding strain rather than clarity. Also surfaced during this same live test: the
scheduler pod's `IA_AGENT_URL not found in config.env` warning, visible for the first time only
because D30's merge exists now — not a new occurrence (it's fired on every heartbeat since CP 3.4/
D28), just newly observable. Fixed at the source by writing the coded default
(`http://172.19.16.1:8787`) into the real `config.env` directly, since `IA_AGENT_URL` is
deliberately excluded from the app's config schema (D26) and has no UI path to set it.

---

## 2026-08-01 — Phase 4 implementation session (CP 4.1, log aggregation)

### D30 · Flow-run log tailing: heartbeat-first discovery, per-run rings, scheduler-pod lines merged by append order

**Chosen:** `ia_agent/flowruns.py`'s `FlowRunTailer` ticks every `TICK = 1.0`s. Active-run
discovery (ARCHITECTURE §5.2) checks the scheduler mirror first — any flow whose heartbeat reads
`phase == "running"` hands over `last_run.id` directly, since `Deployment._last_run` (pipeline
side, CP 3.2) already carries the in-progress run's real id regardless of state, no pipeline change
needed. Falling back to Prefect's own `flow_runs/filter` (state type `RUNNING`, filtered to the five
deployment ids resolved once and cached) only fires when the mirror is offline or reports nothing
running — the gap right after an agent restart, before any heartbeat has landed.

Each tracked run gets its own `Ring` (structured entries: `seq`, `ts`, `source`, `level`, `task`,
`message`), polled via `POST /logs/filter` with `timestamp.after_=<cursor>` — exclusive, so the
same-timestamp boundary is deduped by log `id`, not by timestamp, since two rows in one tick
legitimately share a timestamp. `task_run_id` → task name is resolved once per id and cached
process-wide (`GET /task_runs/{id}`), not per row.

**The scheduler pod's container log (where trigger/gate decisions print, not inside any flow run)
is merged by writing its lines directly into every currently-active run's ring**, in the order
observed — not by a timestamp-sorted interleave with a separate seq space. This reuses D18's
already-accepted precedent exactly: a ring's `seq` means "the order this was appended," and replay
correctness follows from that, not from wall-clock ordering. The alternative (merge-at-read-time by
sorting two independently-seq'd streams by `ts`) would need seq to be reassigned per request, which
breaks the "since= means resume, never re-see, never gap" contract every other channel in this repo
holds. A concurrent-flows edge case exists (two flows "running" at once both get every scheduler
line) — accepted as harmless duplication rather than engineered around, since it is rare.

A run that leaves the active set is still polled for `FINISHED_GRACE = 5.0`s to catch trailing log
lines (Prefect's own log-write lag is a few hundred ms, not zero), then frozen — replayable via
`?since=` forever after, but no longer costing an API call every tick. `RETENTION_RUNS = 20`: oldest
*inactive* ring is evicted once exceeded; an active run is never evicted regardless of count.

**REST** (`api/flowruns.py`): `GET /api/flow-runs?limit=` always asks Prefect directly (cheap, one
POST, always authoritative) rather than only listing what this agent happened to tail, annotating
each row with `active` from the local tailer. `GET /api/flow-runs/{id}/logs?since=` replays the
local ring (`live: true`) when one exists; a run this agent never tailed — from before this agent
started, or one that finished without ever being "active" while it was up — gets a one-shot fetch
straight from Prefect instead (`live: false`, real content, no further updates). **WS**:
`flowrun.logs`, one channel, every new entry tagged with its `flow_run_id`/`flow` — matches D6's
existing "the app filters by channel and payload, not per-run subscriptions" shape.

**Measured, not reasoned — the installed `kubernetes` client's `read_namespaced_pod_log` silently
drops `since_time`.** ARCHITECTURE §5.2 assumed an absolute cursor; live against the real cluster,
passing `since_time` raised `ApiTypeError: unexpected keyword argument` — the generated Python
bindings for this endpoint never wired that parameter up at all (a known gap in the client, not a
server limitation: the k8s API itself accepts it fine). Switched to `since_seconds` (relative),
computed each poll from `time.time() - cursor`, with the caller re-filtering the returned window
against the exact parsed timestamp — the same "trust nothing about the boundary, dedupe yourself"
shape `run_logs` already needed for its own `after_` cursor.

**Also measured: this client version hands back `str(bytes)` for this one endpoint** — the literal
characters `b'2026-08-01T...'`, not real bytes and not decoded text — rather than the plain string
every other call in `integrations/kube.py` gets. `_decode_pod_log` detects the `b'`/`b"` prefix and
`ast.literal_eval`s it back before decoding UTF-8; every other kube.py function was unaffected and
left alone.

**Verified:** `agent/tests/test_flowruns.py` (36/36) — `Ring` seq/replay, both discovery paths,
per-run polling (boundary dedup, task-name caching, level mapping), scheduler-pod merge scoped to
active runs only, eviction protecting active runs, and a live app exercising every REST endpoint
plus a real `flowrun.logs` WS delivery — all with `prefect`/`kube` module functions monkeypatched,
same convention as `test_scheduler.py`'s `build_specs` swap. `agent/tests/check_flowruns.py` (new,
read-only) then ran the *real* functions against the live Prefect server and k3s cluster — resolved
all five deployment ids, listed real recent flow runs, fetched real logs for one and resolved a real
task name, and tailed the real scheduler pod's container log end to end, which is what caught both
`since_time` and the bytes-repr quirk above; nothing it touches is capable of starting, stopping, or
otherwise mutating a flow run, pod, or service. All five prior suites unchanged: 71/71, 32/32,
26/26, 24/24, 20/20. `test_ui_contract.py`'s `terminal_available` `KeyError` reproduces identically
on a clean `main` with none of this session's changes applied (confirmed via `git stash`) — a
pre-existing issue, not a regression from this work, and out of scope for this checkpoint.

### D31 · Flow-event images are cached by content hash, not by source path; events are a loose dict like the heartbeat

**Chosen:** `ia_agent/images.py`'s `cache(rel_path)` keys the cached bytes by `sha256(data)`, not by
`rel_path` — two events pointing at byte-identical files (a duplicate scan hit is the obvious case)
share one cache entry instead of two, and the key stays meaningful forever even though the source
path is usually gone within moments (`entity_classify` unlinks public profiles, `entity_follow`
unlinks right after acting — ARCHITECTURE §5). A missing source file is not an error: `cache()`
returns `None` and `EventStore.record()` still records the event with `image_key: null`, because
the event itself (a verdict, a counter, a reason string) is worth keeping even when the image race
was lost — losing the picture should never mean losing the fact.

**`POST /api/events` accepts a loose dict, not a validated `FlowEvent` pydantic model** — the same
choice `SchedulerMirror.heartbeat` made (D26/D27's precedent). `emit()` (CP 4.3, not yet built) is
fire-and-forget with a 1s timeout and doesn't read the response; a 422 from strict validation would
be a silently dropped event with nobody positioned to notice, so the agent takes whatever shape it's
given and fills in `seq`/`id`/`ts` only when the caller left them out.

**Thumbnails are generated lazily per requested width and cached alongside the original**, not
pre-rendered at a fixed set of sizes on ingest — most cached images are never viewed at every width
the UI might eventually ask for, and ingest-time is exactly when the agent is racing a flow's
`unlink()` call, so doing only the minimum (copy the bytes) there and deferring resize work to first
view keeps that race as short as possible.

**Verified:** `agent/tests/test_events.py`, 35/35 (identical content → identical key, different
content → different key, the missing-file race, thumbnail proportions and width clamping, replay,
and a live app round-trip including a real WS delivery) — see PLAN.md CP 4.2 for the full count.

---

## 2026-08-01 — Phase 4 implementation session (CP 4.3, flow instrumentation, `Insta-Automate`)

### D32 · `emit_sync` blocks for real; a fire-and-forget `create_task` would have lost the image race it exists to win

**Chosen:** `tasks/ollama.py`'s `remove_public`/`gender_classify` are the only two ARCHITECTURE §5.1
call sites that are plain sync functions rather than `async def` — every other instrumented site
(`tasks/ia.py`, all five flow bodies) can just `await AgentClient().emit(...)` inline. The first
version of `controllers.agent.emit_sync` used `asyncio.get_running_loop().create_task(...)` to
fire-and-forget from sync code without blocking it, on the reasoning that both functions are always
called from inside an already-async flow body, so a running loop always exists to schedule onto.
**That reasoning was correct and the design was still wrong**: `remove_public` calls
`entity.unlink()` and `gender_classify` calls `move(entity, ...)` on the *very next line* after the
classification, inside a `for` loop that never once yields back to the event loop until the whole
function returns. A task scheduled with `create_task` doesn't get a turn to run until then either —
so by the time any of those scheduled event-emission coroutines actually executed, every public
profile in the batch had already been unlinked and every classified image already moved. This is
exactly the race `images.cache()` (D31) exists to win, defeated by the very code meant to feed it.

**Fixed: `emit_sync` makes a real, blocking `httpx.post(...)` call**, synchronously, before returning
control to the caller — a module-level function, not an `AgentClient` method, since it needs no
persistent connection (one request per call, immediately). This guarantees the agent has read the
image bytes before `unlink()`/`move()` runs on the next line, at the cost of one blocking HTTP
round-trip per classified image — negligible next to the AI inference call the same loop iteration
already makes. Same failure-swallowing contract as `AgentClient.emit`: any exception (agent
down, endpoint doesn't exist, network blip) is caught and discarded, never allowed to break a
classify run.

**Also found and fixed while verifying this against a real Prefect server**: CP 4.1's
`ia_agent/integrations/prefect.py` `run_logs()` defaulted to `limit=500`, and `flow_runs_filter()`
would silently accept any caller-supplied `limit` too — but Prefect's `/logs/filter` and
`/flow_runs/filter` both 422 above `limit=200` (`"Invalid limit: must be less than or equal to
200."`). CP 4.1's own test suite never caught this because its Prefect calls are monkeypatched
fakes with no such constraint, and the live `check_flowruns.py` run at the time happened to pass an
explicit small `limit=`. The failure mode was silent in production too: `FlowRunTailer._tick()`
catches every exception per-tick and logs it, so a real active run's logs would simply never tail —
no crash, no visible symptom beyond an empty log console. Fixed with a shared
`MAX_FILTER_LIMIT = 200` clamped inside both functions, so every caller (present or future) is
protected regardless of what limit it asks for.

**Verified:** import sanity-check on every changed `Insta-Automate` module (no test suite exists in
that repo — same precedent as CP 3.1/3.2, verified by direct call instead). A live round trip against
a throwaway `ia-agent` instance: `AgentClient.emit` (async) and `emit_sync` (blocking) both pointed
at it via monkeypatched `Config.get`/`controllers.agent.IA_AGENT_TOKEN` (the latter had to be patched
on the *importing* module, not `insta_automate.vars` — a from-import binds its own copy of the name,
the same reason `ia_agent/images.py`'s test monkeypatches its own module's `IA_DIR`, not
`ia_agent.vars.IA_DIR`), both confirmed to land on `POST /api/events` and read back correctly from
`GET /api/events`. The limit-clamp fix was verified directly against the real Prefect server at its
old failing size, then passing; `agent/tests/test_flowruns.py` (36/36) unaffected.

**Corrected same session, before any UI consumed it:** every `emit()` call's `flow` field used
`entity_scan`-style underscores at first, matching ARCHITECTURE §5's literal comment
(`flow: str  # entity_scan | entity_classify | …`). But the scheduler heartbeat and flow-runs API —
both already shipped and already read by the Flutter app (`flowOrder` in `scheduler_models.dart`) —
use hyphenated names (`entity-scan`), an arbitrary string chosen in `Deployment("entity-scan")`
independent of Prefect's own (underscored) flow-function name. Building the Live screen means
joining `flow.events` against `flows.state`/`flow-runs` data by flow name, so two conventions for
the same identifier would force string-translation at every join for no benefit. Re-hyphenated every
`emit()` call (`tasks/ia.py`, `tasks/ollama.py`, all five flow bodies) to match the already-embedded
convention instead — cheaper to fix now, before any downstream code depends on the wrong one, than
to discover it while building CP 4.4.

---

## 2026-07-31 — Phase 3 implementation session (CP 3.5, Flows UI)

### D29 · `force_run` bypasses the rate gate and the switch, never the no-work gate; `pause`/`resume`/`reload_config` stay unwired

**Chosen:** `Prefect` gained `self._commands: dict[str, list[str]]`, `_consume`/`_pending`
(pop-once vs. peek), and `_trigger_gate(force)` (`controllers/prefect.py`). `heartbeat_loop`
(D28) now actually queues the commands it receives instead of just logging them. `wait_until`
(D25) treats `skip_wait`/`run_now`/`reload_config` identically — all three just mean "wake this
wait now instead of at the deadline" — consuming whichever arrives and returning its name instead
of `"elapsed"`. `force_run` is handled per gate site instead: one `force =
self._consume(flow, "force_run")` per loop iteration, reused everywhere that iteration's gate is
checked (`and not force` on a day-limit check, `or force` on a no-work/backpressure check).
`wait_day_change` gained a **peek** (`_pending`, not `_consume`) so a `force_run` arriving while
already inside a day-pause unsticks it without the command being silently consumed before the
outer loop's trigger branch ever sees it.

**The bypass rule: force skips *rate* gates and the switch, never a *no-work* gate.** A day-limit or
backpressure gate is pure rate-limiting — bypassing it is exactly what "force" should mean. A
no-work gate (nothing queued) is a hard constraint — `entity-scan` needs a real queued `Entity` to
supply the `url` parameter, `entity-follow` needs real files in `follow_queued/`, so force can't
manufacture either and those checks are untouched. `entity-ingest`/`entity-classify` have no such
parameter requirement (they just re-check their own directory/Telegram state at run time), so their
no-work gates *are* force-bypassable — a forced trigger with nothing new just completes
immediately, which is harmless.

**Corrected after your first live test: force also bypasses the switch.** The original version of
this decision left the `ENTITY_*` switch untouched by any command, reasoning that force overrides a
rate limit, not an explicit "don't run this." You tested it and disagreed — "the toggles are only
for auto runs, force run should always run irrespective of toggle" — so `Deployment.trigger()` gained
a `force: bool = False` parameter; `if not self.switch() and not force: return` replaces the old
unconditional switch check, and every trigger-loop call site now passes its own `force` through
(`entity_ingest_trigger` needed a `force` parameter threaded in too, since it's called from both the
timer loop and the live Telegram handler — only the timer loop's forced calls pass `True`). A
switched-off flow now really does run when forced, logging that it's doing so.

**`pause`/`resume`/`reload_config` are validated at the agent's REST layer (`KNOWN_COMMANDS`, CP
3.4) but deliberately not wired into the pipeline.** Nothing in the Flows UI has a button for them —
the CP 3.5 plan text and manual test only call for Run now / Force run / Skip wait — so wiring
pause/resume handling now would be dead code with no caller. Whoever adds a Pause button later
wires it the same way `force_run` is wired here: peek/consume against `self._commands`.

**"Run now" and "Skip wait" are one interrupt, not two buttons.** The plan bullets say "Run now"
and "Force run"; the manual test says "press Skip wait." Reconciled by making the Flows card's
first button send `skip_wait` and relabel itself — "Run now" when idle, "Skip wait" when
`phase == "waiting"` — since `wait_until` treats both commands identically anyway.

**Verified without any live Telegram/DB/device/Instagram call** (flow switches are live —
firing a real flow during a test was not acceptable): `Prefect.__new__(Prefect)` skips `__init__`
entirely (no `IaTelegram`/`IaSession`/`AgentClient` construction), then `_consume`/`_pending`/
`_trigger_gate`/`wait_until`/`wait_day_change` are exercised directly with short-circuited `Config`
overrides — mirrors CP 3.2's own verification technique for `wait_until`. All pass: normal elapse is
unchanged when no command is queued, `skip_wait`/`run_now`/`reload_config` each wake `wait_until`
early and are consumed exactly once, `wait_day_change` returns on a pending `force_run` without
consuming it, and the per-flow force-bypass boolean conditions match the table above.

**Flutter side** (`app/lib/features/flows/`, `core/scheduler_models.dart`): `FlowsController`
mirrors `ServicesController`'s shape but replaces the whole snapshot on every `flows.state` event
rather than patching by name, since the channel already publishes the full picture (D27). The
countdown ring's proportional fill needs a "started at" the state block doesn't carry (only the
deadline) — tracked client-side, reset whenever `next_trigger_at` changes, which is what makes a
mid-wait `FOLLOW_WAIT` edit or a `skip_wait` re-target the ring immediately rather than jumping.
"Jump to its logs" opens `http://localhost:4200/flow-runs/flow-run/<id>` in the browser via a new
`FileOpener.openUrl` (same `ShellExecute` call already used for files) — CP 4.1's in-app log viewer
doesn't exist yet, and Prefect's own UI already has the real logs for that run. The switch-disable
confirmation dialog (`_disableConsequence` + the dialog itself) moved out of `switches_tab.dart`
into `core/flow_switch_confirm.dart` so the Settings tab and the Flows card share one copy instead
of forking the consequence text.

**Found by `flutter test`, not `flutter analyze`** (same class of bug as D19/CP 2.4 — overflow is
paint-time): `FlowCard`'s `Card` needed `margin: EdgeInsets.zero` (Material's default 4 px margin
was invisible in the mental model of the card's fixed 360 px width) and the Run now/Force run
button pair needed to become a `Wrap` instead of a bare `Row` — two `OutlinedButton`s at their
natural width came within a couple of pixels of the card's content width, which is exactly the kind
of thing a fixed-width card doesn't get a second chance to reflow out of. `test/flows_layout_test.dart`
(4 cases, one fixed viewport since — unlike the Services detail pane — this card's width doesn't
depend on window size at all) pins both fixes.

**Also found in your first live test: Force Run fired the deployment, but `entity-follow` itself
still refused to follow anyone and sent its own "limit reached" notification.** `force_run`
(this decision, above) only ever bypassed the *trigger loop's* gate — the flow body it triggers,
`flows/entity_follow.py`, independently re-checks `Follow.fetch(session).limit_reached` and breaks
its own loop immediately if the cap is already hit, which it still was (force doesn't touch the DB
counts, only whether the trigger loop calls `run_deployment` at all). Same shape in
`flows/entity_scrape.py`. Both flows gained a `force: bool = False` parameter; the loop conditions
became `(limit_reached and not force)` / `(force or not limit_reached)`, and the day-cap Telegram
notification is now skipped (logged instead) when `force` is set — the whole point of forcing was to
override that constraint, so re-notifying about it is noise, not signal. `entity-scan` needed no
equivalent fix — it only checks `limit_reached` *after* processing its one entity, purely to decide
whether to notify, so it was never gated by the flow body at all. `entity-ingest`/`entity-classify`
have no daily cap. `controllers/prefect.py`'s `entity_scrape_trigger`/`entity_follow_trigger` now
pass `parameters={"force": force}` alongside the existing `force=force` (switch bypass) — two
different mechanisms at two different layers (control-plane trigger vs. flow-body execution), both
needed.

**Discovered while fixing that: flow *bodies* deploy from the git remote's default branch, not
whatever's baked into the image.** `IaFlows.deploy_all()` uses Prefect's `GitRepository(url=GIT_URL)`
storage — the worker clones flow source fresh from git **at run time**, on every flow run, entirely
independent of what `ia build` baked into the image from the checked-out branch. `controllers/
prefect.py` (the trigger loop) is part of the *installed package*, so it picked up `feat/
control-center` correctly when the image was rebuilt from that checkout — but `flows/entity_follow.py`
never would have, no matter how many times the image was rebuilt, because `GitRepository` with no
`branch` clones the remote's default branch (`main`). This had never come up before this session
because no earlier CP touched a `flows/*.py` file. Fixed with a new `GIT_BRANCH` env var
(`vars.py`, empty by default = today's behavior unchanged) threaded into
`GitRepository(url=GIT_URL, branch=GIT_BRANCH or None)` — set via `kubectl set env` on the live
`insta-automate` deployment only for this testing session (same imperative, easily-reverted pattern
as `IA_AGENT_TOKEN`), never baked into the image or committed as a standing override. Once the
control center is accepted and `feat/control-center` merges to `main`, this stops mattering — the
default branch *is* the deployed one again.

**Also found in your first live test: nothing edits `FOLLOW_WAIT` (or any of the other ten trigger
timings) anywhere in the app.** CP 3.1 added them all to `Config._DEFAULTS` on the pipeline side, but
the agent's `config/schema.py` — the only thing `GET/PATCH /api/config` and the Settings > Limits tab
actually know about — never got them, so they were readable only by hand-editing `config.env`. Fixed
by adding a `ConfigGroup.TIMING` and all eleven timing keys plus `SCRAPE_RESERVE_FACTOR` to
`SCHEMA`, and adding `'timing'` to `limits_tab.dart`'s `_groupOrder`. Nothing else needed to change —
`PATCH /api/config`'s limits handling was already generic over any `ConfigType.INT` schema key (the
four cross-checks reference specific keys by name and don't iterate the rest), and `LimitCard` is
already generic over any `ConfigKeySchema`. The whole fix was two data additions, no new plumbing.

**Second round of live-test feedback, same session:**

- **`SCRAPE_BACKPRESSURE_FACTOR` renamed to `SCRAPE_RESERVE_FACTOR`.** Your framing — "if follow is
  60/day, reserve is 180 (60×3); if scraped+follow_queued matches that we're good" — is a clearer
  read of what the number means than "backpressure," so the config key, its `SCHEMA` help text, and
  ARCHITECTURE §4.1 all changed. Nothing had persisted the old name to any live `config.env` yet
  (still resolving to the coded default), so this was a pure rename, no migration.
- **`LimitCard`'s header row could overflow** — exactly this key, whose new name is still 21
  characters. The name `Text` had no width constraint before the fixed-width value field, so a long
  enough key pushed the field outside the card (visible in your screenshot: the number box sitting
  outside the card border). Now wrapped in `Expanded` + `Tooltip` + ellipsis, the same shape of fix
  as the gate-detail text elsewhere — a card of fixed width can't get a second chance to reflow out
  of an overflow, so anything of unbounded length inside one needs this treatment on sight, not just
  where it's already been caught once.
- **The "Triggering" phase label was live for the entire run, not just the moment of triggering.**
  `Deployment.trigger()` calls `await self.log_status()` by default (`wait=True`), which blocks until
  the flow run reaches a terminal state — so `_set_state(flow, phase="triggering", ...)`, set once
  right before that call, was the only phase update for the run's *entire* duration (your Follow
  example ran 116s). Renamed the phase value itself to `"running"` everywhere it's set — accurate for
  what it actually describes for that whole span, not a relabel of a genuinely momentary state.
- **Maximized-mode title bar showed doubled/ghosted window buttons.** Root cause: Windows redraws its
  own caption chrome under/over this app's custom-drawn minimize/maximize/close icons only when the
  window is in true OS-maximized state (a known interaction between `window_manager`'s hidden title
  bar and Windows 11's non-client rendering — restored mode is unaffected, matching what you saw).
  Fixed at the app level rather than patching the plugin: `_WindowButtons` (`shell/title_bar.dart`)
  no longer calls `windowManager.maximize()`. It fakes it via `setBounds` to the monitor's real work
  area, read directly from Win32 (`core/window_work_area.dart` — `GetMonitorInfo`'s `rcWork`, the same
  "reach into Win32 when the Dart wrapper falls short" reasoning as `FileOpener`'s `ShellExecute`
  calls, D5) so the window never actually enters the state that glitches. Tracks `_maximized` locally
  and the restored bounds to reverse it; a `WindowListener` keeps that flag in sync if something
  external changes the real maximize state. **Known gap:** OS-level maximize gestures that don't go
  through this button — Win+Up, dragging to the screen's top edge, the taskbar's own right-click menu
  — still invoke genuine Win32 maximize and can still glitch; intercepting those would need native
  platform-channel work, out of scope here. Unverified by me — I can't hover/click the app myself
  (rule 5) — this is reasoned from the screenshot and the "restored is clean, maximized isn't" split
  you described, not confirmed against a running window.

**Third round: Force Run's disabled state contradicted your actual mental model of it.** It was
built disabled whenever `gate.ok == true`, on the reasoning that Skip Wait already covers "nothing's
blocked, just wake the timer." Your framing corrected that: there are only two kinds of trigger —
*scheduled*, which always respects every condition, and *manual*, which should run and complete its
task regardless of anything, full stop. Force Run is the manual one, so it should never be
conditionally unavailable. `FlowCard._forceRun` (`flow_card.dart`) is unconditionally enabled now; the
confirmation dialog adapts its wording to whether there's actually a gate to bypass, a generic "runs
immediately, ignoring schedule/switch/limits" when there isn't. One honest caveat stayed: for
`entity-scan`/`entity-follow` specifically, a `no_work` gate means there's no queued entity or file to
act on at all — force can bypass every *condition* but can't invent input that doesn't exist — so the
dialog says so up front instead of the button silently doing nothing.

**Fourth round: two real bugs, both in `wait_until`, both from the same root cause — force_run and
the countdown ring only ever interacted with the gate, never with the wait itself.**

1. **Force Run silently did nothing on Follow after repeated tries, but worked on Scrape.**
   `force_run` was only ever consumed at the *top* of each trigger loop's outer `while`, never inside
   `wait_until`'s own tick loop. Press it while a flow is mid-wait and the command sits queued,
   unread, until that `wait_until` call returns on its own — for Scrape that's usually the 10s
   `SCRAPE_BUFFER`, easy to miss; for Follow it's `FOLLOW_WAIT`, up to 1200s. Every attempt you made
   landed during that long wait, so nothing visibly happened. `wait_until` now peeks (`_pending`, not
   `_consume` — same reasoning as the `wait_day_change` peek above) for a queued `force_run` every
   tick and wakes early, returning `"force_run"`; the trigger loop's own `_consume` still has to see
   it afterward to actually bypass the gate. This was latent for every flow, not Follow-specific —
   Ingest's 600s `INGEST_POLL_WAIT` had the same exposure, just less likely to be caught mid-wait in
   testing so far.
2. **Every countdown ring reset to a full circle every ~`TICK` seconds (default 5).** `wait_until`
   recomputed `deadline = datetime.now() + timedelta(seconds=target - elapsed)` from scratch on every
   tick. Mathematically that lands within a few milliseconds of the same instant each time — but
   never *exactly* the same `DateTime`, and the Flutter side's countdown-ring baseline
   (`FlowsController._deadlineObservedAt`) resets whenever `next_trigger_at` changes at all, by exact
   equality. So a wait that hadn't actually been re-targeted still looked re-targeted every tick,
   snapping the ring back to full. `deadline` is now a stable value held across ticks, only
   recomputed when `Config.get(key)` actually changes — an untouched wait now broadcasts the
   byte-identical instant every time, so nothing changes client-side until something real does.
   CP 3.2's original "re-targets within one TICK" behavior for an actual edit is unaffected (verified
   in isolation — see below), and this is also strictly better for `flows.state` traffic, since
   `SchedulerMirror.broadcast_if_changed()` (D27) was re-broadcasting on that same tick-boundary
   jitter for every waiting flow, every ~5s, whether anything real had changed or not.

**Verified in isolation, same technique as every round before this** (`Prefect.__new__`, no
Telegram/DB/device/Instagram calls): a pending `force_run` wakes `wait_until` early without consuming
it; `next_trigger_at` stays identical across ticks when the target is unchanged; an edit mid-wait
still re-targets the deadline correctly. One methodology note for whoever runs this script again:
by this point `config.env` has real explicit values for `TICK`/`FOLLOW_WAIT`/etc (you'd exercised the
new Timings tab), so overriding `Config._DEFAULTS["TICK"]` in the test no longer has any effect —
the file value wins, same as production. The tests still pass correctly, just slower (real 5s
ticks instead of the intended fake ones) — not a bug, just worth knowing next time.

**Fifth round: optimistic UI feedback for command buttons.** Even with the bug-1 fix above, there's an
unavoidable real gap between a command being queued and its effect being visible — the worker still
has to pick up the run, and the card only updates on the next `flows.state` broadcast. Long enough
that a second click was tempting. `flows_controller.dart` gained `PendingCommandNotifier`
(`pendingCommandProvider`): `FlowsController.sendCommand` marks the flow pending *before* the POST
resolves, capturing its current `phase`/`gate.reason` as a baseline. A flow clears as soon as a
`flows.state` snapshot shows that baseline actually changed (real confirmation, not just "a broadcast
happened" — the signature that gates a broadcast, D27, is global across all five flows, so an
unrelated flow changing must not clear this one), or after a fixed 8s timeout regardless, checked by
elapsed time rather than requiring another event, so it self-heals if the agent goes quiet mid-flight.
`FlowCard` swaps the Run now/Skip wait/Force run buttons for a small spinner + "Command sent…" in that
window — same footprint, no layout jump, and both buttons are unreachable for a second click since
neither renders at all while pending.

---

## 2026-07-31 — Phase 3 implementation session (closing the CP 3.4 gap, real heartbeats)

### D28 · `gate` is set once by the caller; `wait_until` only ever touches `phase`/`next_trigger_at`

**Chosen:** `Prefect` gained `self.flow_state: dict[str, dict]` (no lock — single event loop,
each trigger loop only ever writes its own key, unlike `ManagedService`'s cross-thread need for
`RLock`, D9) and `_set_state(flow, **fields)`, a merge-update. Every trigger loop now sets
`gate` (via a `_gate(ok, reason, detail)` helper) at the exact point it decides whether it's about
to trigger or skip — `backpressure` for scrape with the same `"scraped+follow_queued = N ≥
FOLLOW×F = M"` detail string ARCHITECTURE §4.3 illustrates, `day_limit` for the three day-capped
flows (set inside `wait_day_change`, which now takes an optional `flow` argument), `no_work` for
ingest/classify/scan/follow when their respective queue is empty. `wait_until` (D25) was extended
to set `phase="waiting"` and a recomputed `next_trigger_at` every tick, but **deliberately never
touches `gate`** — the caller's gate reason has to keep reading true for the whole wait that
follows it, not get clobbered back to "ok" the instant the sleep starts. `heartbeat_loop()` (2s,
`Prefect.serve()`) reads `flow_state`, layers in `switch` (`Deployment.switch()`), `today`
(flow-specific: scan gets three sub-counters against `PROFILES`/`REELS`/`POSTS`, scrape/follow get
one each, ingest/classify get `None` — they have no daily cap), and `last_run` (from
`Deployment.flow_run`, `getattr`-defensive since a fresh process has none yet), then calls
`AgentClient.heartbeat()` per flow.

**Verified cross-process**, not just in-process: a throwaway agent instance (`build_specs=[]`,
same pattern `test_scheduler.py`/`test_ui_contract.py` use) spun up on a spare port, and a real
`AgentClient` from the `Insta-Automate` venv (a genuinely separate Python environment — these are
two different `uv` projects, so this could not be one in-process test) posted a realistic §4.3
block against it. `GET /api/scheduler` on the throwaway agent read back the exact gate reason and
detail string, `online: true`. This is the first time data has actually crossed the pod→agent
boundary this phase — CP 3.3 only proved failures swallow correctly, never a real payload landing.
Also verified: a gate set before `wait_until` survives every tick of the wait unchanged.

**Rejected:** having `wait_until` accept the gate as a parameter and set it itself — would force
every call site to pass the *same* gate value it already just decided, for no benefit over setting
it directly; the split (caller decides *why*, `wait_until` only tracks *when*) is what let `gate`
survive across the wait without extra plumbing.

**Why:** this is what CP 3.4 (D27) explicitly left open — a real heartbeat loop was needed before
CP 3.5's Flows UI would have anything true to render.

**How to apply:** command handling is still not wired — `heartbeat_loop()` logs a warning if the
agent ever returns queued commands, but nothing acts on them. That's explicitly CP 3.5's job (D27's
open item), and needs a hook in `wait_until`'s tick loop to check for and short-circuit on a
queued command, returning something other than `"elapsed"`.

---

## 2026-07-31 — Phase 3 implementation session (CP 3.4, scheduler mirror in the agent)

### D27 · `flows.state` publishes the full snapshot on change; staleness needs its own watchdog

**Chosen:** `SchedulerMirror` (`ia_agent/scheduler.py`) — an `RLock`-guarded in-memory store, one
state block per flow, reusing `ManagedService`'s exact locking idiom (D9) rather than inventing a
new one. `heartbeat(state)` stores the block and drains that flow's queued commands in the same
call; `queue_command(flow, command)` is the write side, exposed at
`POST /api/scheduler/{flow}/command` with the six command names (§4.4) validated at the API layer,
400 on anything else. `flows.state` broadcasts the **whole snapshot** (`online`, `last_heartbeat_at`,
every flow's block) on every signature change, not a per-flow delta — mirroring how
`services.status` publishes one *complete* service status per change rather than a diff, which
means a client that missed some broadcasts is never stuck merging partial updates; it just has a
stale full picture until the next one arrives, and `GET /api/scheduler` gets it unstuck immediately.
Staleness (`STALE_AFTER = 15.0`s → `online: false`) needed a **watchdog task** (`WATCHDOG_TICK =
3.0`s) distinct from the heartbeat handler's own immediate broadcast-on-POST, because nothing
about a heartbeat *not* arriving would otherwise trigger a re-check — the supervisor's tick loop
has an equivalent structural role (it re-probes services on its own schedule; a service doesn't
have to tell the supervisor it died).

**Verified:** `agent/tests/test_scheduler.py`, 24/24 — pure store logic (command scoping per flow,
staleness flip, signature-gated broadcast) plus a live REST+WS round trip against a throwaway
`create_app()` instance on a separate port, with `build_specs` monkeypatched to `[]` exactly like
`test_ui_contract.py` so this test's own `Supervisor` never touches the three real services a
production agent may already be supervising. All five existing suites still pass unchanged
(71/71, 32/32, 49/49, 26/26, 20/20).

**Rejected:** per-flow delta broadcasts on `flows.state` — would need the client to merge partial
updates into a local model and handle the "I connected mid-session and have no baseline" case
itself; a full snapshot on every change sidesteps both, at the cost of a slightly larger payload
five small JSON blocks is not a size problem worth solving yet. Also rejected: giving `flows.state`
a `seq`-numbered replay ring like `services.logs.<name>` — that ring exists because a **log** is a
delta stream where a gap is a real loss (D18); a full-snapshot channel has no gap to lose, `GET
/api/scheduler` already *is* the replay.

**Why:** CP 3.4 is marked 🟢 (this repo only) in the plan — deliberately **not** wiring
`Prefect.serve()` to send real heartbeats, which stays open. An earlier note in D26 said CP 3.4
would include that pipeline-side wiring; that was wrong, corrected here. `SchedulerMirror` is
therefore verified against synthetic heartbeats only — nothing in `Insta-Automate` calls
`AgentClient.heartbeat()` yet, so `/api/scheduler` on the real running agent reads `online: false`
until that gap closes.

**How to apply:** the next piece of work needing this is either its own small checkpoint or folds
into CP 3.5 (Flows UI needs real data to render against) — add a `heartbeat_loop()` to
`Prefect.serve()` that builds the §4.3 block per flow (phase from `wait_until`'s state, gate from
each `limit_reached`/backpressure check, `today` from `Scan`/`Scrape`/`Follow.fetch()`, `last_run`
from `Deployment.flow_run`) and calls `AgentClient.heartbeat()` on it every ~2s, draining returned
commands into whatever `wait_until` (D25) checks to stop being `"elapsed"`-only.

---

## 2026-07-31 — Phase 3 implementation session (CP 3.3, agent client in the pod)

### D26 · `IA_AGENT_URL` stays a live `Config` key; only `IA_AGENT_TOKEN` moves to `vars.py`

**Chosen:** `controllers/agent.py`'s `AgentClient` has three methods — `heartbeat(state)`,
`emit(event)`, `notify(msg, ...)` — each POSTing to the agent and swallowing every exception,
returning the documented empty/false value on any failure (`[]`, `None`, `False`). The base URL is
read fresh on every call via `Config.get("IA_AGENT_URL")` (already a live `Config` key since CP
3.1, defaulting to `http://172.19.16.1:8787`), not a new `vars.py` entry — it changes with no pod
restart, same as every other `config.env` key, which is strictly better than an env var for
something that isn't a secret. `IA_AGENT_TOKEN` **is** new in `vars.py` (`getenv`-only, no
`config.env` fallback), because `config.env` is Syncthing-replicated to the phone (§4 intro) — a
bearer token has no business in a file that leaves the machine. `httpx` is now a direct dependency
(was only transitive, via `prefect`) since this repo imports it directly for the first time.

**Verified:** against a genuinely unreachable port (connection refused) — `heartbeat` → `[]`,
`emit` → `None`, `notify` → `False`, no exception escapes. Then against the real running `ia-agent`
on this machine, whose `/api/scheduler/heartbeat` and `/api/notify` don't exist yet (CP 3.4 and CP
6.1 build them) — both 404 and both still swallow cleanly, proving the failure path works
end-to-end against a real server, not just a closed socket.

**Rejected:** the ARCHITECTURE §8 cross-repo table's original sketch of putting both
`IA_AGENT_URL` and `IA_AGENT_TOKEN` in `vars.py` — written before CP 3.1 existed and before
`IA_AGENT_URL` was already a `Config` key. Doubling it into `vars.py` too would create two sources
of truth for the same value. §8 corrected in the same commit.

**Why:** the whole point of Phase 1 and Phase 3 is that `config.env` edits apply live; an env-var
`IA_AGENT_URL` would silently reintroduce a "needs a pod restart" exception to that rule for no
reason — a URL isn't sensitive the way a bearer token is.

**How to apply:** CP 3.4 builds the receiving `/api/scheduler/heartbeat` endpoint agent-side —
*correction, recorded when CP 3.4 landed:* it does **not** also wire `Prefect.serve()` to call
`AgentClient.heartbeat()`; that pipeline-side loop is still open, see D27. CP 4.2/4.3 wire `emit()`
into the flow task instrumentation points. CP 6.1/6.2 build `/api/notify` and the `Notifier` facade
that calls `AgentClient.notify()`. None of that requires touching `agent.py` itself unless the
payload shapes change.

---

## 2026-07-31 — Phase 3 implementation session (CP 3.2, config-driven scheduler)

### D25 · `wait_until` takes a config key, not a resolved seconds value, and gates `continue`

**Chosen:** `Prefect.wait_until(self, flow: str, key: str) -> str` — every hardcoded
`wait`/`buffer`/`sleep` in `controllers/prefect.py`'s five trigger loops now calls it with the
matching `Config` key (`INGEST_POLL_WAIT`, `CLASSIFY_POLL_WAIT`, `SCAN_WAIT`/`SCAN_POLL_WAIT`,
`SCRAPE_WAIT`/`SCRAPE_BUFFER`, `FOLLOW_WAIT`/`FOLLOW_BUFFER`, `TG_KEEPALIVE_WAIT`), and
`wait_day_change` reads `DAY_CHANGE_POLL` the same way. It sleeps in `Config.get("TICK")`
increments, re-reading `Config.get(key)` on every tick — the loop condition itself
(`elapsed < (target := Config.get(key))`) is what lets an edited delay shorten or lengthen a wait
already in progress. `SCRAPE_BACKPRESSURE_FACTOR` replaces the hardcoded `* 3` in
`entity_scrape_trigger`'s gate. The three day-limited loops (`entity_scan_trigger`,
`entity_scrape_trigger`, `entity_follow_trigger`) now `continue` immediately after
`wait_day_change()` returns, so the next iteration re-fetches `Scan`/`Scrape`/`Follow` fresh and
re-evaluates the gate before doing anything else, rather than falling through into that same
iteration's trigger logic on the pre-rollover object.

**Rejected:** `wait_until(self, flow: str, seconds: float)` as ARCHITECTURE §4.2 originally
sketched it — a resolved `float` is a snapshot; re-reading a snapshot re-reads nothing. Only
passing the *key* lets each tick go back to `config.env` itself. Also rejected: publishing a
countdown and checking for `run_now`/`skip_wait` commands inside `wait_until` now — no command
queue exists to check yet (that's CP 3.3's `AgentClient` and CP 3.4's heartbeat endpoint), so
`wait_until` always returns `"elapsed"` for now rather than a half-built command-check against
nothing. ARCHITECTURE.md §4.2 updated to match the real signature and note what's still missing.

**Why:** the plan's own CP 3.2 bullets ask for both "re-reads config" (needs the key) and
"SCAN_WAIT cooldown, default 0 = today's behaviour, no-op until set" — verified: `SCAN_WAIT=0`
makes `elapsed < target` false on the first check, so the wait returns immediately, identical to
today's absence of a scan cooldown.

**How to apply:** CP 3.3/3.4 extend `wait_until`, they don't replace it — add a command-check hook
(e.g. drain a queue `Prefect` owns) that short-circuits the `while elapsed < target` loop and
returns a reason other than `"elapsed"`, and a countdown publish call inside the same loop body.
Don't reintroduce a `seconds` parameter anywhere in this path.

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
