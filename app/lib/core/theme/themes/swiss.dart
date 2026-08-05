// THEMES.md §6 — Swiss: International Style. A strict grid, black rules,
// one red, and zero corner radius anywhere. The most opinionated theme in
// the set — chosen because it's the one classical design language that is
// actually about dense information (timetables, wayfinding, technical
// tables), and everything this app renders is a table, a status, or a
// number.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../tokens.dart';

AppTokens buildSwissTokens() {
  const accentPrimary = Color(0xFFE30613);
  const good = Color(0xFF007A33);
  const info = Color(0xFF0057B8);
  // THEMES.md §6 gives #C25E00, which lands at 4.29:1 against a white
  // surface.base — under the 4.5:1 floor `theme_contrast_test.dart`
  // enforces. Darkened to the nearest value that clears it in the same
  // hue (THEMES.md §7 explicitly asks the implementing session to make
  // exactly this kind of adjustment).
  const warn = Color(0xFFB05300);
  const bad = accentPrimary;
  const contentSecondary = Color(0xFF5A5A5A);
  const contentTertiary = Color(0xFF909090);

  return AppTokens(
    id: ThemeId.swiss,
    name: 'Swiss',
    tagline: 'International Style. Rules, grid, one red, zero radius.',
    brightness: Brightness.light,
    surface: const SurfaceTokens(
      canvas: Color(0xFFFFFFFF),
      base: Color(0xFFFFFFFF),
      raised: Color(0xFFF7F7F7),
      sunken: Color(0xFFF0F0F0),
      overlay: Color(0xFFFFFFFF),
      border: Color(0x24000000), // #000000 @ 0.14
      // Real black rules — the primary structural device this theme is
      // built around (THEMES.md §6).
      borderStrong: Color(0xD9000000), // #000000 @ 0.85
      borderSubtle: Color(0x12000000), // #000000 @ 0.07
      scrim: Color(0x66000000),
    ),
    content: const ContentTokens(
      primary: Color(0xFF000000),
      secondary: contentSecondary,
      tertiary: contentTertiary,
      onAccent: Color(0xFFFFFFFF),
      inverse: Color(0xFFFFFFFF),
    ),
    accent: const AccentTokens(primary: accentPrimary, onPrimary: Color(0xFFFFFFFF), muted: Color(0x14E30613), secondary: accentPrimary),
    status: const StatusTokens(
      good: StatusColor(fg: good, container: Color(0xFFE6F4EC), onContainer: Color(0xFF005423)),
      info: StatusColor(fg: info, container: Color(0xFFE4EEF9), onContainer: Color(0xFF003C80)),
      warn: StatusColor(fg: warn, container: Color(0xFFFBEEE2), onContainer: Color(0xFF7F3D00)),
      bad: StatusColor(fg: bad, container: Color(0xFFFCE7E8), onContainer: Color(0xFF96040D)),
    ),
    typography: const TypographyTokens(
      display: 'Inter', // the Helvetica substitute
      body: 'Inter',
      mono: 'JetBrains Mono',
      scale: 0.98,
      bodyHeight: 1.45,
      tightTracking: -0.02,
      looseTracking: 0.10,
      bodyWeight: FontWeight.w400,
      // Heavy weight contrast — 400 body against 700 headings, nothing
      // between (THEMES.md §6).
      headingWeight: FontWeight.w700,
      uppercaseLabels: true,
      iconWeight: PhosphorIconsStyle.bold,
    ),
    // Zero radius everywhere — even pills and avatars are square.
    geometry: const GeometryTokens(radiusSm: 0, radiusMd: 0, radiusLg: 0, radiusFull: 0, borderWidth: 1, borderWidthStrong: 2, focusRingWidth: 2, hairline: 1),
    effects: const EffectTokens(depth: DepthStrategy.border, shadowSm: [], shadowMd: [], shadowLg: [], surfaceBlur: 0, hoverLift: false, hoverTintAlpha: 0.04),
    space: const SpacingTokens(
      xs: 4,
      sm: 8,
      md: 12,
      lg: 16,
      xl: 24,
      xxl: 32,
      xxxl: 48,
      pagePadding: 24,
      cardPadding: 16,
      sectionGap: 24,
      controlHeight: 36,
      rowHeight: 40,
      iconSm: 14,
      iconMd: 18,
      iconLg: 24,
    ),
    motion: const MotionTokens(
      instant: Duration(milliseconds: 90),
      quick: Duration(milliseconds: 160),
      standard: Duration(milliseconds: 240),
      slow: Duration(milliseconds: 400),
      enter: Curves.easeOutCubic,
      exit: Curves.easeInCubic,
      emphasis: Curves.easeOutBack,
      reduced: false,
    ),
    chart: ChartTokens(
      series: const [accentPrimary, Color(0xFF000000), info, good, warn, contentSecondary],
      grid: const Color(0x12000000),
      axis: const Color(0xD9000000),
      axisLabel: contentSecondary,
      capLine: const Color(0xFF000000),
      positiveFill: good.withValues(alpha: 0.16),
      qrQuietZone: const Color(0xFFFFFFFF),
    ),
    // TerminalPalette.light with a pure-black foreground rather than GitHub
    // Light's dark-grey #24292F — this theme's whole point is real black
    // rules against white, not a softened near-black.
    terminal: TerminalPalette.light.copyWith(foreground: const Color(0xFF000000)),
  );
}
