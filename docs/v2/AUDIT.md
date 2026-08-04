# v2 — Current-state audit

Written 2026-08-04 against `main` @ `f25210e`, by reading all 90 files under `app/lib/`.

This is the evidence base for everything in [SCREENS.md](SCREENS.md) and
[DESIGN_SYSTEM.md](DESIGN_SYSTEM.md). **The implementing session should not re-derive
this** — every claim below was checked against the real source, with file:line references
so a fix can start immediately.

The app is *functionally* complete and correct. Nothing in this document is a bug report.
It is a catalogue of visual and structural debt, most of it accumulated honestly: the app
grew over eight phases, each checkpoint solving its own problem well, with no pass that
ever looked across all seven screens at once. CP 7.3 was the first attempt at that, and it
got about 60% of the way — this documents the other 40% plus everything CP 7.3 wasn't
scoped to touch.

---

## 1. The theme layer is a stub

`core/app_theme.dart` (179 lines) is the whole design system today. It holds exactly four
things: three status colors and a 23-field terminal palette. Everything else — every
radius, every spacing value, every font choice, every elevation decision — is a literal
typed inline at the call site.

`app.dart:15-21` is the entire `ThemeData`:

```dart
darkTheme: ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorSchemeSeed: const Color(0xFF6C63FF),
  scaffoldBackgroundColor: Colors.transparent,
  extensions: const [AppPalette.dark],
),
```

That is a stock Material 3 dark scheme generated from one seed. Every surface color, every
component shape, every text style in the app is Material's default. **This is the single
biggest reason the app "looks generic"** — it is, quite literally, the default look, and
no amount of per-widget polish changes that while the theme itself is four lines.

Consequences that show up everywhere:

- **No component themes are set at all.** No `cardTheme`, `filledButtonTheme`,
  `inputDecorationTheme`, `chipTheme`, `dividerTheme`, `tabBarTheme`,
  `navigationRailTheme`, `tooltipTheme`, `snackBarTheme`, `dialogTheme`,
  `switchTheme`, `scrollbarTheme`, `popupMenuTheme`. Every one of those renders at
  Material's default, and every deviation from the default is hand-coded per call site.
- **No `textTheme` customization.** `Roboto` at Material's default sizes and weights, with
  Material's default (loose) letter spacing on labels. Nothing sets `height`, so line
  height is Roboto's metric default rather than a designed value.
- **`AppPalette.lerp` deliberately doesn't blend** (`app_theme.dart:56`) — correct for a
  single dark palette, but it means a theme *switch* will hard-cut rather than animate.
  v2 needs this to actually interpolate, or needs the switch animated another way.

## 2. Thirteen hardcoded colors survive outside the palette

CP 7.3 centralized the status/terminal colors and stopped there. These are still literals:

| File:line | Literal | Should be |
|---|---|---|
| `app.dart:18` | `Color(0xFF6C63FF)` | the theme's accent token |
| `features/live/log_console.dart:11` | `Colors.amber.shade700` | `palette.statusWarn` |
| `features/live/surfaces/surface_common.dart:20` | `Color(0xFF1F4D34)` / `Color(0xFF6EE7A8)` | status container/on-container tokens |
| `features/notifications/notification_center.dart:213-216` | `Colors.redAccent` / `orangeAccent` ×2 / `blueAccent` | `statusBad` / `statusWarn` / `statusInfo` |
| `features/services/service_detail.dart:305` | `Color(0xFFFFB454)` | `palette.statusWarn` |
| `features/services/service_detail.dart:314` | `Color(0xFF3DD68C)` | `palette.statusGood` |
| `features/services/service_detail.dart:380` | `Color(0xFF3DD68C)` | `palette.statusGood` |
| `features/settings/devices_tab.dart:214,217` | `Colors.white` | intentional — QR needs a light quiet zone. Keep, but token it as `chart.qrQuietZone` so a light theme can pick something warmer than pure white |
| `features/settings/devices_tab.dart:279` | `Colors.green` | `palette.statusGood` |
| `features/settings/ops_tab.dart:254` | `Colors.green` | `palette.statusGood` |

`service_detail.dart:305/314/380` are the sharpest example: they are *the exact same hex
values* as `AppPalette.dark.statusWarn` and `.statusGood`, re-typed by hand. They will
silently diverge the moment a theme changes those, and nothing will catch it.

## 3. Six different page paddings

There is no page-shell component, so every screen invents its own outer padding:

| Screen | Padding | Source |
|---|---|---|
| Overview | `all(24)` | `overview_page.dart:30` |
| Flows | `all(24)` | `flows_page.dart:34` |
| Live | `fromLTRB(20, 16, 20, 12)` header, then `Card` margins of `fromLTRB(12, 12, 12, 6)` and `fromLTRB(12, 6, 12, 12)` | `live_page.dart:90,172,174` |
| Services | `fromLTRB(24, 12, 24, 0)` tabs, `fromLTRB(24, 20, 24, 24)` body | `services_page.dart:25,69` |
| Library | `fromLTRB(24, 16, 24, 16)` | `library_page.dart:41` |
| Insights | `fromLTRB(24, 12, 24, 0)` tabs, then `(24,20,24,24)`, `(24,16,24,20)`, `(24,16,24,24)` across its three tabs | `insights_page.dart:28,85,307,358` |
| Settings | `fromLTRB(24, 24, 24, 0)`, tabs `symmetric(horizontal: 24)` | `settings_page.dart:43,47` |

Insights alone uses three different body paddings across its own three tabs. Switching
tabs shifts content vertically by up to 4px for no reason.

## 4. Inconsistent page headers

Four unrelated conventions for "what is this screen":

- **Overview** — a private `_SectionHeader` with `titleMedium` + a chevron, tappable to
  navigate (`overview_page.dart:68-93`).
- **Settings > Limits / Flows** — bare `titleLarge` text with no container
  (`limits_tab.dart:32`, `switches_tab.dart:51`).
- **Services** — `titleMedium` + a `Chip` + an explanatory `bodySmall` sentence, inside
  the left column rather than at page level (`services_page.dart:105-123`).
- **Insights > Funnel** — `titleMedium` + `Chip` + a `bodySmall` sentence, inside a
  `ConstrainedBox(maxWidth: 900)` (`insights_page.dart:92-107`).
- **Live, Library, Flows** — no page title at all. You can only tell which screen you're
  on from the nav rail's selection state.

There is no consistent answer to "where does the eye land when this screen opens."

## 5. Three chip/badge treatments

- Material `Chip` with `visualDensity: compact` — services count, insights entity count,
  switches count, run-summary counters, library move target, `flows` — 7 call sites.
- A private `_Pill` — `Container` + 5px radius + `outlineVariant` border
  (`service_tile.dart:139-162`).
- `OutcomeBadge` with a `BadgeTone` enum and its own hardcoded colors
  (`surfaces/surface_common.dart:20`).

Same visual job, three shapes, three sizes, three color sources.

## 6. Eleven hand-rolled async states survived the CP 7.3 retrofit

CP 7.3 built `LoadingView` / `EmptyView` / `ErrorView` / `AsyncValue.stateView()`
(`core/async_state_view.dart`) and retrofitted the *page-level* call sites. These are
still raw `.when()` with bare `Center(child: Text('$error'))` or a naked
`CircularProgressIndicator`:

| File:line | What it renders on error |
|---|---|
| `library_rail.dart:16` | `Center(child: Text('$error'))` |
| `library_rail.dart:99` | `Center(child: Text('$error'))` |
| `live/device_bar.dart:66` | an icon + `'device error'` — acceptable, it's a header strip, but untokened |
| `live/log_console.dart:62-64` | `Center(child: Text('Could not load logs: $error'))`, no retry |
| `notifications/notification_center.dart:134` | inside the popover |
| `settings/devices_tab.dart:42` | |
| `settings/ops_tab.dart:90` | |
| `settings/queue_tab.dart:27` | |
| `library/entity_yield_dialog.dart:32` | |
| `core/agent_image.dart:42`, `core/library_image.dart:41` | per-image, correctly bespoke — leave |

A raw exception string is not an error state a user can act on.

## 7. Three spellings of "monospace"

- `'Consolas'` — 8 call sites (`service_tile.dart:115`, `service_detail.dart:498,651`,
  `service_terminal.dart:322,366,465`, `config_file_bar.dart:59`, `ops_tab.dart:510`,
  `queue_tab.dart:173`, `shortcuts_reference.dart:78`)
- `'monospace'` — 2 call sites (`log_console.dart:267`, `run_summary.dart:163`)
- `TerminalStyle(fontSize: 13, fontFamily: 'Consolas')` — the xterm widget
  (`service_terminal.dart:465`)

`'monospace'` is not a real family name on Windows; it resolves through Flutter's fallback
chain and renders visibly differently from `'Consolas'` right next to it. The sticky-error
strip in the log console and the log lines above it are in different faces today.

## 8. Tabular figures used exactly once

`service_tile.dart:102` sets `FontFeature.tabularFigures()` on the uptime readout. Nowhere
else. Every other number in the app is proportional, which means **every live-updating
number visibly jitters as it changes**:

- the cooldown countdown ring (`flow_card.dart:400`) — reflows every second
- today's counters (`flow_card.dart:220`)
- run-summary counters (`run_summary.dart:135`)
- the ranking table's three metric columns (`insights_page.dart:230-232`)
- library folder counts (`library_rail.dart:52`)
- probe latency, restart counts, burn-down axis labels

This is a one-line token fix with an outsized effect on how "engineered" the app feels.

## 9. Mica is enabled but invisible

`main.dart:79` calls `Window.setEffect(effect: WindowEffect.mica, dark: true)`, and
`app.dart:19` sets `scaffoldBackgroundColor: Colors.transparent`. So the backdrop is real.

But every piece of content sits on an opaque Material 3 `Card` or `surfaceContainer*`
color, so the Mica is only ever visible in the gaps between cards — a few pixels of
padding. The app pays the full cost of a translucent window (compositing, the
`flutter_acrylic` dependency, the transparent-background special-casing) and shows
essentially none of the benefit.

## 10. Almost no motion

ARCHITECTURE §9 promises "`AnimatedSwitcher` for the scrape before→after morph, implicit
animation on counters and rings. Nothing decorative." What actually exists:

- `StatusDot`'s pulse for transient states (`status_dot.dart`) — genuinely good, the one
  piece of motion in the app that carries meaning
- the cooldown ring's `TweenAnimationBuilder` (`flow_card.dart:387`)

What doesn't exist:

- **Page transitions.** `app_shell.dart:107-115` is a bare `switch` — screens hard-cut.
- **Counter animation.** Every number snaps.
- **The scrape before→after morph** ARCHITECTURE explicitly specifies. Never built.
- **List insertion.** New log lines, new result cards, new notifications all appear
  instantly with no entrance.
- **Hover states.** Nothing beyond `InkWell`'s default splash. On a desktop app driven
  by a mouse, no element previews its own interactivity.
- **Theme switching.** Will hard-cut (see §1).

## 11. Every split is a hardcoded pixel width

| Split | Width | Source | Note |
|---|---|---|---|
| Services list | 300 | `services_page.dart:74` | |
| Library folder rail | 220 | `library_page.dart:45` | |
| Library entity list | 220 | `library_page.dart:48` | |
| Live visualization surface | 420 | `live_page.dart:192` | the code itself flags this as tuned to `entity-scrape` only, and warns follow/classify may need different values |
| Flow card | 360 | `flow_card.dart:162` | |
| Insights burndown card | 420 / 340 | `insights_page.dart:395`, `overview_page.dart:213` | same card, two widths, depending on which screen embeds it |
| Scrape result card | 380 | `scrape_surface.dart:83` | |
| Follow result card | 420 | per D44 |
| Classify result card | 320 | per D44 |
| Run-summary label column | 76 | `run_summary.dart:157` | |
| Log console time column | 58, level pill 66 | `log_console.dart:186,193` | |
| Ranking metric columns | 90 / 90 / 120 | `insights_page.dart:129-134` | |

Every one of these was tuned by hand against one window size, several of them documented
as such in DECISIONS.md (D43, D44, D45). None of them adapt, and none can be dragged.

## 12. Overview reuses full-size cards it shouldn't

`overview_page.dart:112` embeds five real `FlowCard`s (360px each) in a `Wrap`. At the
app's real production width that wraps to 2 or 3 per row with a ragged last row, and each
card carries its full control set — switch, Trigger now, Reduce reserve, Stop, View logs,
info tooltip.

That makes Overview a *duplicate of the Flows screen* rather than a summary of it. It also
means Overview is the tallest page in the app by a wide margin — five 200px cards, then two
cards, then five 340px burn-down charts, then two more cards — so "mission control at a
glance" requires scrolling past roughly two screens of content.

There is no headline. Nothing on the page answers "is anything wrong right now?" without
reading all five flow cards, three service tiles, the dependency strip and the
notification feed individually.

## 13. Flows renders a pipeline as five disconnected cards

`entity_ingest → entity_scan → entity_classify → entity_scrape → entity_follow` is a
strict pipeline with real backlog queues between each stage — the whole of D91's
`SCAN_RESERVE_TARGET` and D86's `SCRAPE_RESERVE_FACTOR` logic is about the size of those
inter-stage queues, and the Library screen's seven folders *are* those queues.

The Flows screen renders this as five independent cards in a `Wrap`
(`flows_page.dart` → `FlowCard`), in pipeline order, and that ordering is the only hint
that they're related. The backlog counts that actually govern triggering are not shown at
all — they live in the Library screen's folder rail, on a different tab.

D93 then moved the mechanism explanation *and* the gate detail into a tooltip, because the
card was too cluttered to hold them. That was the right call for that card, but it means
the answer to "why isn't this running?" is now behind a hover on a 14px icon.

## 14. Library is the daily workhorse and the least-designed screen

By the project's own account this is where the pain is: 7,655 real files, two
human-in-the-loop curation steps, and ARCHITECTURE §9 calls out "reviewing 7.5k images
with a mouse is the current pain."

What's there: three fixed columns, a `ListTile` folder rail, a `ListTile` entity list, a
grid of `LibraryTile`s, and a two-row toolbar. It works — CP 5.3/D48 got the selection
mechanics right — but:

- **No progress signal.** Nothing says "you've reviewed 40 of 312 in this folder."
- **No preview.** No way to see one image large. On a 1080×2246 profile page rendered into
  a ~120px thumbnail, you cannot actually read what you're judging. The context menu offers
  "Open on Instagram" as the only way to see more.
- **The toolbar hides its own actions.** Apply / Delete / the move-target picker only
  render when `selection.selected.isNotEmpty` (`library_toolbar.dart:149`), so the primary
  actions of the screen are invisible until you've already selected something.
- **Two rows of chrome** above every grid (`library_toolbar.dart:115-166`), taking ~90px
  of vertical space permanently.
- **The folder rail is un-designed** — plain `ListTile`s with `bodyLarge` titles and a
  `'N image(s)'` subtitle. Seven stage folders that represent a pipeline, rendered as an
  undifferentiated list, with no indication of which two are the ones that need human
  review.

## 15. Smaller specifics worth fixing

- `library_rail.dart:53` — `'${folder.total} across ${folder.entities} entit${folder.entities == 1 ? 'y' : 'ies'}'`. Pluralization by string surgery, and `'image(s)'` elsewhere. Needs a shared `plural()` helper.
- `title_bar.dart:39` — the status chip reads the literal text `'Agent: connected'` at all times. A 40px title bar spending ~130px on a label that says "everything is normal" 99% of the time.
- `title_bar.dart:93-98` — maximize is faked via `setBounds` because real Win32 maximize glitches the custom caption. The known gap (Win+Up, drag-to-top, taskbar menu still glitch) is documented but unfixed.
- `app_shell.dart:84` — `Divider(height: 1)` under the title bar and `VerticalDivider(width: 1)` beside the rail, both at Material's default `dividerColor`, which on this scheme is barely visible. The shell has no real structural edges.
- `flows_page.dart` / `overview_page.dart` — `FlowCard` is rendered in both, at the same size, with the same controls. No compact variant exists.
- `log_console.dart:75-89` — five `FilterChip`s (DEBUG/INFO/WARNING/ERROR/CRITICAL) take a full row permanently. Four of the five are on by default and rarely changed.
- `run_summary.dart:38` — a `SingleChildScrollView` of label/value rows with a 76px label gutter. Functional, visually inert; it's the first thing you see on the Live screen.
- `insights_page.dart:87` — `ConstrainedBox(maxWidth: 900)` on the funnel, but the ranking table and burn-down tabs have no max width, so content measure varies wildly by tab on a wide window.
- `entity_yield_dialog.dart` / `shortcuts_reference.dart` / `onboarding.dart` — three dialogs, three different internal layouts, no shared dialog shell.
- `device_bar.dart:86` — `maxWidth: 140` on the device model name, then ellipsis. Fine, but it's another hardcoded measure.
- No `scrollbarTheme` anywhere — Material's default desktop scrollbar is used throughout, including in the library grid where it overlays content.
- `fl_chart` is pinned at `^0.69.0`; current is `1.2.0`. A major-version gap with breaking API changes. Not urgent, but the burn-down redesign is the natural moment to decide.

---

## What CP 7.3 already got right — do not undo

Listed so the v2 session doesn't "fix" things that are already correct:

- `core/async_state_view.dart` — the shape is right. It needs *more* call sites (§6), not a redesign.
- `AppPalette` as a `ThemeExtension` — the right mechanism. v2 widens it into a full token set rather than replacing it.
- `StatusDot`'s transient-state pulse — meaningful motion, keep exactly.
- `FunnelChart`'s `CustomPainter` trapezoid (D78) and the hand-built ranking table (D77) — both exist because Material's stock widgets provably couldn't do the job. Restyle through tokens; do not revert to `DataTable`.
- The library's selection mechanics (D48) — plain click/Space toggles, arrows move focus only. This is a recorded user preference (`feedback_multiselect_toggle`). Preserve exactly.
- `flow_card.dart`'s `_StatusKind` split (D84) — blocked vs cooldown vs polling is a real distinction hard-won across two repos. The v2 pipeline view must preserve all six states.
- Every `maxLines: 1` + `TextOverflow.ellipsis` — each one is a fixed overflow (D87, D89, D93). Keep them.
- The 10 layout tests in `app/test/` — they encode real overflow regressions that `flutter analyze` cannot see (D19). They must keep passing, and v2 adds more.
