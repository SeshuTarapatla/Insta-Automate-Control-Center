// THEMES.md §2 — Command Deck: near-black, hairline-ruled, monospace-
// numeraled. Grafana / k9s / Vercel territory, for someone who actually
// runs a pipeline off this screen all day.
//
// Organising idea: color means something, or it isn't there. The chrome is
// achromatic — greys and hairlines only — so the four status colors are the
// only saturated things on screen. The accent itself is a cool sky blue used
// *only* for selection and focus, never for status (DESIGN_SYSTEM §1.3's
// rule: accent never encodes state).
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../tokens.dart';

AppTokens buildCommandDeckTokens() {
  const good = Color(0xFF22C55E);
  const info = Color(0xFF38BDF8);
  const warn = Color(0xFFF59E0B);
  const bad = Color(0xFFEF4444);
  const accentPrimary = Color(0xFF38BDF8);
  const contentSecondary = Color(0xFF949CB0);
  const contentTertiary = Color(0xFF5B6274);
  const border = Color(0xFF232733);
  const borderStrong = Color(0xFF333949);

  return AppTokens(
    id: ThemeId.commandDeck,
    name: 'Command Deck',
    tagline: 'Ops console. Hairlines, monospace numerals, color reserved for meaning.',
    brightness: Brightness.dark,
    surface: const SurfaceTokens(
      canvas: Color(0xFF07080B),
      base: Color(0xFF0E1015),
      raised: Color(0xFF161923),
      sunken: Color(0xFF090A0E),
      overlay: Color(0xFF1A1D27),
      border: border,
      borderStrong: borderStrong,
      borderSubtle: Color(0xFF191C25),
      scrim: Color(0xB8000000), // #000000 @ 0.72
    ),
    content: const ContentTokens(
      primary: Color(0xFFE6E9F0),
      secondary: contentSecondary,
      tertiary: contentTertiary,
      onAccent: Color(0xFF04121A),
      inverse: Color(0xFF0E1015),
    ),
    accent: const AccentTokens(primary: accentPrimary, onPrimary: Color(0xFF04121A), muted: Color(0x2438BDF8), secondary: accentPrimary),
    status: const StatusTokens(
      good: StatusColor(fg: good, container: Color(0xFF052E16), onContainer: Color(0xFF4ADE80)),
      info: StatusColor(fg: info, container: Color(0xFF082F49), onContainer: Color(0xFF7DD3FC)),
      warn: StatusColor(fg: warn, container: Color(0xFF3B2400), onContainer: Color(0xFFFCD34D)),
      bad: StatusColor(fg: bad, container: Color(0xFF3F0D0D), onContainer: Color(0xFFFCA5A5)),
    ),
    typography: const TypographyTokens(
      display: 'Inter',
      body: 'Inter',
      mono: 'JetBrains Mono',
      scale: 0.96,
      bodyHeight: 1.45,
      tightTracking: -0.01,
      looseTracking: 0.08,
      bodyWeight: FontWeight.w400,
      headingWeight: FontWeight.w600,
      uppercaseLabels: true,
      iconWeight: PhosphorIconsStyle.regular,
    ),
    geometry: const GeometryTokens(radiusSm: 3, radiusMd: 4, radiusLg: 6, radiusFull: 999, borderWidth: 1, borderWidthStrong: 1, focusRingWidth: 2, hairline: 1),
    // depth: border — all three shadow lists empty. Depth is hairlines and
    // surface steps, nothing else (THEMES.md §2).
    effects: const EffectTokens(depth: DepthStrategy.border, shadowSm: [], shadowMd: [], shadowLg: [], surfaceBlur: 0, hoverLift: false, hoverTintAlpha: 0.06),
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
      series: const [accentPrimary, good, warn, Color(0xFFA78BFA), Color(0xFFF472B6), Color(0xFF2DD4BF)],
      grid: border,
      axis: borderStrong,
      axisLabel: contentTertiary,
      capLine: contentSecondary,
      positiveFill: good.withValues(alpha: 0.16),
      // Real white regardless of theme — a QR scanner needs a genuine light
      // quiet zone, not this theme's near-black canvas.
      qrQuietZone: const Color(0xFFFFFFFF),
    ),
    // TerminalPalette.dark (Tokyo Night) with the three steps THEMES.md §2
    // calls out, so the terminal reads as one more surface step in this
    // theme's own near-black stack rather than a different app's colors.
    terminal: TerminalPalette.dark.copyWith(background: const Color(0xFF090A0E), panelBackground: const Color(0xFF090A0E), headerBackground: const Color(0xFF161923)),
  );
}
