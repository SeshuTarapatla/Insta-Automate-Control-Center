# v2 — Design system

The token architecture every theme and component in v2 is built from. Read
[AUDIT.md](AUDIT.md) first for why this is needed; read [THEMES.md](THEMES.md) next for
the concrete values each theme fills these tokens with.

---

## 0. The strategy decision, and why

**v2 builds its own token layer on top of Material 3. It does not adopt `shadcn_ui`,
`forui`, `fluent_ui`, or any other component framework.**

This was a real fork, evaluated rather than assumed:

| Option | Verdict |
|---|---|
| `shadcn_ui` (0.56.0) / `forui` (0.25.0) | Both are excellent and both would mean rewriting all 90 files against a new widget vocabulary. The app's layouts encode roughly a dozen hard-won overflow and constraint fixes (D19, D43–D46, D77, D87, D89, D93) that a rewrite would have to rediscover live, on the user's single screen, against a real pipeline. Also: both are pre-1.0 and moving fast; a breaking release would strand the whole app. |
| `fluent_ui` | Would give Windows-native fidelity for free — but only for the one theme that wants it (Mica). The other five would be fighting it. Adopting a whole framework to serve one of six themes inverts the cost. |
| **Own tokens on Material 3** | Material 3's *components* are fine; what's generic is the default *theme*. `ThemeData` already has ~40 component sub-themes that are entirely unset today (AUDIT §1). Filling those in, driven by a token set, changes the look completely while every existing layout keeps working. |

The insight that makes this work: **the app doesn't look generic because it uses Material —
it looks generic because it uses Material's defaults.** A `Card` with a themed shape,
themed border, themed elevation strategy and themed surface color is not recognisably a
Material `Card`. The widget tree barely changes; the theme does all the work.

Consequence for the implementing session: **you almost never write `Color(0x...)`, a
radius, a font size, or a padding value inside a feature file again.** If you find
yourself reaching for a literal, the token set is missing something — add the token.

### Packages v2 adds

| Package | Version | For |
|---|---|---|
| `flutter_animate` | `^4.5.2` | Declarative entrance/hover/state animations. Replaces hand-rolled `AnimationController`s for everything except `StatusDot` (which stays as-is — see AUDIT "do not undo"). |
| `phosphor_flutter` | `^2.1.0` | Icon set. Material Icons is the single most recognisable "this is a default Flutter app" signal after the color scheme. Phosphor has six weights (thin → fill), which lets *icon weight itself be a theme token* — Command Deck uses `regular`, Nocturne uses `light`, Swiss uses `bold`. That is a genuinely large vibe lever for one dependency. |

Kept as-is: `fl_chart` stays on `^0.69.0` for v2.0.0. The 1.2.0 upgrade is breaking and the
burn-down/funnel work is already large; it is scheduled separately in
[PLAN_V2.md](PLAN_V2.md) as an optional post-2.0.0 item.

Explicitly **not** added: `google_fonts` (runtime download, rejected — see §2),
`animated_theme_switcher` (its whole value is a screenshot-and-crossfade transition; we get
a better result from `AppTokens.lerp` doing real interpolation, see §9).

---

## 1. Token architecture

One `ThemeExtension` holds everything. `core/theme/` is a new directory:

```
core/theme/
  tokens.dart          AppTokens + every sub-token class
  build_theme.dart     AppTokens -> ThemeData (all ~40 component sub-themes)
  density.dart         Density enum + the scale it applies
  theme_controller.dart Riverpod controller + shared_preferences persistence
  themes/
    classic.dart       one file per theme, each returning an AppTokens
    command_deck.dart
    nocturne.dart
    mica.dart
    daylight.dart
    swiss.dart
  registry.dart        id -> builder map, ordered for the picker
```

```dart
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.id,          // ThemeId.commandDeck
    required this.name,        // 'Command Deck'
    required this.tagline,     // one line for the picker
    required this.brightness,
    required this.surface,
    required this.content,
    required this.accent,
    required this.status,
    required this.typography,
    required this.geometry,
    required this.effects,
    required this.space,
    required this.motion,
    required this.chart,
    required this.terminal,
  });
  // ...
}
```

**Never name a field `type`.** `ThemeExtension<T>`'s own `type` getter (`Object get type => T`)
isn't decorative — Flutter uses it as the map key when it builds `ThemeData.extensions` from
the constructor's `extensions: [...]` list. A same-named field silently shadows it, so
`Theme.of(context).extension<AppTokens>()` misses on every lookup and the `AppTokensX.tokens`
fallback fires unconditionally — invisible for as long as only one theme exists (the fallback
and the real value are identical), and a real, live bug the moment a second one does. Found
live in V2.4 (D104) after shipping this way since V2.1; the field is `typography`, not `type`.

`ThemeData.palette` (the existing extension getter in `app_theme.dart:177`) is **kept and
widened** to `ThemeData.tokens`, with `palette` retained as a deprecated alias for one
checkpoint so the migration can be incremental rather than a single 90-file commit.

### 1.1 `SurfaceTokens` — the layer stack

Five named layers, always in this order, so a theme decides *once* how depth reads:

| Token | Role |
|---|---|
| `canvas` | the window background, behind everything |
| `base` | the default panel/card surface |
| `raised` | a card sitting on another card; hovered rows |
| `sunken` | inset wells — terminal body, log console, code blocks, text field interiors |
| `overlay` | dialogs, popovers, menus, tooltips, snackbars |

Plus:

| Token | Role |
|---|---|
| `border` | the default hairline |
| `borderStrong` | emphasised divider, focused field, selected tile |
| `borderSubtle` | barely-there separation inside a panel |
| `scrim` | modal backdrop |

**Surfaces carry alpha.** `Color` values here may be translucent — that is how Mica gets
its layered acrylic and how any future glass theme works, with no special-casing anywhere
in the widget tree. Opaque themes simply use `alpha: 1.0`.

### 1.2 `ContentTokens` — text and icons

| Token | Role |
|---|---|
| `primary` | body text, headings |
| `secondary` | supporting text, subtitles, captions |
| `tertiary` | disabled, placeholder, watermark |
| `onAccent` | text/icon on an accent-filled surface |
| `inverse` | text on an inverted surface (snackbar) |

Three levels, no more. The audit found the app already only ever uses `onSurface` /
`onSurfaceVariant` / a `withValues(alpha: 0.7…0.8)` variant of the latter — this names
that existing practice instead of leaving it to per-call-site alpha arithmetic.

### 1.3 `AccentTokens`

| Token | Role |
|---|---|
| `primary` | the theme's identity color — selection, focus ring, primary button, active nav |
| `onPrimary` | |
| `muted` | accent at low emphasis — selected-row tint, chart fills |
| `secondary` | an optional second hue; a theme may set it equal to `primary` |

**Rule: accent never encodes state.** Green does not mean "accent" in Command Deck just
because the accent happens to be greenish. State is `StatusTokens`, exclusively.

### 1.4 `StatusTokens` — the meaning layer

Four states, each with a foreground, a container and an on-container:

| State | Means | Current usage it replaces |
|---|---|---|
| `good` | running, connected, ok, succeeded | `AppPalette.statusGood`, `Colors.green` ×2, `Color(0xFF3DD68C)` ×2 |
| `info` | starting, connecting, waiting, in progress | `AppPalette.statusInfo`, `Colors.blueAccent` |
| `warn` | backoff, unhealthy, blocked, degraded, gated | `AppPalette.statusWarn`, `Colors.amber.shade700`, `Colors.orangeAccent` ×2, `Color(0xFFFFB454)` |
| `bad` | failed, disconnected, error, cancelled | `colorScheme.error` |

Every one of the 13 hardcoded colors in AUDIT §2 maps onto one of these. **After the token
migration, `grep -rn "Color(0x" app/lib --include=*.dart | grep -v core/theme/` must return
nothing** (the QR quiet zone excepted, and tokened as `chart.qrQuietZone`). That grep is a
literal acceptance criterion in [PLAN_V2.md](PLAN_V2.md).

All four states must satisfy **4.5:1 contrast against `surface.base`** in every theme, and
be distinguishable from each other for the most common forms of color blindness — which is
why status is never carried by hue alone: `StatusDot` keeps its pulse for transient states,
and every status chip pairs its color with a word or an icon.

### 1.5 `TypographyTokens`

```dart
class TypographyTokens {
  final String display;     // headings — may differ from body
  final String body;        // prose, labels
  final String mono;        // ALL numerics, IDs, paths, terminal, code
  final double scale;       // theme-level size multiplier (Swiss runs tighter)
  final double bodyHeight;  // line height multiplier
  final double tightTracking;   // headings
  final double looseTracking;   // uppercase micro-labels
  final FontWeight bodyWeight;
  final FontWeight headingWeight;
  final bool uppercaseLabels;   // Swiss/Command yes, Nocturne no
}
```

Two hard rules, both fixing audit findings:

1. **`mono` is the single source for every monospace face.** The three spellings in AUDIT
   §7 all become `tokens.typography.mono`. This includes `TerminalStyle`'s `fontFamily` in
   `service_terminal.dart:465`.
2. **Every number renders with `FontFeature.tabularFigures()`.** A `MonoText` /
   `NumericText` component (see [COMPONENTS.md](COMPONENTS.md)) enforces it so it can't be
   forgotten. This fixes AUDIT §8 — the countdown ring, counters, latencies, and the
   ranking table all stop jittering.

### 1.6 `GeometryTokens`

```dart
class GeometryTokens {
  final double radiusSm;    // chips, badges, small buttons
  final double radiusMd;    // cards, panels, fields
  final double radiusLg;    // dialogs, popovers
  final double radiusFull;  // pills, avatars — usually 999
  final double borderWidth;       // 1.0 everywhere except Swiss/brutalist
  final double borderWidthStrong;
  final double focusRingWidth;
  final double hairline;    // dividers — may be < 1 on high-DPI
}
```

Radius is one of the strongest vibe levers available: Swiss at `0`, Command Deck at `4`,
Mica at `8`, Daylight at `10`, Classic at `12`, Nocturne at `14`. Same widgets, six
distinctly different products.

### 1.7 `EffectTokens` — depth strategy

```dart
enum DepthStrategy { border, shadow, both, glow }

class EffectTokens {
  final DepthStrategy depth;
  final List<BoxShadow> shadowSm;
  final List<BoxShadow> shadowMd;
  final List<BoxShadow> shadowLg;
  final double surfaceBlur;    // > 0 only for translucent themes (Mica)
  final bool hoverLift;        // does hover raise, or only tint?
  final double hoverTintAlpha;
}
```

This is the token that most decides whether a theme reads as flat, layered, or glassy.
Command Deck is `border` with all shadows empty — depth comes entirely from hairlines and
surface steps. Daylight is `shadow`. Mica is `both` with `surfaceBlur > 0`. Nocturne is
`glow` (a soft accent-tinted shadow).

`build_theme.dart` reads `depth` once and configures `cardTheme`, `dialogTheme`,
`popupMenuTheme`, `menuTheme`, `dropdownMenuTheme` and `bottomSheetTheme` consistently, so
a theme can never end up with bordered cards and shadowed dialogs by accident.

### 1.8 `SpacingTokens` and density

A 4px base scale: `xs 4 · sm 8 · md 12 · lg 16 · xl 24 · xxl 32 · xxxl 48`.

Plus semantic measures that the audit showed were being reinvented per screen:

| Token | Replaces |
|---|---|
| `pagePadding` | the six different page paddings in AUDIT §3 |
| `cardPadding` | the `all(16)` repeated at 9 call sites |
| `sectionGap` | the `SizedBox(height: 28)` / `32` / `20` mix |
| `controlHeight` | button/field height — the `SizedBox(height: 32)` / `36` literals |
| `rowHeight` | list/table row height |
| `iconSm / iconMd / iconLg` | the `size: 14` / `15` / `16` / `18` / `20` / `24` / `28` / `32` spread |

**Density** (`density.dart`) is a multiplier applied to `SpacingTokens`, `rowHeight`,
`controlHeight` and `typography.scale` when the theme is built. Three tiers, added
2026-08-05 once `compact` existed and a roomier third tier was an obvious next ask:

| Density | Space × | Type × | For |
|---|---|---|---|
| `compact` | 0.75 | 0.95 | dense ops use; Command Deck's own default |
| `comfortable` | 1.0 | 1.0 | default |
| `spacious` | 1.15 | 1.05 | more room to breathe than the default |

Density is a real user setting persisted alongside the theme choice, per the session's
answers. Because it is applied at `ThemeData` build time, **nothing in any feature file
knows density exists** — it is entirely a token concern.

### 1.9 `MotionTokens`

```dart
class MotionTokens {
  final Duration instant;  // 90ms  — hover, tint, focus ring
  final Duration quick;    // 160ms — chips, badges, small state changes
  final Duration standard; // 240ms — page transitions, panel swaps, dialogs
  final Duration slow;     // 400ms — theme switch, hero morphs
  final Curve enter;       // easeOutCubic
  final Curve exit;        // easeInCubic
  final Curve emphasis;    // easeOutBack — used sparingly
  final bool reduced;      // honours the OS reduce-motion preference
}
```

`reduced` collapses every duration to `Duration.zero` at build time. It reads
`MediaQuery.disableAnimations` (which Windows' "Show animations" setting drives) and can
also be forced from Settings.

**Motion doctrine** — carried forward verbatim from ARCHITECTURE §9's "nothing decorative":

- Motion may show **causality** (this appeared because that happened), **continuity**
  (this is the same object, moved), or **state** (this is still working).
- Motion may not decorate. No bounce on load, no stagger for its own sake, nothing that
  delays a user who already knows what they want.
- Anything that repeats forever must mean "still in progress" — `StatusDot`'s pulse is the
  reference implementation and the reason it survives v2 untouched.

### 1.10 `ChartTokens`

`fl_chart` is themed today only by whatever `colorScheme` values each chart file reaches
for. v2 gives it real tokens: `series` (an ordered list for multi-series), `grid`, `axis`,
`axisLabel`, `capLine` (the burn-down's dashed cap), `positiveFill`, `qrQuietZone`.

Follow the `dataviz` skill's guidance for the palette itself — it is already the basis for
the D78 funnel and the five small-multiple burn-down charts, and those decisions stand.

---

## 2. Typography — the concrete choice

**Bundled as assets. Two families ship in v2.0.0.**

| Family | Role | Source |
|---|---|---|
| **Inter** (Variable) | `display` + `body` for Classic, Command Deck, Nocturne, Daylight, Swiss | github.com/rsms/inter — `InterVariable.ttf`, `InterVariable-Italic.ttf`, SIL OFL |
| **JetBrains Mono** | `mono` for every theme | github.com/JetBrains/JetBrainsMono — Regular/Medium/Bold, SIL OFL |

Mica is the deliberate exception: it uses **Segoe UI Variable** and **Cascadia Mono** from
the OS, because a theme whose entire point is "this shipped with Windows" must not bring
its own typeface. Declared as a plain family-name string with Inter/JetBrains Mono as the
fallback so it degrades safely.

Why bundled rather than `google_fonts`: this is a deliberately LAN-only app on a machine
that also runs the pipeline. A runtime font fetch adds a network dependency to a tool whose
whole premise is local operation, and renders the first cold launch in a fallback face.
~1.6 MB of assets is a trivially better trade.

Inter over Roboto because Roboto *is* the "default Flutter app" signal, and Inter's
tabular-figures and slashed-zero OpenType features are exactly what a numeric dashboard
needs. Both features are enabled through the `MonoText`/`NumericText` components.

**Implementation note for the build session:** the `.ttf` files must be downloaded and
committed under `app/assets/fonts/`. Licenses (`OFL.txt`) go alongside them. Both are
SIL OFL 1.1 — redistribution in an application bundle is explicitly permitted. Wire them
in `pubspec.yaml` under `flutter: fonts:`, with Inter declared as a variable font.

### The type scale

Nine roles, mapped onto Material's `TextTheme` slots so existing `theme.textTheme.*` calls
keep working during the migration:

| Role | Material slot | Size (comfortable) | Weight | Tracking |
|---|---|---|---|---|
| `pageTitle` | `headlineSmall` | 22 | heading | tight |
| `sectionTitle` | `titleLarge` | 17 | heading | tight |
| `cardTitle` | `titleMedium` | 15 | 600 | normal |
| `subTitle` | `titleSmall` | 13 | 600 | normal |
| `body` | `bodyMedium` | 13.5 | body | normal |
| `bodyStrong` | `bodyLarge` | 14 | 600 | normal |
| `caption` | `bodySmall` | 12 | body | normal |
| `label` | `labelMedium` | 12 | 600 | normal |
| `micro` | `labelSmall` | 10.5 | 700 | loose (uppercase where the theme opts in) |

All sizes multiply by `typography.scale × density.typeScale`.

---

## 3. Iconography

Phosphor replaces Material Icons app-wide. The weight is a theme token
(`typography` carries it as `iconWeight`), which is a large and cheap differentiator:

| Theme | Phosphor weight |
|---|---|
| Classic | `regular` (closest to Material's look) |
| Command Deck | `regular` |
| Nocturne | `light` |
| Mica | `regular` |
| Daylight | `regular` |
| Swiss | `bold` |

A single `AppIcon` widget resolves `(semantic name, theme weight) → PhosphorIconData`, so
the mapping lives in one file rather than being re-chosen at 200 call sites. Semantic names
(`AppIcons.flow`, `AppIcons.service`, `AppIcons.library`) rather than glyph names, so the
glyph can change without a sweep.

Sizes come from `space.iconSm/Md/Lg` (14 / 18 / 24 at comfortable), replacing the eight
different literal sizes AUDIT §1.8 found.

---

## 4. Elevation and layering — the rule

The audit found `Card`, `Material + InkWell + Container + Border`, and bare
`Container + BoxDecoration` all used for the same job. v2 has exactly one rule:

> **Depth is expressed once, by `EffectTokens.depth`, and applied by `build_theme.dart`.
> Feature code never sets `elevation`, never sets a `BoxShadow`, and never draws its own
> border.**

Feature code chooses a *semantic* container (`AppPanel`, `AppCard`, `AppWell`,
`AppOverlay` — see [COMPONENTS.md](COMPONENTS.md)) and the theme decides whether that
reads as a shadow, a hairline, a surface step, or a glow.

---

## 5. Interaction states

Every interactive surface must render five states. Today most render two (default and
`InkWell` splash), which is the concrete reason the app "feels flat" under a mouse.

| State | Treatment |
|---|---|
| default | `surface.base` |
| hover | `surface.raised`, or an accent tint at `effects.hoverTintAlpha`; plus a lift if `effects.hoverLift` |
| focus | a `focusRingWidth` ring in `accent.primary`, always visible, never removed for aesthetics |
| pressed | one step beyond hover, `motion.instant` |
| disabled | `content.tertiary` foreground, no border emphasis, no pointer cursor |

Plus, for desktop specifically: **`MouseCursor` is set correctly everywhere.**
`SystemMouseCursors.click` on actions, `.text` on selectable text, `.resizeColumn` on the
new draggable pane dividers. Today the app uses the default arrow almost everywhere, which
is a small thing that reads strongly as "unfinished desktop app."

---

## 6. Accessibility floor

Not optional, and cheap to hold if done from the start:

- 4.5:1 contrast for body text, 3:1 for large text and UI boundaries, in **every** theme.
  A `test/theme_contrast_test.dart` asserts this across all six themes × all status colors
  × all surface layers, so a future palette tweak can't silently break it.
- Status never by hue alone (§1.4).
- Every icon-only button has a `tooltip` **and** a `Semantics` label. The audit found
  several icon buttons with tooltips (good) but the pattern isn't universal.
- Focus order follows visual order; every dialog traps focus and restores it on close.
- `motion.reduced` honours the OS setting (§1.9).

---

## 7. Window and shell

- Minimum window stays `1024×700` (`main.dart:12`). **Every layout must survive that
  floor** — this is what the ten existing layout tests exist to enforce, and v2 adds one
  per new screen.
- Three breakpoints, named in tokens so screens branch consistently rather than each
  inventing a `LayoutBuilder` threshold:
  `compact < 1100` · `medium 1100–1500` · `wide ≥ 1500`.
  The real production window (filling the space right of the scrcpy mirror, ~1250×1400
  logical on this machine per `main.dart`'s geometry math) lands in `medium` — **so
  `medium` is the design target, not `wide`.** This is a genuinely unusual aspect ratio:
  tall and narrow-ish. Screens should prefer vertical stacking over wide multi-column
  layouts. See [VISUAL_INPUTS.md](VISUAL_INPUTS.md) — a screenshot at the real size is the
  highest-value input the user can provide.
- Mica stays enabled, and v2 finally *uses* it (AUDIT §9): `surface.canvas` becomes fully
  transparent and the nav rail + page background become translucent in the Mica theme, so
  the desktop actually shows through the chrome. Opaque themes set alpha 1.0 and are
  unaffected.

---

## 8. Theme switching

- `theme_controller.dart` — a Riverpod `Notifier` holding `(ThemeId, Density)`, persisted
  to `shared_preferences`. Mirrors `MutedTagsController` and `onboarding.dart`'s existing
  pattern exactly (CP 6.3 / CP 7.3), so there is no new persistence mechanism.
- The picker lives in **Settings → a new "Appearance" tab**, as a grid of live preview
  cards — each card renders a real miniature of the app chrome in that theme, not a color
  swatch. Also reachable from the command palette (`> Theme: Command Deck`).
- The switch animates rather than hard-cutting. `AppTokens.lerp` implements **real
  interpolation** — `Color.lerp` for every color, `lerpDouble` for every measure — unlike
  today's `AppPalette.lerp` which deliberately snaps at `t < 0.5` (`app_theme.dart:56`).
  Fonts and `DepthStrategy` can't interpolate, so they snap at the midpoint while colors
  and geometry sweep; at `motion.slow` (400ms) that reads as one continuous change.
- **Mica is special-cased**: switching *to* or *from* it calls
  `Window.setEffect(...)`, which is a native window-level change and cannot animate. Accept
  the hard cut there and document it.

---

## 9. Migration discipline

The theme migration touches every file. To keep it reviewable and to keep the app running
throughout:

1. `AppTokens` lands with **`ThemeData.palette` still working** as a deprecated shim that
   reads from the new tokens. Nothing breaks on day one.
2. Files migrate feature-by-feature, one checkpoint at a time (see
   [PLAN_V2.md](PLAN_V2.md)), each ending with `flutter analyze` clean and all layout tests
   green.
3. The shim is deleted in the final theming checkpoint, and the
   `grep -rn "Color(0x" app/lib --include=*.dart | grep -v core/theme/` acceptance check
   must come back empty.
4. **No screen re-architecture happens in the same commit as its theme migration.** Theme
   first, then layout — otherwise a visual regression is impossible to attribute.
