// THEMES.md §1 — Classic: the look the app has had since CP 0.3, preserved so
// nothing is lost and every other theme has a reference point.
//
// Built differently from the other five, on purpose: rather than transcribing
// Material's generated scheme by hand (and drifting from it), this calls
// `ColorScheme.fromSeed` and reads the tokens straight off the result, so the
// match to today is exact rather than transcribed.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../tokens.dart';

AppTokens buildClassicTokens() {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF6C63FF), brightness: Brightness.dark);

  // AppPalette.dark's existing three (unchanged — CP 7.3), plus `bad` from
  // the seed scheme's own `error`/`errorContainer`/`onErrorContainer`.
  const good = Color(0xFF3DD68C);
  const info = Color(0xFF6EA8FE);
  const warn = Color(0xFFFFB454);

  StatusColor tinted(Color fg) =>
      StatusColor(fg: fg, container: Color.alphaBlend(fg.withValues(alpha: 0.18), scheme.surfaceContainer), onContainer: fg);

  return AppTokens(
    id: ThemeId.classic,
    name: 'Classic',
    tagline: "Exactly today's app. The baseline, preserved.",
    brightness: Brightness.dark,
    surface: SurfaceTokens(
      canvas: Colors.transparent,
      base: scheme.surfaceContainer,
      raised: scheme.surfaceContainerHigh,
      sunken: scheme.surfaceContainerLowest,
      overlay: scheme.surfaceContainerHigh,
      border: scheme.outlineVariant,
      borderStrong: scheme.outline,
      borderSubtle: scheme.outlineVariant.withValues(alpha: 0.5),
      scrim: scheme.scrim,
    ),
    content: ContentTokens(
      primary: scheme.onSurface,
      secondary: scheme.onSurfaceVariant,
      tertiary: scheme.onSurfaceVariant.withValues(alpha: 0.62),
      onAccent: scheme.onPrimary,
      inverse: scheme.onInverseSurface,
    ),
    accent: AccentTokens(primary: scheme.primary, onPrimary: scheme.onPrimary, muted: scheme.primary.withValues(alpha: 0.14), secondary: scheme.secondary),
    status: StatusTokens(good: tinted(good), info: tinted(info), warn: tinted(warn), bad: StatusColor(fg: scheme.error, container: scheme.errorContainer, onContainer: scheme.onErrorContainer)),
    type: const TypographyTokens(
      display: 'Roboto',
      body: 'Roboto',
      // The one deliberate upgrade this theme makes over today's app — it
      // replaces the 'Consolas'/'monospace' mix (AUDIT §7), which was a bug,
      // not a look.
      mono: 'JetBrains Mono',
      scale: 1.0,
      bodyHeight: 1.4,
      tightTracking: 0.0,
      looseTracking: 0.0,
      bodyWeight: FontWeight.w400,
      headingWeight: FontWeight.w600,
      uppercaseLabels: false,
      iconWeight: PhosphorIconsStyle.regular,
    ),
    geometry: const GeometryTokens(radiusSm: 8, radiusMd: 12, radiusLg: 16, radiusFull: 999, borderWidth: 1, borderWidthStrong: 1, focusRingWidth: 2, hairline: 1),
    effects: const EffectTokens(
      depth: DepthStrategy.shadow,
      // Material 3's own default elevation shadows (level 1 / 2 / 3).
      shadowSm: [BoxShadow(color: Color(0x4D000000), blurRadius: 3, offset: Offset(0, 1))],
      shadowMd: [BoxShadow(color: Color(0x4D000000), blurRadius: 6, offset: Offset(0, 3))],
      shadowLg: [BoxShadow(color: Color(0x4D000000), blurRadius: 12, offset: Offset(0, 6))],
      surfaceBlur: 0,
      hoverLift: false,
      hoverTintAlpha: 0.08,
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
      series: [scheme.primary, good, info, warn, scheme.error, scheme.secondary],
      grid: scheme.outlineVariant.withValues(alpha: 0.5),
      axis: scheme.outlineVariant,
      axisLabel: scheme.onSurfaceVariant.withValues(alpha: 0.62),
      capLine: scheme.onSurfaceVariant,
      positiveFill: good.withValues(alpha: 0.16),
      // The QR quiet zone stays pure white regardless of theme — the one
      // literal the token-coverage grep excepts (V2.3).
      qrQuietZone: Colors.white,
    ),
    terminal: TerminalPalette.dark,
  );
}
