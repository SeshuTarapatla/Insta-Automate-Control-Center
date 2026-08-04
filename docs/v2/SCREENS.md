# v2 — Screen re-architecture

What each screen becomes, and why. Read [AUDIT.md](AUDIT.md) for the problems these solve
and [COMPONENTS.md](COMPONENTS.md) for the vocabulary used throughout.

**The design target is a tall, medium-width window.** `main.dart` sizes the app to fill the
space right of the scrcpy mirror — roughly **1250 × 1400 logical px** on this machine.
That is unusual: taller than it is wide. Several decisions below (the vertical flow
pipeline, the Live screen's stacked split) exist specifically because of it, and are marked
as such. A screenshot at the real size is the single highest-value input the user can
provide — see [VISUAL_INPUTS.md](VISUAL_INPUTS.md).

---

## 0. Shell — title bar and navigation rail

### Title bar (40px → 44px)

Today: an app icon, a title string, a `_StatusChip` reading the literal text
`'Agent: connected'`, a help button, the notification bell, window buttons
(`title_bar.dart`).

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ ◈  Insta-Automate    ●agent ●k3s ●pg ●prefect ●device   ⌘K  ?  🔔3   ─ □ ✕ │
└──────────────────────────────────────────────────────────────────────────────┘
```

- **The status cluster replaces the text chip** (AUDIT §15). Five dots — agent, k3s,
  postgres, prefect, device — each a `StatusDot` with a rich tooltip naming the component
  and its latency. Roughly the same width as today's single `'Agent: connected'` label,
  carrying five times the information, and it turns the title bar into a genuine always-on
  health indicator. Data already exists: `connectionProvider` plus
  `dependenciesControllerProvider`.
- **⌘K** opens the command palette (§8). Shown as a button so it's discoverable, not just a
  hidden shortcut.
- The window buttons and the faked-maximize workaround (`title_bar.dart:93-98`) are
  **carried over unchanged** — that's a real Win32 glitch workaround, not styling.

### Navigation rail

Today: `NavigationRail` with `labelType: all`, no badges, no shortcuts, no grouping
(`app_shell.dart:89-100`).

```
┌────────────┐
│ MONITOR    │   ← group label, micro role, tokens.content.tertiary
│ ◉ Overview │
│ ○ Flows  ②│   ← CountBadge: 2 flows blocked
│ ○ Live     │
│            │
│ OPERATE    │
│ ○ Services①│   ← 1 service unhealthy
│ ○ Library  │
│  ⚑ Review ⑨│   ← NEW sub-item: jumps straight into review mode
│            │
│ ANALYZE    │
│ ○ Insights │
│ ────────── │
│ ○ Settings │   ← pinned to the bottom
└────────────┘
```

- **Grouped** with `micro`-role labels. Seven flat items with no hierarchy is the shape of a
  demo app; three named groups is the shape of a tool.
- **Badges** (`CountBadge`) — blocked flows, unhealthy services, unread notifications,
  pending review count. This is what makes the rail worth glancing at rather than merely
  clicking.
- **`Ctrl+1..7`** to jump to any destination. Registered app-wide alongside the existing
  `?` binding (`app_shell.dart:74`), which is currently the app's only app-wide shortcut.
- **Collapsible** to icons-only (`Ctrl+B`), persisted. On a 1250px-wide window the rail's
  ~88px matters.
- **Review** as a sub-item under Library is deliberate: it's the app's highest-frequency
  action and it deserves to be one click from anywhere.

### Page transitions

`app_shell.dart:107-115`'s bare `switch` gets wrapped in `PageTransition` — a 240ms fade +
8px vertical slide (`motion.standard`). The comment there about panes being rebuilt rather
than kept alive stays true and stays correct; only the visual swap changes.

---

## 1. Overview — bento mission control

**The problem** (AUDIT §12): Overview embeds five full 360px `FlowCard`s, then two cards,
then five 340px burn-down charts, then two more — about two screens of scrolling, with no
headline. It duplicates the Flows screen rather than summarising it, and nothing on it
answers "does anything need me right now?"

**Bento UI adopted as the layout pattern**, per the theme triage in
[THEMES.md](THEMES.md) §10 — a grid of differently-sized tiles, each answering exactly one
question, all above the fold.

```
┌──────────────────────────────────────────────────────────────────────┐
│  ⚑  2 flows blocked · everything else nominal                        │  ← HERO, full width
│     Scan is over its 1,000 backlog cap · Follow is cooling down       │
│     [ Review 1,204 waiting ]  [ Go to Flows ]                        │
└──────────────────────────────────────────────────────────────────────┘
┌──────────────────────────────────┬───────────────────┬───────────────┐
│  PIPELINE                    2×2 │  SERVICES     1×1 │  DEPS    1×1  │
│  ingest ▸ scan ▸ classify         │  ● adb            │  ●●●●●●●     │
│      ▸ scrape ▸ follow            │  ● vl-server      │  k3s pg pfct │
│  (compact horizontal strip,       │  ● wsl-bridge     │  pods dev net│
│   status dot + backlog per edge)  │                   │  disk        │
├──────────────────────────────────┼───────────────────┼───────────────┤
│  TODAY'S CAPS                2×1 │  CURATION    1×2  │  DEVICE  1×1  │
│  scan-p  ████████░░  184/300     │  gender_valid     │  I2201        │
│  scan-r  ███░░░░░░░   42/150     │      1,204  ⚑     │  ● mirroring  │
│  scan-po ██░░░░░░░░   18/100     │  scraped          │  [ Stop ]     │
│  scrape  ██████░░░░  136/300  ▁▃▅│      191    ⚑     │               │
│  follow  ███░░░░░░░   58/200  ▁▂▃│  [ Review → ]     │               │
├──────────────────────────────────┴───────────────────┴───────────────┤
│  RECENT                                                          3×1 │
│  ● FOLLOW limit reached                                    2m ago    │
│  ● entity scraped: @someone                               14m ago    │
└──────────────────────────────────────────────────────────────────────┘
```

- **The hero tile is the headline the page has never had.** One computed sentence plus, at
  most, two actions. Its `StatusKind` drives the whole tile's `accentEdge`, so the page's
  overall health is legible from peripheral vision. Logic: any service failed or agent
  disconnected → `bad`; any flow blocked, any cap hit, any dependency down → `warn`;
  otherwise → `good` ("All five flows running normally").
- **`FlowCardCompact`** — a new variant, ~140px wide: status dot, name, one-line state,
  no controls. Overview summarises; Flows controls. This is the fix for the duplication.
- **The Curation tile is new** and, I'd argue, the most valuable thing on the page: the two
  human-in-the-loop backlogs (`gender_valid` → `scrape_queued`, `scraped` →
  `follow_queued`) are the pipeline's actual bottleneck, and today they're only visible by
  navigating to Library and reading a folder rail. Data already exists via
  `GET /api/library/folders`.
- **Caps become bars + sparklines**, not five 340px `fl_chart` cards. A cap is a
  ratio-to-a-limit; a progress bar says that in 24px of height where a bar chart takes 200.
  The 7-day `Sparkline` (COMPONENTS §10) keeps the trend signal. Full charts stay on
  Insights, one click away.
- **Grid:** 4 columns at `medium`, 6 at `wide`, 2 at `compact`, with tiles declaring
  `colSpan`/`rowSpan`. Tiles reflow rather than overflow at the 1024px floor.

Every tile header is a `SectionHeader` with a `navIndex`, keeping CP 7.3's
jump-to-the-full-screen behaviour.

---

## 2. Flows — a real pipeline

**The problem** (AUDIT §13): `entity_ingest → scan → classify → scrape → follow` is a
strict pipeline with real backlog queues between stages. The entire logic of
`SCRAPE_RESERVE_FACTOR` (D86) and `SCAN_RESERVE_TARGET` (D91) is about the size of those
queues. The screen renders it as five disconnected cards in a `Wrap`, and shows none of the
queues — they live on a different tab, in the Library folder rail.

**Vertical**, not horizontal — because the production window is tall and narrow
(preamble). A horizontal five-stage diagram would either wrap awkwardly or shrink each
node past usefulness; vertically, each node gets the full width and the connectors read
naturally as flow.

```
╭─────────────────────────────────────────────────────────────╮
│ ●  INGEST                          Checking…      [ ON ]  ⓘ │
│    instant on a new channel message · 10m poll fallback     │
│                                       [ Trigger now ]       │
╰─────────────────────────────────────────────────────────────╯
         │
         │   entities/ queued                              2
         ▼
╭─────────────────────────────────────────────────────────────╮
│ ⧗  SCAN                            Blocked        [ ON ]  ⓘ │  ← warn accentEdge
│    backlog 6,142 / 1,000 cap — public profiles pause        │
│                                       [ Trigger now ]       │
╰─────────────────────────────────────────────────────────────╯
         │
         │   scanned/                                  1,882
         ▼
╭─────────────────────────────────────────────────────────────╮
│ ▶  CLASSIFY                        Running · 00:41  [ ON ] ⓘ│  ← good accentEdge
│    runs when files land in scanned/ · checked every 10s     │
│                                    [ Stop ]  [ Live ▸ ]     │
╰─────────────────────────────────────────────────────────────╯
         │
         ⚑   gender_valid/  →  YOU REVIEW           1,204  ▸
         ▼
╭─────────────────────────────────────────────────────────────╮
│ ◷  SCRAPE                          Cooling 4:12   [ ON ]  ⓘ │
│    scraped 136/300 today                                     │
│                                       [ Trigger now ]       │
╰─────────────────────────────────────────────────────────────╯
         │
         ⚑   scraped/  →  YOU REVIEW                  191  ▸
         ▼
╭─────────────────────────────────────────────────────────────╮
│ ◷  FOLLOW                          Cooling 18:03  [ ON ]  ⓘ │
│    followed 58/200 today · reserve 250                       │
│           [ Trigger now ]  [ Reduce reserve ]                │
╰─────────────────────────────────────────────────────────────╯
```

### What's new

- **Edges carry live backlog counts** from `GET /api/library/folders` (already exists, no
  agent work). This makes the reserve gates *visible* rather than an explanation in a
  tooltip: when `scraped + follow_queued` exceeds the reserve, the edge into Follow shows
  it and turns `warn` — which is exactly the state D86's "Reduce reserve" button exists to
  fix, now sitting right next to it.
- **The two human-review edges are marked `⚑` and are clickable**, jumping straight into
  Library review mode for that folder. This is the first time the app has ever shown that
  the pipeline *waits on the user* at two specific points.
- **Node status is expressed three ways at once** — the icon, the `accentEdge` color, and
  the words — so it survives both a glance and color blindness.

### What is preserved exactly

- **All six `_StatusKind` states** from D84 (`off · running · dayPaused · cooldown ·
  blocked · polling`) and their exact derivation in `_kindOf` (`flow_card.dart:29-38`).
  That distinction was hard-won across two repos and must not be simplified.
- **The countdown ring only for `cooldown`** — D84's central point. In the node layout it
  becomes a compact inline `mm:ss` next to the status word plus a thin determinate progress
  line along the node's bottom edge, rather than a 56px ring. Same information, less
  furniture, same rule: no countdown for any state that isn't a deterministic
  "eligible again at X".
- **The ⓘ tooltip from D93** — mechanism line + raw gate detail — stays, now rendered
  through `AppTooltip(rich: true)` so the gate formula gets monospace and the two blocks get
  real separation. But the *blocked* case now also shows a plain-language reason inline
  (`backlog 6,142 / 1,000 cap`), because "why isn't this running" is too important to be
  hover-only. D93 hid it because the card was cluttered; the node layout has room.
- Every button and its semantics: `Trigger now` (D88), `Reduce reserve` (D86, follow only),
  `Stop` (D69, running only), the confirm dialogs, the optimistic "command sent" state, the
  switch's confirm-before-toggle.
- `View logs` → Prefect becomes a menu item on the node's overflow menu rather than a
  permanent button, freeing the row.

### Expansion

Clicking a node expands it in place (accordion, `AnimatedReveal`) to reveal: last run state
+ duration + run id, today's full counters, the raw gate string, `View logs`, and
`Open in Live`. One node open at a time. This is where the detail that D93 had to hide now
lives — available on click, not on hover, and not competing for space when closed.

---

## 3. Live — the showpiece

**Today**: header row (flow chips + buttons + `DeviceBar`), then a horizontal split — left
column with a `RunSummary` card above a `LogConsole`, right column a **fixed 420px**
visualization surface whose own code comments flag it as tuned to `entity-scrape` only and
warn that follow/classify will need different values (`live_page.dart:179-190`).

**The fixed width is the core problem.** The surfaces' cards already wrap to fill whatever
width they're given (D44), so a fixed column caps how much can ever be shown, and it was
tuned for one of five flows.

**Restructured as a vertical split** — again because the window is tall and narrow. Both
panes get the full width: the visualization gets many more cards per row than 420px ever
allowed, and log lines get the width they benefit from (which was D45's whole point).

```
┌──────────────────────────────────────────────────────────────────────────┐
│ [Ingest][Scan][Classify]►[Scrape][Follow]        📱 I2201  ● [ Stop ]     │
│ ▶ RUNNING  ·  02:41 elapsed  ·  processed 18  ·  scraped 12  ·  skipped 6│
│ ────────────────────────────────────────────  [Trigger now] [Stop]       │
├──────────────────────────────────────────────────────────────────────────┤
│  VISUALIZATION                                            ⤢ expand       │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │  [in-progress card, large]                                         │  │
│  ├────────────────────────────────────────────────────────────────────┤  │
│  │  [card] [card] [card] [card] [card] [card]   ← wraps to full width │  │
│  │  [card] [card] [card] [card] [card] [card]                         │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│ ═══════════════════════ ⣿ drag to resize ⣿ ═════════════════════════════ │
│  LOGS            [ all levels ▾ ]  [ 🔍 search ]              ⏬ follow   │
│  ⚠ 2 errors this run                                              ▾      │
│  14:02:11  INFO     Opening profile @someone                             │
│  14:02:13  INFO     Scraped: posts 41 · followers 1.2k                   │
└──────────────────────────────────────────────────────────────────────────┘
```

- **`RunSummary` dissolves into the header ribbon.** Today it's a `SingleChildScrollView`
  of label/value rows in its own card — the first thing you see on the app's showpiece
  screen, and visually inert. As a one-line metric strip with `AnimatedCounter`s it takes
  ~28px instead of ~180 and reads faster. Run id and last-run detail move to an ⓘ tooltip.
- **The elapsed timer is new** and is the thing you actually want when watching a run.
- **The level `FilterChip` row collapses** into one `AppSelect` (`all levels ▾`), freeing a
  permanent row. Four of the five levels are on by default and rarely changed
  (`log_console.dart:75-89`).
- **Log search is new** — a run can be hundreds of lines; there is no way to find anything
  in it today. Highlights matches and shows `n of m` with `Enter`/`Shift+Enter` to step.
- **`⤢ expand`** maximises either pane to fill the screen — the "just show me the images"
  and "just show me the logs" modes, both one click away.
- The split is a `ResizableSplit` with `persistKey: 'live.split'`, initial 55/45.

### Surfaces

The five surfaces (`scan`, `classify`, `scrape`, `follow`, `ingest`) keep their existing
structure and every hard-won detail: D41's large-card-only-while-in-progress rule, D42's
correct per-state aspect ratios, D62's vertical scan filmstrip, D44's wrap-at-capped-width,
D67's ordering, D85's click/right-click-to-open-profile via `ResultCardActions`.

Two additions:

- **The scrape before→after morph** that ARCHITECTURE §9 specified and was never built
  (AUDIT §10). `AnimatedReveal` morphs the in-progress row-crop strip card into the
  resolved portrait composite card when `scrape.done` arrives. Genuine continuity motion —
  the same subject, changing state — not decoration.
- **Card widths become tokens** rather than the three hardcoded per-flow values (380 scrape
  / 420 follow / 320 classify), computed from the available width so each surface fits a
  whole number of columns with no ragged gutter at any window size.

---

## 4. Services

Structure is already right (master/detail) — this is mostly polish plus the terminal.

- **`ResizableSplit`** replaces the hardcoded 300px list width (`services_page.dart:74`),
  `persistKey: 'services.split'`.
- **Service tiles** → `AppPanel(interactive: true, accentEdge: kind)`. Same content
  (`StatusDot`, label, state + origin pill, uptime, probe subtitle) with real hover/focus
  states and tokened colors. The three hardcoded hexes in `service_detail.dart:305/314/380`
  — which are literally re-typed `AppPalette` values — become `status.*`.
- **The terminal gets treated as the feature it is.** It's the most technically impressive
  thing in the app (a real ConPTY stream through `xterm.dart` with a replayed ring, D15/D18)
  and it currently sits in a plain pane. It gains a proper frame: a header with the service
  name, a live/replaying indicator, and search / copy-all / clear / font-size controls; the
  `sunken` surface treatment; and its `TerminalTheme` sourced from `tokens.terminal` (which
  also finally fixes `service_terminal.dart:465`'s hardcoded `'Consolas'`).
- **Dependencies tab** → `AppTable`, with the ten dependencies as sortable rows
  (name · state · detail · latency) instead of the current bespoke rows.
- **Self-heal** gets a clearer affordance — today its "off" state is a 15px healing icon in
  the tile corner with a tooltip (`service_tile.dart:59-67`), which is easy to miss for a
  setting that means "a crash stays a crash."

---

## 5. Library — the workhorse

**The problem** (AUDIT §14): this is where the daily pain is — 7,655 files, two curation
steps, and ARCHITECTURE §9 naming it explicitly. It's currently three fixed columns, plain
`ListTile` rails, a two-row toolbar that hides its own primary actions until something is
selected, and no way to see an image large enough to judge it.

### 5a. Browse layout

```
┌────────────────────┬──────────────────────────────────────────────────────┐
│ INTAKE             │  scrape_queued / sejjjalll        1,204 images       │
│  entities      12  │  ○ 24 selected   [→ scraped ▾] [Apply] [Delete]  ⊞⊟ │
│                    │ ─────────────────────────────────────────────────── │
│ SCANNING           │  ┌────┐┌────┐┌────┐┌────┐┌────┐┌────┐┌────┐┌────┐ │
│  scanned    1,882  │  │ ✓  ││    ││ ✓  ││    ││    ││ ✓  ││    ││    │ │
│  gender_invalid 401│  └────┘└────┘└────┘└────┘└────┘└────┘└────┘└────┘ │
│                    │  ┌────┐┌────┐┌────┐┌────┐┌────┐┌────┐┌────┐┌────┐ │
│ ⚑ YOUR REVIEW      │  │    ││ ✓  ││    ││    ││    ││    ││ ✓  ││    │ │
│  gender_valid 1,204│  └────┘└────┘└────┘└────┘└────┘└────┘└────┘└────┘ │
│  scraped       191 │                                                      │
│                    │                                                      │
│ QUEUED             │                                                      │
│  scrape_queued 7,007│                                                     │
│  follow_queued  191│                                                      │
└────────────────────┴──────────────────────────────────────────────────────┘
        ▲ entity list appears as a second rail for non-flat folders
```

- **The folder rail becomes stage-aware.** Seven folders grouped into INTAKE / SCANNING /
  ⚑ YOUR REVIEW / QUEUED, with the two human-review folders visually marked. Right now
  they're seven undifferentiated `ListTile`s and nothing indicates which two are *your job*.
- **One toolbar row, actions always visible.** `Apply` / `Delete` / the move-target picker
  render at all times, disabled when the selection is empty, rather than appearing only
  once something is selected (`library_toolbar.dart:149`). Never hide the primary action of
  a screen.
- **`ResizableSplit`** for both rails (`persistKey: 'library.rails'`).
- **Counts as `NumericText`**, and the `'image(s)'` / `'entit(y|ies)'` string surgery
  (`library_rail.dart:53`) replaced by a shared `plural()` helper.
- **Skeleton loading** for the grid rather than a centred spinner — the grid's shape is
  known before the data arrives.

### 5b. Review mode — the headline feature

Triggered by `R`, the toolbar's `Review` button, the nav rail's Review sub-item, or a click
on a ⚑ edge on the Flows pipeline. A full-window surface over the app.

```
┌──────────────────────────────────────────────────────────────────────────┐
│  ⚑ REVIEW  gender_valid / sejjjalll            42 of 1,204        Esc ✕  │
│  ████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░           │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│                     ┌──────────────────────────┐                         │
│                     │                          │                         │
│                     │      the actual image    │                         │
│                     │      at real size        │                         │
│                     │                          │                         │
│                     └──────────────────────────┘                         │
│                            @someone_here                                 │
│                     root: sejjjalll  ·  open on Instagram ↗              │
│                                                                          │
│              [ ✕ Discard  ←Left ]      [ ✓ Keep  Right→ ]                │
├──────────────────────────────────────────────────────────────────────────┤
│ ✓  ✕  ✓  ✓  ✕  ✓ [●] ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·   │
│                    ▲ current                                             │
│                              42 keep · 18 discard      [ Apply batch ⏎ ] │
└──────────────────────────────────────────────────────────────────────────┘
```

**Why this matters:** the current grid renders a 1080×2246 profile page into a ~120px
thumbnail. You cannot actually read what you're judging — the only way to see more is the
context menu's "Open on Instagram", which leaves the app. Review mode shows the image at a
size where the decision is possible, and makes the decision one keystroke.

Keyboard, and only keyboard, is the fast path:

| Key | Action |
|---|---|
| `→` / `L` | Keep and advance |
| `←` / `H` | Discard and advance |
| `↑` / `K` | Go back one (and un-decide it) |
| `Space` | Toggle the current decision without advancing |
| `Enter` | Apply the batch (confirm dialog, exactly as today) |
| `Del` | Send the current image to the Recycle Bin immediately |
| `Z` | Toggle zoom-to-fit / 1:1 |
| `O` | Open on Instagram |
| `Esc` | Exit; decisions are kept in memory, nothing is written |

- **Nothing is written until `Apply`.** Review mode is a decision buffer; the actual write
  goes through the exact same `POST /api/library/apply` path and the same confirm dialog as
  the grid's Apply button today. No new agent endpoint, no new failure mode.
- **The filmstrip** shows every decision so far and is clickable to jump back.
- **Both curation steps** use it: `gender_valid → scrape_queued` and
  `scraped → follow_queued`, with the target folder read from the existing per-folder
  move-target setting (CP 5.2).
- **Pagination is handled** — review mode pages in the next batch automatically as you
  approach the end of the loaded set, the same way `ctrl+A` already pages in the remainder
  (`library_toolbar.dart:53`). It must never present a partial set as if it were the whole
  folder, which is the same class of bug D90 caught on mobile.

### 5c. Lightbox — one change that needs your confirmation

Double-click on a grid tile currently **copies the id** (`library_tile.dart:84`). I'd
propose double-click opens a **lightbox** (the same large view review mode uses, for a
single image) and copy-id moves to the context menu, where it already exists
(`library_tile.dart:58`).

**Flagged rather than assumed** because it changes an existing interaction, and the
library's selection mechanics are a recorded user preference (D48,
`feedback-multiselect-toggle`). Plain click keeps toggling, arrows keep moving focus only —
none of that changes. Confirm before building.

---

## 6. Insights

Structurally sound already (D77's hand-built table and D78's `CustomPainter` funnel both
exist because Material's stock widgets provably couldn't do the job). This is mostly
theming plus consistency.

- One `AppPage` with a single body padding, fixing the three different paddings across its
  own three tabs (AUDIT §3) and applying `maxContentWidth` to all three rather than only
  the funnel (`insights_page.dart:87`).
- **Funnel** — keep the trapezoid painter and both conversion numbers per stage (D78) with
  no logic change. Retoken its colors to `chart.*`, and animate the trapezoids drawing in
  on first load (`motion.standard`, staggered by stage).
- **Ranking** → `AppTable` (COMPONENTS §10), which is the generalisation of the exact
  hand-built table D77 produced. Same columns, same sort behaviour, same
  row-tap-opens-the-entity-dialog, now with the flexible-column invariant covered by a
  regression test. Metrics render through `NumericText`.
- **Daily limits** — keep the five small multiples (the `dataviz` skill's own
  small-multiples-over-shared-axis guidance drove that, and it stands). Add a summary strip
  above them: today's value against cap for all five as compact bars, so the tab answers
  "am I near a cap" before you read five charts.
- **Cross-linking**: each funnel stage and each ranking row links to the matching Library
  folder or the entity dialog. Insights currently tells you where the losses are and gives
  you no way to act on it.

---

## 7. Settings

Five tabs → six, adding **Appearance** ([THEMES.md](THEMES.md) §9). Ordering:
`Flows · Limits · Queue · Devices · Appearance · Ops`.

- **Flows / Limits / Queue** — restyle only. `LimitCard`'s `Wrap` gains consistent grouping
  headers via `SectionHeader`, and every numeric field renders through the token type
  scale.
- **Ops** — keep the button grid + streamed log panel (and the 19px-overflow fix from D72
  that capped it and made it independently scrollable). The job list becomes an `AppTable`
  with real status colors, and running jobs get a live elapsed timer. The five confirm-gated
  destructive jobs keep their dialogs verbatim.
- **Devices** — the QR pairing card gets real structure; the `Colors.white` QR quiet zone
  becomes `chart.qrQuietZone` so it can be warm-white in Daylight rather than clinical.
- **Appearance** — new (theme grid with live miniatures, density, reduce-motion, terminal
  palette override).

---

## 8. Command palette — new

`Ctrl+K` from anywhere. `ui/command/`.

```
┌────────────────────────────────────────────────────┐
│ 🔍 scr                                             │
├────────────────────────────────────────────────────┤
│  FLOWS                                             │
│  ▶ Trigger now: Scrape                             │
│  ⏸ Stop: Scrape                              running│
│  LIBRARY                                           │
│  ⚑ Review: scraped                             191 │
│  📁 Open folder: scrape_queued               7,007 │
│  GO TO                                             │
│  → Live · Scrape                                   │
│  SETTINGS                                          │
│  # SCRAPE_LIMIT                              300   │
└────────────────────────────────────────────────────┘
```

Sources, all from providers that already exist:

| Group | Items |
|---|---|
| Go to | the 7 destinations + the 6 settings tabs + the 3 insights tabs |
| Flows | Trigger now / Stop / Reduce reserve / toggle switch, × 5 flows — same confirm dialogs |
| Library | Open folder × 7, Review × 2, per-entity jump |
| Services | Start / Stop / Restart / Test / Take over, × 3 services |
| Ops | the 10 registered jobs, destructive ones still confirm-gated |
| Appearance | the 6 themes, 2 densities |
| Settings | every `ConfigKey` from the schema, jumping to its field |
| Help | the shortcut reference, the welcome dialog |

Fuzzy subsequence matching, grouped results, recents first, full keyboard operation, `Esc`
to dismiss. Every entry reuses the existing action path — the palette is a new *front door*
to existing behaviour, never a second implementation of it.

`core/shortcuts_reference.dart` (CP 7.3, hand-assembled from bindings scattered across
four files) becomes **generated from the command registry**, so it can no longer drift from
the real bindings.

---

## 9. Notification center

Restyle plus two structural fixes:

- **Group by day** with sticky `micro` headers, instead of one flat list.
- The four hardcoded `Colors.redAccent` / `orangeAccent` ×2 / `blueAccent`
  (`notification_center.dart:213-216`) become `status.*`.
- `FadeSlideIn` on arrival, so a notification landing while the panel is open is visible as
  an event rather than a silent list mutation.
- The panel-header `Expanded`+ellipsis fix from D56 is preserved exactly.

---

## 10. Connection banner and degradation

`shell/connection_banner.dart` keeps its behaviour (ARCHITECTURE §9's "honest degradation":
a non-blocking banner with Retry and *Start agent*, never a dead screen). It gains the
`status.bad` container treatment and a slide-in rather than appearing instantly.

New: when the agent is down, screens render their **skeleton** with a "last seen 2m ago"
watermark rather than an error page, so the layout doesn't collapse and reflow when the
connection returns.
