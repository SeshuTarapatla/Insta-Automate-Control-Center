# v2 — Observed: what the app actually looks like

Captured 2026-08-04 from a fresh debug build against the live agent, real pipeline data,
and the scrcpy mirror running — i.e. the real production setup, not a mock.

Screenshots are committed in [screens/](screens/). **Look at them before implementing any
screen.** They are the ground truth this document summarises.

| File | Screen |
|---|---|
| `00-desktop.png` | whole desktop — mirror + VS Code + app, shows the real layout |
| `01-overview.png` | Overview |
| `02-flows.png` | Flows |
| `03-live.png` | Live (entity-ingest selected, real run) |
| `04-services.png` | Services → Supervised, ADB server selected, terminal streaming |
| `05-library.png` | Library → `entities` (portrait profile pages) |
| `08-library-rowcrops.png` | Library → `scrape_queued / _.hridaya._` (wide row crops) |
| `06-insights.png` | Insights |
| `07-settings.png` | Settings → Flows |

This document **corrects four things** the source-only audit got wrong. Those corrections
are marked ⚠️ and are also reflected in the other v2 docs.

---

## 1. ⚠️ The real window is landscape, not tall and narrow

Measured, not inferred:

| | Value |
|---|---|
| Monitor | **2560 × 1600** physical |
| Windows scaling | **150%** (DPI 144) |
| Work area | 2560 × 1528 physical (taskbar takes 72) |
| scrcpy mirror | occupies x 0–664 physical = **443 logical** on the left |
| App window | x 664 → 2560, **1896 × 1528 physical** |
| **App client area** | **1253 × 1013 logical** |
| Content area (minus 85px rail, 40px title bar) | **≈ 1168 × 973 logical** |

**The docs said "roughly 1250 × 1400 logical … taller than it is wide."** Width was right;
height was wrong. The real shape is **≈ 1.24 : 1 landscape** — closer to 5:4. The error came
from reading `main.dart`'s geometry math without accounting for the work area's real height
at 150% scaling.

This invalidates the stated *reason* for two decisions (D95). One survives on better
grounds, one is reversed — see §7.

## 2. The dominant visual problem is horizontal emptiness

Every screen is laid out as though the window were narrow, and it isn't. Measured from the
screenshots:

| Screen | Wasted space |
|---|---|
| **Flows** | ~**55%** of the screen is empty black below the cards. Five 360px cards wrap 3 + 2, leaving a whole card slot empty at bottom-right, and ~700 logical px of dead height below. |
| **Settings → Flows** | each switch row has the label hard-left and the switch hard-right with **~1100 logical px of nothing between them**. Then ~450px of dead height below. |
| **Live** | the fixed 420px visualization column was **~95% empty** for entity-ingest (one small card in a 413 × 950 column). |
| **Library** | the two rails take **440 of 1168 logical px — 38% of the width — for navigation**, and with no entity selected the entire grid pane (~660 × 950) is one line of placeholder text. |
| **Services** | ~400px of dead height under the three service tiles. |
| **Overview** | the 3 + 2 flow wrap leaves a card slot empty; the page still scrolls past two screens. |

The single highest-leverage change in the whole redesign is **using the horizontal space**.

## 3. ⚠️ The Library grid uses one cell aspect ratio for two very different image shapes

This is the worst visual defect in the app, and it is invisible from source.

The grid's cells are near-square. The folders hold:

| Folder | Real image shape | Result in a square cell |
|---|---|---|
| `entities` | 1080 × 2246 — **portrait, 1 : 2.08** | letterboxed left/right, **~40% of every cell is empty** (`05-library.png`) |
| `scanned`, `gender_valid`, `gender_invalid`, `scrape_queued` | 1080 × 198 — **wide strip, 5.45 : 1** | letterboxed top/bottom, **~82% of every cell is empty** (`08-library-rowcrops.png`) |
| `scraped`, `follow_queued` | 1080 × ~2000 — portrait | as `entities` |

In `08-library-rowcrops.png` only **9 cells** are visible in the grid pane. With cells
matched to the 5.45:1 content shape, the same area holds roughly **40**. For the screen
whose job is reviewing a 6,635-image backlog, that is a 4× difference in how much you can
see at once.

D41 chose `BoxFit.contain` over `cover` for good reason (letterbox rather than lose
content) and that decision is right — but it was made for the Live surfaces, where the
container matches the content. The grid never got a matching cell shape.

**Fix:** the cell aspect ratio becomes a per-folder value derived from the folder's known
image shape, not one constant. `library/folders.py`'s `FOLDERS` registry already names all
seven folders; the shapes are documented in CLAUDE.md's `IA_DIR` table. No agent change —
the client can hold the mapping.

## 4. Status is not glanceable on Flows or Overview

`02-flows.png`: **four of the five cards** (Ingest, Scan, Classify, Scrape) render an
**identical amber hourglass icon in an identical 56px amber circle**, above the **identical
words "Waiting on condition."** Only Follow differs (pause icon, "Paused for the day").

So the screen whose entire purpose is telling you what the pipeline is doing communicates
almost nothing without reading the ⓘ tooltip on each card individually. The 56px amber
circle is the largest, highest-contrast element on each card and carries the least
information on the screen.

This is worse than AUDIT §13 predicted and makes the pipeline redesign more urgent, not
less.

Also visible: the cards in a row have **ragged bottom edges** (Scan is taller than Ingest
and Classify because it alone has a "today" line), so the top row doesn't align. Real state
captured: Follow reads **"followed 99/60"** — over its own daily limit.

## 5. Services' detail pane is already the app's best design — promote it

`04-services.png` is markedly more mature than the rest of the app, and nothing in the
original v2 docs noticed because it reads as ordinary in source:

- a **metric strip** — `UPTIME · RESTARTS · PID · PORT · PROBE · OWNER` as uppercase micro
  labels above their values, in a row of bordered cells
- switch cards that **explain what they do** in a sentence, rather than a bare label
- a functional-test result card with value chips
- a terminal with a real header: `Terminal — live  108×27` plus search and copy actions

**The metric strip should become `MetricStrip` in [COMPONENTS.md](COMPONENTS.md) and be used
everywhere** — it is exactly the treatment the Flows nodes, the Live run header, and the
Insights summary need. This is a case of the app already containing its own answer.

## 6. ✅ Two open questions are now answered by observation

**The light-theme terminal (THEMES §8) is safe.** `04-services.png` shows real `adb` output:
grey `—` agent lines and plain white log text. Essentially monochrome — no dark-on-dark ANSI
anywhere. `TerminalPalette.light` will render it fine. Keep the "always dark" override as a
user preference, but it is not needed as a fallback.

**The `Colors.white` QR quiet zone** (AUDIT §2) is the only defensible hardcoded color and
stays, tokened as `chart.qrQuietZone`.

## 7. ⚠️ Consequences for the plan

### Flows vertical pipeline — **keep, better reason**

Not because the window is narrow (it isn't) but because:

- the screen currently wastes ~55% of its height, and
- at 1168 logical px wide, each pipeline node can be a **horizontal strip** carrying status
  dot + name + state + inline gate reason + today's counters + actions **all in one row**,
  which is exactly the "use the horizontal space" fix §2 calls for.

Budget: 5 nodes × ~120px + 4 edges × ~55px = **820px** in a 973px content height. Fits, with
room for one node to expand.

### Live vertical split — **⚠️ REVERSED, keep it horizontal**

SCREENS §3 proposed stacking the visualization above the logs. That was justified by the
"tall and narrow" error. At 1168 × 973 a vertical split gives each pane ~470px of height —
too short for a log console (~12 lines) and too short for portrait result cards.

**Keep the horizontal split.** Both panes get the full 973px height, which is what a log
stream and a column of portrait cards both want. What actually needs fixing is that the
right column is a hardcoded 420px tuned to one flow: make it a `ResizableSplit` with a
~45/55 default and per-flow computed card widths.

### Library — **aspect ratio is now the top fix, above review mode**

Review mode is still the headline feature, but §3's per-folder cell aspect ratio is a
smaller change with comparable impact and should land first, in V2.9.

Also: the two rails at 38% of width should collapse. The folder rail can be much narrower
(icons + count, expanding on hover) or the two rails can merge into one tree.

### Settings — rows need a middle

The switch rows' ~1100px void is the clearest single example of §2. Every full-width row in
the app (settings switches, dependency rows, queue entries) should either constrain to a
readable measure (~720px) or put something useful in the middle.

## 8. Smaller observations

- **Two different "Stop" buttons sit inches apart on the Live header** (`03-live.png`): the
  flow's Stop and `DeviceBar`'s mirror Stop, neither labelled as to scope. Genuinely
  ambiguous — the mirror one should say what it stops.
- **The Settings `TabBar` stretches edge-to-edge** across 1168px with huge gaps between five
  tabs (`07-settings.png`), while Services' `TabBar` is correctly `isScrollable` +
  `tabAlignment: start` (`04-services.png`). Two different treatments of the same widget.
- **The Live log console renders a JSON blob in the body font**, not monospace
  (`03-live.png`) — structured output should be `MonoText`.
- **Nav rail is ~85 logical px** and reads well. Grouping and badges (SCREENS §0) still
  apply; the width does not need to change.
- **The title bar's middle ~700px is empty** — ample room for the status cluster and the
  ⌘K affordance.
- The five log-level `FilterChip`s take a full row with all five enabled, confirming
  AUDIT §15.
- `Run summary`'s label/value list leaves ~800px empty to the right of every value.
- Real data captured for reference: `scrape_queued` **6,635 across 104 entities**,
  `follow_queued` **201 across 10**, `entities` **442**, scan today `profiles 1/10 · reels
  2/30 · posts 0/30`, scrape `170/300`.

---

## How these were captured

Rule 5 was lifted by the user for this session specifically. Method, for repeatability:

- `flutter clean` → `launch_app` (dart MCP) on device `windows`, debug build.
  **Note:** `launch_app` returns the `flutter run` host pid, not the window's — the real
  window belongs to a child `ia_control_center.exe` (found via `Get-Process`).
- `flutter_driver` is **not** available — the app doesn't call
  `enableFlutterDriverExtension()`. Driving was done with Win32 `SetCursorPos` +
  `mouse_event` at logical client coordinates converted through the monitor's DPI scale.
- Screenshots via .NET `Graphics.CopyFromScreen` over the window rect, after
  `SetProcessDPIAware()` and `SetForegroundWindow`.
- Helper scripts are in the session scratchpad (`shot.ps1`, `sweep.ps1`); nav rail
  destinations sit at logical `x = 40`, `y = 65 + 64n`.
- **Nothing was mutated** — only navigation clicks (nav rail, folder rail, entity list).
  No switch, trigger, apply, delete or ops job was touched.
