// v2 token architecture — DESIGN_SYSTEM.md §1. One `ThemeExtension` (`AppTokens`)
// holds everything a theme needs; `build_theme.dart` is the only place that turns
// these into a `ThemeData`. Feature code reads tokens, never literals — DESIGN_SYSTEM
// §0's rule: "you almost never write `Color(0x...)`, a radius, a font size, or a
// padding value inside a feature file again."
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:xterm/xterm.dart';

import 'themes/classic.dart';

/// One entry per shipping theme (THEMES.md §1), in picker order.
enum ThemeId { classic, commandDeck, nocturne, mica, daylight, swiss }

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

  static SurfaceTokens lerp(SurfaceTokens a, SurfaceTokens b, double t) => SurfaceTokens(
    canvas: Color.lerp(a.canvas, b.canvas, t)!,
    base: Color.lerp(a.base, b.base, t)!,
    raised: Color.lerp(a.raised, b.raised, t)!,
    sunken: Color.lerp(a.sunken, b.sunken, t)!,
    overlay: Color.lerp(a.overlay, b.overlay, t)!,
    border: Color.lerp(a.border, b.border, t)!,
    borderStrong: Color.lerp(a.borderStrong, b.borderStrong, t)!,
    borderSubtle: Color.lerp(a.borderSubtle, b.borderSubtle, t)!,
    scrim: Color.lerp(a.scrim, b.scrim, t)!,
  );
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

  static ContentTokens lerp(ContentTokens a, ContentTokens b, double t) => ContentTokens(
    primary: Color.lerp(a.primary, b.primary, t)!,
    secondary: Color.lerp(a.secondary, b.secondary, t)!,
    tertiary: Color.lerp(a.tertiary, b.tertiary, t)!,
    onAccent: Color.lerp(a.onAccent, b.onAccent, t)!,
    inverse: Color.lerp(a.inverse, b.inverse, t)!,
  );
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

  static AccentTokens lerp(AccentTokens a, AccentTokens b, double t) => AccentTokens(
    primary: Color.lerp(a.primary, b.primary, t)!,
    onPrimary: Color.lerp(a.onPrimary, b.onPrimary, t)!,
    muted: Color.lerp(a.muted, b.muted, t)!,
    secondary: Color.lerp(a.secondary, b.secondary, t)!,
  );
}

/// One state's three colors — DESIGN_SYSTEM §1.4.
@immutable
class StatusColor {
  const StatusColor({required this.fg, required this.container, required this.onContainer});

  final Color fg;
  final Color container;
  final Color onContainer;

  static StatusColor lerp(StatusColor a, StatusColor b, double t) => StatusColor(
    fg: Color.lerp(a.fg, b.fg, t)!,
    container: Color.lerp(a.container, b.container, t)!,
    onContainer: Color.lerp(a.onContainer, b.onContainer, t)!,
  );
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

  static StatusTokens lerp(StatusTokens a, StatusTokens b, double t) => StatusTokens(
    good: StatusColor.lerp(a.good, b.good, t),
    info: StatusColor.lerp(a.info, b.info, t),
    warn: StatusColor.lerp(a.warn, b.warn, t),
    bad: StatusColor.lerp(a.bad, b.bad, t),
  );
}

/// DESIGN_SYSTEM §1.5. `mono` is the single source for every monospace face —
/// the three spellings AUDIT §7 found (`'Consolas'`, `'monospace'`,
/// `TerminalStyle`'s own literal) all become `tokens.typography.mono`.
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

  /// DESIGN_SYSTEM §8 — sizes and weights sweep; face names and the
  /// uppercase/icon-weight choices can't interpolate, so they snap at the
  /// midpoint the same way `DepthStrategy` does (`EffectTokens.lerp`).
  static TypographyTokens lerp(TypographyTokens a, TypographyTokens b, double t) => TypographyTokens(
    display: t < 0.5 ? a.display : b.display,
    body: t < 0.5 ? a.body : b.body,
    mono: t < 0.5 ? a.mono : b.mono,
    scale: lerpDouble(a.scale, b.scale, t)!,
    bodyHeight: lerpDouble(a.bodyHeight, b.bodyHeight, t)!,
    tightTracking: lerpDouble(a.tightTracking, b.tightTracking, t)!,
    looseTracking: lerpDouble(a.looseTracking, b.looseTracking, t)!,
    bodyWeight: FontWeight.lerp(a.bodyWeight, b.bodyWeight, t)!,
    headingWeight: FontWeight.lerp(a.headingWeight, b.headingWeight, t)!,
    uppercaseLabels: t < 0.5 ? a.uppercaseLabels : b.uppercaseLabels,
    iconWeight: t < 0.5 ? a.iconWeight : b.iconWeight,
  );
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

  static GeometryTokens lerp(GeometryTokens a, GeometryTokens b, double t) => GeometryTokens(
    radiusSm: lerpDouble(a.radiusSm, b.radiusSm, t)!,
    radiusMd: lerpDouble(a.radiusMd, b.radiusMd, t)!,
    radiusLg: lerpDouble(a.radiusLg, b.radiusLg, t)!,
    radiusFull: lerpDouble(a.radiusFull, b.radiusFull, t)!,
    borderWidth: lerpDouble(a.borderWidth, b.borderWidth, t)!,
    borderWidthStrong: lerpDouble(a.borderWidthStrong, b.borderWidthStrong, t)!,
    focusRingWidth: lerpDouble(a.focusRingWidth, b.focusRingWidth, t)!,
    hairline: lerpDouble(a.hairline, b.hairline, t)!,
  );
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

  /// DESIGN_SYSTEM §8 — `depth` and the shadow lists that express it can't
  /// interpolate (a border-depth theme has no shadow to grow, a glow's
  /// shadow list has a different shape than a plain drop shadow's), so both
  /// snap at the midpoint alongside `TypographyTokens`' face names; blur
  /// strength and hover behaviour still sweep.
  static EffectTokens lerp(EffectTokens a, EffectTokens b, double t) => EffectTokens(
    depth: t < 0.5 ? a.depth : b.depth,
    shadowSm: t < 0.5 ? a.shadowSm : b.shadowSm,
    shadowMd: t < 0.5 ? a.shadowMd : b.shadowMd,
    shadowLg: t < 0.5 ? a.shadowLg : b.shadowLg,
    surfaceBlur: lerpDouble(a.surfaceBlur, b.surfaceBlur, t)!,
    hoverLift: t < 0.5 ? a.hoverLift : b.hoverLift,
    hoverTintAlpha: lerpDouble(a.hoverTintAlpha, b.hoverTintAlpha, t)!,
  );
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

  static SpacingTokens lerp(SpacingTokens a, SpacingTokens b, double t) => SpacingTokens(
    xs: lerpDouble(a.xs, b.xs, t)!,
    sm: lerpDouble(a.sm, b.sm, t)!,
    md: lerpDouble(a.md, b.md, t)!,
    lg: lerpDouble(a.lg, b.lg, t)!,
    xl: lerpDouble(a.xl, b.xl, t)!,
    xxl: lerpDouble(a.xxl, b.xxl, t)!,
    xxxl: lerpDouble(a.xxxl, b.xxxl, t)!,
    pagePadding: lerpDouble(a.pagePadding, b.pagePadding, t)!,
    cardPadding: lerpDouble(a.cardPadding, b.cardPadding, t)!,
    sectionGap: lerpDouble(a.sectionGap, b.sectionGap, t)!,
    controlHeight: lerpDouble(a.controlHeight, b.controlHeight, t)!,
    rowHeight: lerpDouble(a.rowHeight, b.rowHeight, t)!,
    iconSm: lerpDouble(a.iconSm, b.iconSm, t)!,
    iconMd: lerpDouble(a.iconMd, b.iconMd, t)!,
    iconLg: lerpDouble(a.iconLg, b.iconLg, t)!,
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

  /// Settings' "Reduce motion" override (THEMES.md §9) and the OS "Show
  /// animations" signal both apply here, at theme-build time — the same
  /// point density does — rather than at any individual call site.
  MotionTokens withReduced(bool value) => MotionTokens(
    instant: instant,
    quick: quick,
    standard: standard,
    slow: slow,
    enter: enter,
    exit: exit,
    emphasis: emphasis,
    reduced: value,
  );

  static Duration _lerpDuration(Duration a, Duration b, double t) =>
      Duration(microseconds: lerpDouble(a.inMicroseconds.toDouble(), b.inMicroseconds.toDouble(), t)!.round());

  /// DESIGN_SYSTEM §8 — durations sweep; `Curve`s can't meaningfully
  /// interpolate (there's no halfway point between `easeOutCubic` and
  /// `easeOutBack`), so they snap alongside `reduced`.
  static MotionTokens lerp(MotionTokens a, MotionTokens b, double t) => MotionTokens(
    instant: _lerpDuration(a.instant, b.instant, t),
    quick: _lerpDuration(a.quick, b.quick, t),
    standard: _lerpDuration(a.standard, b.standard, t),
    slow: _lerpDuration(a.slow, b.slow, t),
    enter: t < 0.5 ? a.enter : b.enter,
    exit: t < 0.5 ? a.exit : b.exit,
    emphasis: t < 0.5 ? a.emphasis : b.emphasis,
    reduced: t < 0.5 ? a.reduced : b.reduced,
  );
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

  /// Every shipping theme's `series` is the same length (six) — an
  /// index-aligned crossfade rather than a snap, so a running burn-down
  /// chart doesn't jump mid-animation.
  static ChartTokens lerp(ChartTokens a, ChartTokens b, double t) => ChartTokens(
    series: [
      for (var i = 0; i < a.series.length && i < b.series.length; i++) Color.lerp(a.series[i], b.series[i], t)!,
    ],
    grid: Color.lerp(a.grid, b.grid, t)!,
    axis: Color.lerp(a.axis, b.axis, t)!,
    axisLabel: Color.lerp(a.axisLabel, b.axisLabel, t)!,
    capLine: Color.lerp(a.capLine, b.capLine, t)!,
    positiveFill: Color.lerp(a.positiveFill, b.positiveFill, t)!,
    qrQuietZone: Color.lerp(a.qrQuietZone, b.qrQuietZone, t)!,
  );
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

  /// THEMES.md §8 — needed by Daylight/Swiss, none existed before V2.4.
  /// Based on GitHub Light: syntax color on white, at contrast. Cleared live
  /// against a real streaming `adb` service (OBSERVED §6) before this was
  /// even built, so this is a genuine second home, not an untested guess.
  static const light = TerminalPalette(
    foreground: Color(0xFF24292F),
    background: Color(0xFFFFFFFF),
    black: Color(0xFF24292F),
    red: Color(0xFFCF222E),
    green: Color(0xFF116329),
    yellow: Color(0xFF4D2D00),
    blue: Color(0xFF0969DA),
    magenta: Color(0xFF8250DF),
    cyan: Color(0xFF1B7C83),
    white: Color(0xFF6E7781),
    brightBlack: Color(0xFF57606A),
    brightRed: Color(0xFFA40E26),
    brightGreen: Color(0xFF1A7F37),
    brightYellow: Color(0xFF633C01),
    brightBlue: Color(0xFF218BFF),
    brightMagenta: Color(0xFFA475F9),
    brightCyan: Color(0xFF3192AA),
    brightWhite: Color(0xFF8C959F),
    searchHitBackground: Color(0xFFFFF8C5),
    searchHitBackgroundCurrent: Color(0xFFFFD8B5),
    searchHitForeground: Color(0xFF24292F),
    panelBackground: Color(0xFFFFFFFF),
    headerBackground: Color(0xFFF6F8FA),
  );

  /// Lets a theme reuse `.dark`/`.light` wholesale and only recolor the two
  /// or three fields THEMES.md calls out (Command Deck's background steps,
  /// Mica's translucent well, Swiss's pure-black foreground) instead of
  /// respelling all 23 fields.
  TerminalPalette copyWith({
    Color? foreground,
    Color? background,
    Color? black,
    Color? red,
    Color? green,
    Color? yellow,
    Color? blue,
    Color? magenta,
    Color? cyan,
    Color? white,
    Color? brightBlack,
    Color? brightRed,
    Color? brightGreen,
    Color? brightYellow,
    Color? brightBlue,
    Color? brightMagenta,
    Color? brightCyan,
    Color? brightWhite,
    Color? searchHitBackground,
    Color? searchHitBackgroundCurrent,
    Color? searchHitForeground,
    Color? panelBackground,
    Color? headerBackground,
  }) => TerminalPalette(
    foreground: foreground ?? this.foreground,
    background: background ?? this.background,
    black: black ?? this.black,
    red: red ?? this.red,
    green: green ?? this.green,
    yellow: yellow ?? this.yellow,
    blue: blue ?? this.blue,
    magenta: magenta ?? this.magenta,
    cyan: cyan ?? this.cyan,
    white: white ?? this.white,
    brightBlack: brightBlack ?? this.brightBlack,
    brightRed: brightRed ?? this.brightRed,
    brightGreen: brightGreen ?? this.brightGreen,
    brightYellow: brightYellow ?? this.brightYellow,
    brightBlue: brightBlue ?? this.brightBlue,
    brightMagenta: brightMagenta ?? this.brightMagenta,
    brightCyan: brightCyan ?? this.brightCyan,
    brightWhite: brightWhite ?? this.brightWhite,
    searchHitBackground: searchHitBackground ?? this.searchHitBackground,
    searchHitBackgroundCurrent: searchHitBackgroundCurrent ?? this.searchHitBackgroundCurrent,
    searchHitForeground: searchHitForeground ?? this.searchHitForeground,
    panelBackground: panelBackground ?? this.panelBackground,
    headerBackground: headerBackground ?? this.headerBackground,
  );

  static TerminalPalette lerp(TerminalPalette a, TerminalPalette b, double t) => TerminalPalette(
    foreground: Color.lerp(a.foreground, b.foreground, t)!,
    background: Color.lerp(a.background, b.background, t)!,
    black: Color.lerp(a.black, b.black, t)!,
    red: Color.lerp(a.red, b.red, t)!,
    green: Color.lerp(a.green, b.green, t)!,
    yellow: Color.lerp(a.yellow, b.yellow, t)!,
    blue: Color.lerp(a.blue, b.blue, t)!,
    magenta: Color.lerp(a.magenta, b.magenta, t)!,
    cyan: Color.lerp(a.cyan, b.cyan, t)!,
    white: Color.lerp(a.white, b.white, t)!,
    brightBlack: Color.lerp(a.brightBlack, b.brightBlack, t)!,
    brightRed: Color.lerp(a.brightRed, b.brightRed, t)!,
    brightGreen: Color.lerp(a.brightGreen, b.brightGreen, t)!,
    brightYellow: Color.lerp(a.brightYellow, b.brightYellow, t)!,
    brightBlue: Color.lerp(a.brightBlue, b.brightBlue, t)!,
    brightMagenta: Color.lerp(a.brightMagenta, b.brightMagenta, t)!,
    brightCyan: Color.lerp(a.brightCyan, b.brightCyan, t)!,
    brightWhite: Color.lerp(a.brightWhite, b.brightWhite, t)!,
    searchHitBackground: Color.lerp(a.searchHitBackground, b.searchHitBackground, t)!,
    searchHitBackgroundCurrent: Color.lerp(a.searchHitBackgroundCurrent, b.searchHitBackgroundCurrent, t)!,
    searchHitForeground: Color.lerp(a.searchHitForeground, b.searchHitForeground, t)!,
    panelBackground: Color.lerp(a.panelBackground, b.panelBackground, t)!,
    headerBackground: Color.lerp(a.headerBackground, b.headerBackground, t)!,
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
    required this.typography,
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

  // Deliberately not named `type` — `ThemeExtension<T>`'s own `type` getter
  // (`Object get type => T`) isn't decorative: Flutter uses it as the map
  // key when building `ThemeData.extensions` from the constructor's list.
  // A same-named field silently shadows it, so `ThemeData(extensions: [
  // tokens])` keys itself by a `TypographyTokens` *instance* instead of the
  // `AppTokens` type — every `Theme.of(context).extension<AppTokens>()`
  // call then misses and `AppTokensX.tokens` falls back to
  // `buildClassicTokens()` unconditionally, regardless of the real active
  // theme (found live, D104 — invisible through V2.1–V2.3 since Classic
  // was the only theme that existed, so the fallback and the real value
  // were identical).
  final TypographyTokens typography;
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
    TypographyTokens? typography,
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
    typography: typography ?? this.typography,
    geometry: geometry ?? this.geometry,
    effects: effects ?? this.effects,
    space: space ?? this.space,
    motion: motion ?? this.motion,
    chart: chart ?? this.chart,
    terminal: terminal ?? this.terminal,
  );

  /// DESIGN_SYSTEM §8 — real per-field interpolation, not the midpoint snap
  /// `AppPalette.lerp` (the token it replaces) used. Every color and every
  /// measure sweeps continuously; whatever can't mean anything at a halfway
  /// point — face names, `DepthStrategy`, shadow shapes, curves — snaps,
  /// each documented on its own sub-token's `lerp` above. `id`/`name`/
  /// `tagline` snap the same way: there's no such thing as 60% of the way
  /// from "Classic" to "Swiss" as a string. Mica's native `Window.setEffect`
  /// hard-cut (THEMES.md §4) is a separate, OS-level concern —
  /// `theme_controller.dart` triggers that call directly; nothing here needs
  /// to special-case it, since the colors and geometry keep sweeping
  /// smoothly underneath regardless of what the compositor is doing.
  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    if (identical(this, other)) return this;
    return AppTokens(
      id: t < 0.5 ? id : other.id,
      name: t < 0.5 ? name : other.name,
      tagline: t < 0.5 ? tagline : other.tagline,
      brightness: t < 0.5 ? brightness : other.brightness,
      surface: SurfaceTokens.lerp(surface, other.surface, t),
      content: ContentTokens.lerp(content, other.content, t),
      accent: AccentTokens.lerp(accent, other.accent, t),
      status: StatusTokens.lerp(status, other.status, t),
      typography: TypographyTokens.lerp(typography, other.typography, t),
      geometry: GeometryTokens.lerp(geometry, other.geometry, t),
      effects: EffectTokens.lerp(effects, other.effects, t),
      space: SpacingTokens.lerp(space, other.space, t),
      motion: MotionTokens.lerp(motion, other.motion, t),
      chart: ChartTokens.lerp(chart, other.chart, t),
      terminal: TerminalPalette.lerp(terminal, other.terminal, t),
    );
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
