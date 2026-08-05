// THEMES.md §4 — Mica: translucent, layered, Fluent. The tasteful, native
// answer to "glassmorphism" — real Windows compositor Mica (`main.dart`'s
// `Window.setEffect` call, already paid for since CP 0.2) rather than a
// stack of `BackdropFilter`s. `surface.canvas` is fully transparent so the
// desktop shows through the shell; every other surface carries real alpha
// so it reads as acrylic sitting on top of that backdrop.
//
// The only theme that uses system fonts — Segoe UI Variable / Cascadia
// Mono — because a theme whose entire point is "this shipped with Windows"
// must not bring its own typeface. Both are present on any Windows 11
// machine this app runs on, so no bundled-font fallback is wired up (the
// other five themes' Inter/JetBrains Mono already cover the "degrades
// safely" case THEMES.md mentions, for every *other* theme).
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../tokens.dart';

AppTokens buildMicaTokens() {
  const accentPrimary = Color(0xFF60CDFF);
  const good = Color(0xFF6CCB5F);
  const info = accentPrimary;
  const warn = Color(0xFFFCE100);
  const bad = Color(0xFFFF99A4);
  const contentSecondary = Color(0xC8FFFFFF); // Fluent TextFillColorSecondary
  const contentTertiary = Color(0x8BFFFFFF); // Fluent TextFillColorTertiary
  const raised = Color(0xCC2B2B2B);
  const sunken = Color(0xD91A1A1A);

  return AppTokens(
    id: ThemeId.mica,
    name: 'Mica',
    tagline: 'Translucent Windows 11 native. Uses the backdrop the app already pays for.',
    brightness: Brightness.dark,
    surface: SurfaceTokens(
      canvas: Colors.transparent,
      base: const Color(0xB8202020),
      raised: raised,
      sunken: sunken,
      overlay: const Color(0xEB2C2C2C),
      border: const Color(0x18FFFFFF), // Fluent CardStrokeColorDefault
      borderStrong: const Color(0x29FFFFFF),
      borderSubtle: const Color(0x0EFFFFFF),
      scrim: const Color(0x4D000000),
    ),
    content: const ContentTokens(
      primary: Color(0xFFFFFFFF), // Fluent TextFillColorPrimary
      secondary: contentSecondary,
      tertiary: contentTertiary,
      onAccent: Color(0xFF000000),
      inverse: Color(0xFF000000),
    ),
    accent: const AccentTokens(primary: accentPrimary, onPrimary: Color(0xFF003A50), muted: Color(0x2E60CDFF), secondary: accentPrimary),
    status: StatusTokens(
      good: StatusColor(fg: good, container: const Color(0xFF393D1B), onContainer: good),
      info: StatusColor(fg: info, container: const Color(0xFF1B3A4B), onContainer: info),
      warn: StatusColor(fg: warn, container: const Color(0xFF433519), onContainer: warn),
      bad: StatusColor(fg: bad, container: const Color(0xFF442726), onContainer: bad),
    ),
    typography: const TypographyTokens(
      display: 'Segoe UI Variable Display',
      body: 'Segoe UI Variable Text',
      mono: 'Cascadia Mono',
      scale: 1.0,
      bodyHeight: 1.4,
      tightTracking: 0.0,
      looseTracking: 0.0,
      bodyWeight: FontWeight.w400,
      headingWeight: FontWeight.w600,
      uppercaseLabels: false,
      iconWeight: PhosphorIconsStyle.regular,
    ),
    // Fluent's own corner scale (THEMES.md §4).
    geometry: const GeometryTokens(radiusSm: 4, radiusMd: 8, radiusLg: 8, radiusFull: 999, borderWidth: 1, borderWidthStrong: 1, focusRingWidth: 2, hairline: 1),
    effects: const EffectTokens(
      depth: DepthStrategy.both,
      // Not given explicitly in THEMES.md's table (only shadowMd is) —
      // scaled down/up from it rather than guessed independently.
      shadowSm: [BoxShadow(color: Color(0x2E000000), blurRadius: 12, offset: Offset(0, 3))],
      shadowMd: [BoxShadow(color: Color(0x42000000), blurRadius: 32, offset: Offset(0, 8))],
      shadowLg: [BoxShadow(color: Color(0x52000000), blurRadius: 48, offset: Offset(0, 16))],
      surfaceBlur: 18,
      hoverLift: false,
      hoverTintAlpha: 0.06,
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
      series: const [accentPrimary, good, warn, bad, Color(0xFFC39EFF), Color(0xFF4CC2FF)],
      grid: const Color(0x18FFFFFF),
      axis: const Color(0x29FFFFFF),
      axisLabel: contentTertiary,
      capLine: contentSecondary,
      positiveFill: good.withValues(alpha: 0.16),
      qrQuietZone: const Color(0xFFFFFFFF),
    ),
    terminal: TerminalPalette.dark.copyWith(background: sunken, panelBackground: sunken, headerBackground: raised),
  );
}
