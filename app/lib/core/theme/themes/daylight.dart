// THEMES.md §5 — Daylight: warm paper white, ink text, real shadows, indigo
// accent. After five dark themes (including Classic), this is the one that
// makes it feel like a different application — and the theme that proves
// the token system actually works, since every dark-mode assumption in the
// codebase has to have become a real token for it to render at all.
//
// Warm rather than pure white (`#FBFBF9`, not `#FFFFFF`) because a
// full-height, full-bright panel next to a dark scrcpy mirror is fatiguing;
// the slight warmth takes the edge off without reading as beige.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../tokens.dart';

AppTokens buildDaylightTokens() {
  const accentPrimary = Color(0xFF4F46E5);
  const good = Color(0xFF15803D);
  const info = Color(0xFF1D4ED8);
  const warn = Color(0xFFB45309);
  const bad = Color(0xFFB91C1C);
  const contentSecondary = Color(0xFF5C5C56);
  const contentTertiary = Color(0xFF8E8E86);

  return AppTokens(
    id: ThemeId.daylight,
    name: 'Daylight',
    tagline: 'Warm paper. The biggest single vibe change available.',
    brightness: Brightness.light,
    surface: const SurfaceTokens(
      canvas: Color(0xFFFBFBF9),
      base: Color(0xFFFFFFFF),
      raised: Color(0xFFF6F6F3),
      sunken: Color(0xFFF1F1ED),
      overlay: Color(0xFFFFFFFF),
      border: Color(0xFFE4E4DE),
      borderStrong: Color(0xFFC9C9C1),
      borderSubtle: Color(0xFFEFEFEA),
      scrim: Color(0x591A1A18), // #1A1A18 @ 0.35
    ),
    content: const ContentTokens(
      primary: Color(0xFF1A1A18),
      secondary: contentSecondary,
      tertiary: contentTertiary,
      onAccent: Color(0xFFFFFFFF),
      inverse: Color(0xFFFBFBF9),
    ),
    accent: const AccentTokens(primary: accentPrimary, onPrimary: Color(0xFFFFFFFF), muted: Color(0x1A4F46E5), secondary: accentPrimary),
    status: const StatusTokens(
      good: StatusColor(fg: good, container: Color(0xFFDCFCE7), onContainer: Color(0xFF14532D)),
      info: StatusColor(fg: info, container: Color(0xFFDBEAFE), onContainer: Color(0xFF1E3A8A)),
      warn: StatusColor(fg: warn, container: Color(0xFFFEF3C7), onContainer: Color(0xFF78350F)),
      bad: StatusColor(fg: bad, container: Color(0xFFFEE2E2), onContainer: Color(0xFF7F1D1D)),
    ),
    typography: const TypographyTokens(
      display: 'Inter',
      body: 'Inter',
      mono: 'JetBrains Mono',
      scale: 1.0,
      bodyHeight: 1.5,
      tightTracking: 0.0,
      looseTracking: 0.0,
      bodyWeight: FontWeight.w400,
      headingWeight: FontWeight.w600,
      uppercaseLabels: false,
      iconWeight: PhosphorIconsStyle.regular,
    ),
    geometry: const GeometryTokens(radiusSm: 6, radiusMd: 10, radiusLg: 14, radiusFull: 999, borderWidth: 1, borderWidthStrong: 1, focusRingWidth: 2, hairline: 1),
    effects: const EffectTokens(
      depth: DepthStrategy.shadow,
      shadowSm: [BoxShadow(color: Color(0x0D1A1A18), blurRadius: 4, offset: Offset(0, 1))],
      shadowMd: [BoxShadow(color: Color(0x121A1A18), blurRadius: 12, offset: Offset(0, 4))],
      shadowLg: [BoxShadow(color: Color(0x1A1A1A18), blurRadius: 28, offset: Offset(0, 12))],
      surfaceBlur: 0,
      hoverLift: true,
      hoverTintAlpha: 0.045,
    ),
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
      series: const [accentPrimary, Color(0xFF0891B2), good, warn, Color(0xFFBE185D), Color(0xFF7C3AED)],
      grid: const Color(0xFFEFEFEA),
      axis: const Color(0xFFC9C9C1),
      axisLabel: contentTertiary,
      capLine: contentSecondary,
      positiveFill: good.withValues(alpha: 0.16),
      qrQuietZone: const Color(0xFFFFFFFF),
    ),
    // A new palette, needed here — no light terminal palette existed before
    // V2.4 (THEMES.md §6/§8). Verbatim, no per-theme override.
    terminal: TerminalPalette.light,
  );
}
