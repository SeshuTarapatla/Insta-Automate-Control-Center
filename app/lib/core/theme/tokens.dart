// v2 token architecture — DESIGN_SYSTEM.md §1. One `ThemeExtension` (`AppTokens`)
// holds everything a theme needs; `build_theme.dart` is the only place that turns
// these into a `ThemeData`. Feature code reads tokens, never literals — DESIGN_SYSTEM
// §0's rule: "you almost never write `Color(0x...)`, a radius, a font size, or a
// padding value inside a feature file again."
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:xterm/xterm.dart';

import 'themes/classic.dart';

/// One entry per shipping theme (THEMES.md §1). Only `classic` exists as a real
/// theme through V2.1 — the other five land in V2.4.
enum ThemeId { classic }

/// DESIGN_SYSTEM §1.1 — the layer stack. Always in this order, so a theme decides
/// *once* how depth reads. Colors here may carry alpha: that's how Mica's acrylic
/// works with zero special-casing in the widget tree (opaque themes just use
/// alpha 1.0).
@immutable
class SurfaceTokens {
  const SurfaceTokens({
    required this.canvas,
    required this.base,
    required this.raised,
    required this.sunken,
    required this.overlay,
    required this.border,
    required this.borderStrong,
    required this.borderSubtle,
    required this.scrim,
  });

  /// The window background, behind everything.
  final Color canvas;

  /// The default panel/card surface.
  final Color base;

  /// A card sitting on another card; hovered rows.
  final Color raised;

  /// Inset wells — terminal body, log console, code blocks, text field interiors.
  final Color sunken;

  /// Dialogs, popovers, menus, tooltips, snackbars.
  final Color overlay;

  /// The default hairline.
  final Color border;

  /// Emphasised divider, focused field, selected tile.
  final Color borderStrong;

  /// Barely-there separation inside a panel.
  final Color borderSubtle;

  /// Modal backdrop.
  final Color scrim;
}

/// DESIGN_SYSTEM §1.2 — text and icons. Three levels, no more.
@immutable
class ContentTokens {
  const ContentTokens({
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.onAccent,
    required this.inverse,
  });

  /// Body text, headings.
  final Color primary;

  /// Supporting text, subtitles, captions.
  final Color secondary;

  /// Disabled, placeholder, watermark.
  final Color tertiary;

  /// Text/icon on an accent-filled surface.
  final Color onAccent;

  /// Text on an inverted surface (snackbar).
  final Color inverse;
}

/// DESIGN_SYSTEM §1.3. Rule: accent never encodes state — that's `StatusTokens`,
/// exclusively.
@immutable
class AccentTokens {
  const AccentTokens({required this.primary, required this.onPrimary, required this.muted, required this.secondary});

  /// The theme's identity color — selection, focus ring, primary button, active nav.
  final Color primary;

  final Color onPrimary;

  /// Accent at low emphasis — selected-row tint, chart fills.
  final Color muted;

  /// An optional second hue; a theme may set it equal to `primary`.
  final Color secondary;
}

/// One state's three colors — DESIGN_SYSTEM §1.4.
@immutable
class StatusColor {
  const StatusColor({required this.fg, required this.container, required this.onContainer});

  final Color fg;
  final Color container;
  final Color onContainer;
}

/// DESIGN_SYSTEM §1.4 — the meaning layer. Four states; status is never carried
/// by hue alone (`StatusDot` keeps its pulse, every status chip pairs color with
/// a word or icon).
@immutable
class StatusTokens {
  const StatusTokens({required this.good, required this.info, required this.warn, required this.bad});

  /// Running, connected, ok, succeeded.
  final StatusColor good;

  /// Starting, connecting, waiting, in progress.
  final StatusColor info;

  /// Backoff, unhealthy, blocked, degraded, gated.
  final StatusColor warn;

  /// Failed, disconnected, error, cancelled.
  final StatusColor bad;
}

/// DESIGN_SYSTEM §1.5. `mono` is the single source for every monospace face —
/// the three spellings AUDIT §7 found (`'Consolas'`, `'monospace'`,
/// `TerminalStyle`'s own literal) all become `tokens.type.mono`.
@immutable
class TypographyTokens {
  const TypographyTokens({
    required this.display,
    required this.body,
    required this.mono,
    required this.scale,
    required this.bodyHeight,
    required this.tightTracking,
    required this.looseTracking,
    required this.bodyWeight,
    required this.headingWeight,
    required this.uppercaseLabels,
    required this.iconWeight,
  });

  /// Headings — may differ from body.
  final String display;

  /// Prose, labels.
  final String body;

  /// ALL numerics, IDs, paths, terminal, code.
  final String mono;

  /// Theme-level size multiplier (Swiss runs tighter).
  final double scale;

  /// Line height multiplier.
  final double bodyHeight;

  final double tightTracking;
  final double looseTracking;
  final FontWeight bodyWeight;
  final FontWeight headingWeight;

  /// Swiss/Command Deck yes, Nocturne no.
  final bool uppercaseLabels;

  /// A theme token (DESIGN_SYSTEM §3) — Phosphor ships six weights, so icon
  /// weight itself becomes a per-theme vibe lever for one dependency.
  final PhosphorIconsStyle iconWeight;
}

/// DESIGN_SYSTEM §1.6. Radius is one of the strongest vibe levers available:
/// same widgets, six distinctly different products.
@immutable
class GeometryTokens {
  const GeometryTokens({
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusLg,
    required this.radiusFull,
    required this.borderWidth,
    required this.borderWidthStrong,
    required this.focusRingWidth,
    required this.hairline,
  });

  /// Chips, badges, small buttons.
  final double radiusSm;

  /// Cards, panels, fields.
  final double radiusMd;

  /// Dialogs, popovers.
  final double radiusLg;

  /// Pills, avatars — usually 999.
  final double radiusFull;

  /// 1.0 everywhere except Swiss/brutalist.
  final double borderWidth;
  final double borderWidthStrong;
  final double focusRingWidth;

  /// Dividers — may be < 1 on high-DPI.
  final double hairline;
}

/// DESIGN_SYSTEM §1.7 — the token that most decides whether a theme reads as
/// flat, layered, or glassy. `build_theme.dart` reads `depth` once and
/// configures every card/dialog/menu-shaped sub-theme consistently, so a theme
/// can never end up with bordered cards and shadowed dialogs by accident.
enum DepthStrategy { border, shadow, both, glow }

@immutable
class EffectTokens {
  const EffectTokens({
    required this.depth,
    required this.shadowSm,
    required this.shadowMd,
    required this.shadowLg,
    required this.surfaceBlur,
    required this.hoverLift,
    required this.hoverTintAlpha,
  });

  final DepthStrategy depth;
  final List<BoxShadow> shadowSm;
  final List<BoxShadow> shadowMd;
  final List<BoxShadow> shadowLg;

  /// > 0 only for translucent themes (Mica).
  final double surfaceBlur;

  /// Does hover raise, or only tint?
  final bool hoverLift;
  final double hoverTintAlpha;
}

/// DESIGN_SYSTEM §1.8 — a 4px base scale, plus the semantic measures the audit
/// found being reinvented per screen (six page paddings, `all(16)` at nine call
/// sites, a `SizedBox(height: ...)` mix, etc).
@immutable
class SpacingTokens {
  const SpacingTokens({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.xxl,
    required this.xxxl,
    required this.pagePadding,
    required this.cardPadding,
    required this.sectionGap,
    required this.controlHeight,
    required this.rowHeight,
    required this.iconSm,
    required this.iconMd,
    required this.iconLg,
  });

  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double xxl;
  final double xxxl;

  final double pagePadding;
  final double cardPadding;
  final double sectionGap;
  final double controlHeight;
  final double rowHeight;
  final double iconSm;
  final double iconMd;
  final double iconLg;

  /// Applies `density`'s space multiplier (DESIGN_SYSTEM §1.8) to every
  /// measure. Called once, at theme-build time — nothing in a feature file
  /// knows density exists.
  SpacingTokens scaled(double factor) => SpacingTokens(
    xs: xs * factor,
    sm: sm * factor,
    md: md * factor,
    lg: lg * factor,
    xl: xl * factor,
    xxl: xxl * factor,
    xxxl: xxxl * factor,
    pagePadding: pagePadding * factor,
    cardPadding: cardPadding * factor,
    sectionGap: sectionGap * factor,
    controlHeight: controlHeight * factor,
    rowHeight: rowHeight * factor,
    iconSm: iconSm * factor,
    iconMd: iconMd * factor,
    iconLg: iconLg * factor,
  );
}

/// DESIGN_SYSTEM §1.9. `reduced` collapses every duration to zero at build time
/// — it's what makes Windows' "Show animations: off" actually work, and what
/// Settings' own override drives.
@immutable
class MotionTokens {
  const MotionTokens({
    required this.instant,
    required this.quick,
    required this.standard,
    required this.slow,
    required this.enter,
    required this.exit,
    required this.emphasis,
    required this.reduced,
  });

  /// Hover, tint, focus ring.
  final Duration instant;

  /// Chips, badges, small state changes.
  final Duration quick;

  /// Page transitions, panel swaps, dialogs.
  final Duration standard;

  /// Theme switch, hero morphs.
  final Duration slow;

  final Curve enter;
  final Curve exit;

  /// Used sparingly.
  final Curve emphasis;

  final bool reduced;
}

/// DESIGN_SYSTEM §1.10. `fl_chart` gets real tokens instead of reaching into
/// `colorScheme` ad hoc per chart file.
@immutable
class ChartTokens {
  const ChartTokens({
    required this.series,
    required this.grid,
    required this.axis,
    required this.axisLabel,
    required this.capLine,
    required this.positiveFill,
    required this.qrQuietZone,
  });

  /// An ordered list for multi-series charts.
  final List<Color> series;

  final Color grid;
  final Color axis;
  final Color axisLabel;

  /// The burn-down's dashed cap line.
  final Color capLine;

  final Color positiveFill;

  /// The one literal `Color(0x...)` the token-coverage grep excepts (V2.3).
  final Color qrQuietZone;
}

/// `service_terminal.dart`'s previously-inline `TerminalTheme` — same colors,
/// just named, reused, and now theme-driven instead of hardcoded to one dark
/// palette (Tokyo Night). `TerminalPalette.light` (THEMES.md §8) lands in V2.4
/// for Daylight/Swiss.
@immutable
class TerminalPalette {
  const TerminalPalette({
    required this.foreground,
    required this.background,
    required this.black,
    required this.red,
    required this.green,
    required this.yellow,
    required this.blue,
    required this.magenta,
    required this.cyan,
    required this.white,
    required this.brightBlack,
    required this.brightRed,
    required this.brightGreen,
    required this.brightYellow,
    required this.brightBlue,
    required this.brightMagenta,
    required this.brightCyan,
    required this.brightWhite,
    required this.searchHitBackground,
    required this.searchHitBackgroundCurrent,
    required this.searchHitForeground,
    required this.panelBackground,
    required this.headerBackground,
  });

  final Color foreground;
  final Color background;
  final Color black;
  final Color red;
  final Color green;
  final Color yellow;
  final Color blue;
  final Color magenta;
  final Color cyan;
  final Color white;
  final Color brightBlack;
  final Color brightRed;
  final Color brightGreen;
  final Color brightYellow;
  final Color brightBlue;
  final Color brightMagenta;
  final Color brightCyan;
  final Color brightWhite;
  final Color searchHitBackground;
  final Color searchHitBackgroundCurrent;
  final Color searchHitForeground;

  /// The pane's own container background — same as `background` today, kept
  /// as a separate name since the terminal body and its chrome are
  /// conceptually different surfaces even though they currently match.
  final Color panelBackground;

  /// The header/search-bar strip, one step lighter than the pane itself.
  final Color headerBackground;

  static const dark = TerminalPalette(
    foreground: Color(0xFFD5D6E0),
    background: Color(0xFF12121A),
    black: Color(0xFF15151E),
    red: Color(0xFFF7768E),
    green: Color(0xFF3DD68C),
    yellow: Color(0xFFE0AF68),
    blue: Color(0xFF7AA2F7),
    magenta: Color(0xFFBB9AF7),
    cyan: Color(0xFF7DCFFF),
    white: Color(0xFFC0CAF5),
    brightBlack: Color(0xFF6B6F8C),
    brightRed: Color(0xFFFF8FA3),
    brightGreen: Color(0xFF64E3A6),
    brightYellow: Color(0xFFF3C77B),
    brightBlue: Color(0xFF9AB8FF),
    brightMagenta: Color(0xFFD0B4FF),
    brightCyan: Color(0xFF9FE0FF),
    brightWhite: Color(0xFFEDEFFA),
    searchHitBackground: Color(0xFFFFB454),
    searchHitBackgroundCurrent: Color(0xFF3DD68C),
    searchHitForeground: Color(0xFF12121A),
    panelBackground: Color(0xFF12121A),
    headerBackground: Color(0xFF1A1A24),
  );

  /// Adapts to `xterm`'s own theme type at the one call site that needs it,
  /// so nothing outside `service_terminal.dart` needs to import `xterm`.
  TerminalTheme toXterm({required Color cursor, required Color selection}) => TerminalTheme(
    cursor: cursor,
    selection: selection,
    foreground: foreground,
    background: background,
    black: black,
    red: red,
    green: green,
    yellow: yellow,
    blue: blue,
    magenta: magenta,
    cyan: cyan,
    white: white,
    brightBlack: brightBlack,
    brightRed: brightRed,
    brightGreen: brightGreen,
    brightYellow: brightYellow,
    brightBlue: brightBlue,
    brightMagenta: brightMagenta,
    brightCyan: brightCyan,
    brightWhite: brightWhite,
    searchHitBackground: searchHitBackground,
    searchHitBackgroundCurrent: searchHitBackgroundCurrent,
    searchHitForeground: searchHitForeground,
  );
}

/// DESIGN_SYSTEM §1 — everything a theme needs, in one `ThemeExtension`.
/// `build_theme.dart` is the only file that reads this to produce a
/// `ThemeData`; feature code reaches for `Theme.of(context).tokens` instead
/// of any of the sub-groups directly, so a future rename only touches one
/// call site shape.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.id,
    required this.name,
    required this.tagline,
    required this.brightness,
    required this.surface,
    required this.content,
    required this.accent,
    required this.status,
    required this.type,
    required this.geometry,
    required this.effects,
    required this.space,
    required this.motion,
    required this.chart,
    required this.terminal,
  });

  final ThemeId id;

  /// e.g. 'Command Deck'.
  final String name;

  /// One line for the theme picker (V2.4).
  final String tagline;

  final Brightness brightness;
  final SurfaceTokens surface;
  final ContentTokens content;
  final AccentTokens accent;
  final StatusTokens status;

  // Shadows `ThemeExtension<T>.type` (`Object get type => T`) — a same-named
  // field is a valid narrowing override in Dart, just needs the annotation.
  @override
  final TypographyTokens type;
  final GeometryTokens geometry;
  final EffectTokens effects;
  final SpacingTokens space;
  final MotionTokens motion;
  final ChartTokens chart;
  final TerminalPalette terminal;

  @override
  AppTokens copyWith({
    ThemeId? id,
    String? name,
    String? tagline,
    Brightness? brightness,
    SurfaceTokens? surface,
    ContentTokens? content,
    AccentTokens? accent,
    StatusTokens? status,
    TypographyTokens? type,
    GeometryTokens? geometry,
    EffectTokens? effects,
    SpacingTokens? space,
    MotionTokens? motion,
    ChartTokens? chart,
    TerminalPalette? terminal,
  }) => AppTokens(
    id: id ?? this.id,
    name: name ?? this.name,
    tagline: tagline ?? this.tagline,
    brightness: brightness ?? this.brightness,
    surface: surface ?? this.surface,
    content: content ?? this.content,
    accent: accent ?? this.accent,
    status: status ?? this.status,
    type: type ?? this.type,
    geometry: geometry ?? this.geometry,
    effects: effects ?? this.effects,
    space: space ?? this.space,
    motion: motion ?? this.motion,
    chart: chart ?? this.chart,
    terminal: terminal ?? this.terminal,
  );

  /// Only one theme exists through V2.1, so there is nothing to interpolate
  /// between yet — this snaps at the midpoint the same way the `AppPalette`
  /// it replaces did. `AppTokens.lerp` gains **real** per-field interpolation
  /// in V2.4 (DESIGN_SYSTEM §8), once switching between six themes is a real
  /// user action worth animating.
  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return t < 0.5 ? this : other;
  }
}

/// The app always registers an `AppTokens` extension (`build_theme.dart`), so
/// this is the one call site every feature file goes through. Falls back to
/// Classic — same reasoning as the `AppPalette` shim it's replacing: widget
/// tests that build their own bare `ThemeData()` with no theme wiring at all
/// still need a sane value, and this app has exactly one dark baseline.
extension AppTokensX on ThemeData {
  AppTokens get tokens => extension<AppTokens>() ?? buildClassicTokens();
}
