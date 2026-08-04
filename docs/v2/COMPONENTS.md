# v2 — Component library

The shared vocabulary every screen is rebuilt from. New directory `app/lib/ui/`, sitting
between `core/` (models, clients, cross-cutting services) and `features/` (screens).

Rule of thumb for the implementing session: **if a feature file sets a color, a radius, a
padding, a font, a shadow or an icon size directly, the component it needed doesn't exist
yet.** Build it here instead.

Each component below lists: what it replaces (with file:line from today's code), its API,
and its behaviour across themes.

---

## 0. Directory

```
app/lib/ui/
  surfaces.dart      AppPanel · AppCard · AppWell · AppOverlay
  text.dart          AppText · MonoText · NumericText · AnimatedCounter
  status.dart        StatusChip · StatusDot(kept) · OutcomeBadge · CountBadge
  buttons.dart       AppButton · IconAction · ButtonGroup
  page.dart          AppPage · PageHeader · SectionHeader · Toolbar
  fields.dart        AppTextField · SearchField · AppSelect · AppSwitch
  layout.dart        ResizableSplit · Gap · AppDivider · MetricRow · KeyValueList
  feedback.dart      LoadingView · EmptyView · ErrorView (moved, widened)
  overlays.dart      AppDialog · AppTooltip · AppMenu · AppSnack
  data.dart          AppTable · AppTableColumn · Sparkline
  motion.dart        FadeSlideIn · AnimatedReveal · animation helpers
  icons.dart         AppIcon · AppIcons (semantic names)
  command/           CommandPalette + registry (see SCREENS.md §8)
```

---

## 1. Surfaces

Replaces the three-way split the audit found: `Card(margin: EdgeInsets.zero)` at 19 sites,
`Material + InkWell + Container + Border` (`service_tile.dart:31-44`), and bare
`Container + BoxDecoration` (`log_console.dart:192`, `library_tile.dart:89`,
`insights_page.dart:166,220`).

```dart
AppPanel({
  Widget child,
  EdgeInsets? padding,          // defaults to tokens.space.cardPadding
  SurfaceLevel level,           // base | raised | sunken | overlay
  bool interactive,             // adds hover/focus/pressed states
  VoidCallback? onTap,
  VoidCallback? onSecondaryTap, // desktop right-click, used by the library
  bool selected,
  StatusKind? accentEdge,       // a 2px status-colored left/top edge
})
```

`AppCard` = `AppPanel(level: base)` with the theme's card padding.
`AppWell` = `AppPanel(level: sunken)` — terminal body, log console, code blocks.
`AppOverlay` = `AppPanel(level: overlay)` — used internally by dialogs/menus.

**All depth comes from `EffectTokens.depth`** (DESIGN_SYSTEM §1.7 / §4). `AppPanel` reads
it once and renders a border, a shadow, both, or a glow. Feature code never sets
`elevation` and never writes a `BoxShadow` again.

`accentEdge` is the one new visual affordance: a status-colored edge on a panel, which is
how a failed service, a blocked flow or an errored ops job announces itself without needing
a differently-colored card background in every theme.

---

## 2. Text and numerals

```dart
AppText(String, {TextRole role, Color? color, int? maxLines, bool ellipsis = true})
```

`TextRole` is the nine-role scale from DESIGN_SYSTEM §2. `ellipsis` defaults **true** —
every overflow fix in D87/D89/D93 was adding `maxLines: 1` + `TextOverflow.ellipsis` by
hand, and making it the default means the next one never regresses.

```dart
MonoText(String, {TextRole role, Color? color})       // tokens.type.mono
NumericText(num | String, {TextRole role, ...})       // mono + tabularFigures + slashed zero
AnimatedCounter(int value, {Duration? duration})      // NumericText that tweens on change
```

`NumericText` is the fix for AUDIT §8 — it is **the only way numbers get rendered in v2**,
and it enforces `FontFeature.tabularFigures()` so nothing jitters. Call sites to convert:
the cooldown ring (`flow_card.dart:400`), today's counters (`flow_card.dart:220`),
run-summary counters (`run_summary.dart:135`), the ranking table's three metric columns
(`insights_page.dart:230-232`), library folder counts (`library_rail.dart:52`), probe
latency and restart counts (`service_detail.dart`), burn-down axis labels.

`AnimatedCounter` delivers the "implicit animation on counters" ARCHITECTURE §9 promised
and AUDIT §10 found missing. Duration `motion.quick`; collapses to instant under
`motion.reduced`.

---

## 3. Status

```dart
enum StatusKind { good, info, warn, bad, neutral }

StatusChip({StatusKind kind, String label, IconData? icon, bool dense})
CountBadge({int count, StatusKind kind, bool dot})   // nav rail badges, unread counts
OutcomeBadge({String label, StatusKind kind})        // kept name, retokened
```

Collapses the three treatments in AUDIT §5 into one: Material `Chip` (7 sites), `_Pill`
(`service_tile.dart:139`), and `OutcomeBadge` (`surface_common.dart:20`). `OutcomeBadge`
keeps its name and call sites — only its `BadgeTone` enum and hardcoded
`Color(0xFF1F4D34)`/`Color(0xFF6EE7A8)` are replaced by `StatusKind` + tokens.

**`StatusDot` is carried over unchanged** from `features/services/status_dot.dart` (moved
to `ui/status.dart`). Its transient-state pulse is the one piece of meaningful motion in
the app today and is explicitly protected in AUDIT's "do not undo" list. It gains only a
`StatusKind` parameter so it isn't tied to `ServiceState`.

Every status chip pairs color with a **word or an icon**, never color alone — the
accessibility rule from DESIGN_SYSTEM §1.4/§6.

---

## 4. Buttons and actions

```dart
enum ButtonTone { primary, neutral, danger }
enum ButtonSize { sm, md }

AppButton({
  String label, IconData? icon, VoidCallback? onPressed,
  ButtonTone tone = neutral, ButtonSize size = md,
  bool filled = false, bool busy = false, String? tooltip,
})

IconAction({IconData icon, VoidCallback? onPressed, required String tooltip, ...})
ButtonGroup({List<Widget> children})   // consistent gap + wraps instead of overflowing
```

`busy` renders an inline spinner and disables the button — this is the pattern
`flow_card.dart:233-254` hand-rolls today for the "Command sent — waiting…" state, and
`ops_tab.dart` needs too.

`IconAction` **requires** `tooltip` (a compile-time guarantee, not a convention) and emits a
`Semantics` label from it, closing the accessibility gap in DESIGN_SYSTEM §6.

`ButtonGroup` replaces the ad-hoc `Wrap(spacing: 8, runSpacing: 8)` clusters in
`flow_card.dart:255`, `library_toolbar.dart:140`, `service_detail.dart` and `ops_tab.dart`
— all of which were separately hand-tuned after real overflow reports (D87, D89, CP 5.3).

**Every button sets `SystemMouseCursors.click`** (DESIGN_SYSTEM §5).

---

## 5. Page structure

The fix for AUDIT §3 (six page paddings) and §4 (four header conventions).

```dart
AppPage({
  String title,
  String? subtitle,
  List<Widget> actions,        // right-aligned in the header
  Widget? leading,             // e.g. the Live screen's flow selector
  List<AppTab>? tabs,          // renders a themed TabBar when present
  required Widget body,
  bool scrollable = false,
  double? maxContentWidth,     // Insights' 900 becomes a token-driven default
})
```

**Every screen is wrapped in exactly one `AppPage`.** It owns the outer padding
(`tokens.space.pagePadding`), the title row, the tab bar, and the max-width constraint —
so all seven screens finally agree on where content starts and how a title looks.

```dart
PageHeader(...)                              // used internally by AppPage
SectionHeader({String title, String? caption, int? navIndex, List<Widget>? actions})
Toolbar({List<Widget> leading, List<Widget> trailing})
```

`SectionHeader` generalises `overview_page.dart:68-93`'s private one — the chevron +
`navIndex` tap-to-navigate behaviour is good and becomes available everywhere.

---

## 6. Fields

```dart
AppTextField({...})
SearchField({String hint, ValueChanged<String> onChanged, bool autofocus})
AppSelect<T>({T value, List<AppOption<T>> options, ValueChanged<T> onChanged})
AppSwitch({bool value, ValueChanged<bool>? onChanged, String? confirmMessage})
```

`SearchField` replaces three near-identical inline `TextField`s with
`isDense`/`prefixIcon: Icon(Icons.search, size: 18)`/`OutlineInputBorder` —
`library_rail.dart:87`, `insights_page.dart:270`, and the queue tab. It adds what all three
lack: a clear button, a debounce, and `Esc` to clear.

`AppSwitch`'s `confirmMessage` folds in `core/flow_switch_confirm.dart`'s existing
confirm-before-toggle rule so it can't be forgotten on a new switch.

---

## 7. Layout

```dart
ResizableSplit({
  required Widget first, required Widget second,
  Axis axis = Axis.horizontal,
  double initialFirstSize, double minFirst, double minSecond,
  required String persistKey,     // shared_preferences
})
```

The answer to AUDIT §11 — thirteen hardcoded pixel widths, several of which the code itself
flags as tuned to one flow or one window size (`live_page.dart:179-190`). Draggable,
persisted, with `SystemMouseCursors.resizeColumn` on the handle and a keyboard-accessible
grab.

Applied to: Services (list ↔ detail), Library (rails ↔ grid), Live (log ↔ visualization),
Insights ranking (n/a). The hardcoded values become the *initial* sizes, so the app opens
exactly as it does today and the user can change it.

```dart
Gap.xs / .sm / .md / .lg / .xl          // replaces ~200 SizedBox(height/width: N)
AppDivider({bool strong, Axis axis})
MetricRow({String label, Widget value, IconData? icon})
KeyValueList({List<MetricRow> rows, double? labelWidth})
```

`KeyValueList` replaces `run_summary.dart:141-170`'s private `_SummaryRow` (76px label
gutter) and the several label/value stacks in `service_detail.dart`, with the label column
auto-sized to its longest label rather than hardcoded.

---

## 8. Feedback

`LoadingView` / `EmptyView` / `ErrorView` / `AsyncValue.stateView()` move from
`core/async_state_view.dart` into `ui/feedback.dart` **essentially unchanged** — AUDIT's
"do not undo" list is explicit that the shape is right.

Two additions:

- `stateView` gains `emptyWhen` / `emptyView`, so the very common
  `data: (list) => list.isEmpty ? EmptyView(...) : ...` becomes part of the call rather
  than boilerplate at each site.
- `LoadingView` gains a **skeleton** mode. A spinner tells you nothing about what's
  arriving; a skeleton of the layout that's coming reads as faster even at identical
  latency. Applies to the library grid, the ranking table, the flows pipeline and the
  services list — all of which have a known shape before data arrives.

Then **the eleven remaining hand-rolled `.when()` call sites in AUDIT §6 are converted**,
which is a listed acceptance criterion in [PLAN_V2.md](PLAN_V2.md).

---

## 9. Overlays

```dart
AppDialog({String title, Widget body, List<Widget> actions, double? width})
AppTooltip({String message, Widget child, bool rich})
AppMenu / AppMenuItem
AppSnack.show(context, message, {StatusKind kind, SnackAction? action})
```

`AppDialog` gives the three current dialogs one shell — `entity_yield_dialog.dart`,
`shortcuts_reference.dart` and `onboarding.dart` each build their own today (AUDIT §15).
It also standardises focus trapping and `Esc`-to-close.

`AppTooltip` matters more than it sounds: D93 deliberately moved the flow mechanism line
*and* the raw gate condition into a tooltip, so the answer to "why isn't this running?"
now lives inside one. A default Material tooltip is a grey box with no structure —
`rich: true` gives it the theme's overlay surface, real padding, a title/body split and
monospace for the gate formula.

`AppSnack` replaces `core/app_snack_bar.dart`, adding `StatusKind` (today it's a boolean
`isError`) and an optional action button.

---

## 10. Data display

```dart
AppTable<T>({
  List<AppTableColumn<T>> columns,
  List<T> rows,
  void Function(T)? onRowTap,
  AppTableSort? sort, ValueChanged<AppTableSort>? onSort,
  Widget? emptyState,
})

AppTableColumn<T>({
  String label, Widget Function(T) cell,
  double? width,          // null = flexible, absorbs leftover space
  bool numeric, bool sortable, Comparable Function(T)? sortKey,
})
```

This generalises the **hand-built table from D77** — which exists precisely because
Material's `DataTable` cannot make one column flexible while the rest stay fixed. That
lesson is preserved and made reusable: `width: null` = the flexible column, everything else
fixed, exactly the behaviour D77 hand-rolled for the ranking table.

`numeric: true` right-aligns and renders through `NumericText`.

Consumers: the Insights ranking table (existing), the queue tab, the paired-devices list,
the ops job history, and the dependencies tab — all of which are tables rendered four
different ways today.

```dart
Sparkline({List<num> values, num? cap, StatusKind? tone})
```

A tiny inline trend line for the new Overview bento tiles and the flow pipeline nodes — the
last 7 days of a counter at ~60×20, no axes. Not `fl_chart`; a small `CustomPainter`, since
`fl_chart` at that size is all overhead.

---

## 11. Motion helpers

```dart
FadeSlideIn({Widget child, int index = 0, Axis axis = Axis.vertical})
AnimatedReveal({bool visible, Widget child})
PageTransition                      // used by AppShell for destination changes
```

Built on `flutter_animate`. `index` gives list children a small stagger (capped — the first
~8 items only, so a 200-row table doesn't take four seconds to appear).

All of them read `tokens.motion` and collapse to zero under `motion.reduced`. This is where
AUDIT §10's missing motion gets delivered:

| Missing today | Delivered by |
|---|---|
| page transitions | `PageTransition` in `AppShell` — a 240ms fade + 8px slide |
| counter animation | `AnimatedCounter` (§2) |
| the scrape before→after morph (ARCHITECTURE §9, never built) | `AnimatedReveal` in `scrape_surface.dart`, morphing the in-progress strip card into the resolved composite card |
| list insertion | `FadeSlideIn` on log lines, result cards, notifications |
| hover states | `AppPanel(interactive: true)` (§1) |
| theme switching | `AppTokens.lerp` real interpolation (DESIGN_SYSTEM §8) |

---

## 12. Icons

```dart
AppIcon(AppIcons.flow, size: IconSize.md, color: ...)
```

`AppIcons` is a set of **semantic** names — `flow`, `service`, `dependency`, `library`,
`entity`, `insight`, `settings`, `device`, `mirror`, `notification`, `trigger`, `stop`,
`apply`, `discard`, `queue`, `terminal`, `job`, `pair` — each resolving to a Phosphor glyph
at the theme's `iconWeight` (DESIGN_SYSTEM §3).

One file owns the mapping, so changing the glyph for "flow" is a one-line edit rather than
a sweep across 200 call sites, and Swiss's bold weight / Nocturne's light weight apply
automatically everywhere.

---

## 13. Testing the library

Each component gets a case in a new `app/test/ui/` suite. The two that need real assertions
rather than smoke tests:

- **`ResizableSplit`** — respects `minFirst`/`minSecond` at the 1024px window floor, and
  persists/restores correctly.
- **`AppTable`** — the D77 invariant: with one `width: null` column and the rest fixed, the
  flexible column absorbs *all* leftover width and the fixed ones do not grow. This is the
  exact bug D77 fixed by abandoning `DataTable`; it deserves a regression test this time.

Plus `test/theme_contrast_test.dart` (DESIGN_SYSTEM §6) parameterised over all six themes,
and a `test/token_coverage_test.dart` that greps the built package for `Color(0x` outside
`core/theme/` — the acceptance criterion from DESIGN_SYSTEM §1.4, enforced rather than
merely documented.
