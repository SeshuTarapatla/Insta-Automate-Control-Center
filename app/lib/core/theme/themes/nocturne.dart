// THEMES.md §3 — Nocturne: deep blue-purple, muted pastels, generous radii,
// a soft accent glow. The app at 11pm.
//
// This is the only theme where the terminal and the chrome around it were
// designed together: `TerminalPalette.dark` is already Tokyo Night, and
// Nocturne extends that color language outward rather than inventing a new
// one, so it's used verbatim rather than recolored.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../tokens.dart';

AppTokens buildNocturneTokens() {
  const accentPrimary = Color(0xFFBB9AF7);
  const good = Color(0xFF9ECE6A);
  const info = Color(0xFF7AA2F7);
  const warn = Color(0xFFE0AF68);
  const bad = Color(0xFFF7768E);
  const contentSecondary = Color(0xFF8A92B2);
  // THEMES.md §3 gives #565F89, which lands at 2.76:1 against surface.base —
  // under the 3:1 UI-boundary floor `theme_contrast_test.dart` enforces.
  // Lightened to the nearest value that clears it while staying in the same
  // muted blue-grey family (THEMES.md §7 explicitly asks the implementing
  // session to make exactly this kind of adjustment).
  const contentTertiary = Color(0xFF6A7399);
  const border = Color(0xFF2E3145);
  const borderStrong = Color(0xFF3D4160);

  return AppTokens(
    id: ThemeId.nocturne,
    name: 'Nocturne',
    tagline: 'Soft, cozy, low-contrast. Tokyo Night, extended.',
    brightness: Brightness.dark,
    surface: const SurfaceTokens(
      canvas: Color(0xFF13131A),
      base: Color(0xFF1A1B26),
      raised: Color(0xFF232534),
      sunken: Color(0xFF16161F),
      overlay: Color(0xFF262838),
      border: border,
      borderStrong: borderStrong,
      borderSubtle: Color(0xFF22243A),
      scrim: Color(0xA80B0B12), // #0B0B12 @ 0.66
    ),
    content: const ContentTokens(
      primary: Color(0xFFC0CAF5),
      secondary: contentSecondary,
      tertiary: contentTertiary,
      onAccent: Color(0xFF1A1128),
      inverse: Color(0xFF1A1B26),
    ),
    accent: const AccentTokens(primary: accentPrimary, onPrimary: Color(0xFF1A1128), muted: Color(0x29BB9AF7), secondary: accentPrimary),
    status: const StatusTokens(
      good: StatusColor(fg: good, container: Color(0xFF1F2E14), onContainer: Color(0xFFC3E88D)),
      info: StatusColor(fg: info, container: Color(0xFF16233F), onContainer: Color(0xFFA9C3FF)),
      warn: StatusColor(fg: warn, container: Color(0xFF33260F), onContainer: Color(0xFFF0C990)),
      bad: StatusColor(fg: bad, container: Color(0xFF3A121C), onContainer: Color(0xFFFF9EB0)),
    ),
    typography: const TypographyTokens(
      display: 'Inter',
      body: 'Inter',
      mono: 'JetBrains Mono',
      scale: 1.0,
      bodyHeight: 1.55,
      tightTracking: 0.0,
      looseTracking: 0.0,
      bodyWeight: FontWeight.w400,
      headingWeight: FontWeight.w600,
      uppercaseLabels: false,
      iconWeight: PhosphorIconsStyle.light,
    ),
    // The largest radii in the set (THEMES.md §3) — same widgets as every
    // other theme, distinctly softer.
    geometry: const GeometryTokens(radiusSm: 8, radiusMd: 14, radiusLg: 20, radiusFull: 999, borderWidth: 1, borderWidthStrong: 1, focusRingWidth: 2, hairline: 1),
    effects: const EffectTokens(
      depth: DepthStrategy.glow,
      shadowSm: [BoxShadow(color: Color(0x0FBB9AF7), blurRadius: 12, offset: Offset(0, 2))],
      shadowMd: [
        BoxShadow(color: Color(0x59000000), blurRadius: 24, offset: Offset(0, 6)),
        BoxShadow(color: Color(0x0DBB9AF7), blurRadius: 32),
      ],
      // Not specified in THEMES.md's table — scaled up from shadowMd rather
      // than guessed independently, so the glow grows consistently at the
      // one size step the doc didn't spell out.
      shadowLg: [
        BoxShadow(color: Color(0x73000000), blurRadius: 40, offset: Offset(0, 14)),
        BoxShadow(color: Color(0x14BB9AF7), blurRadius: 56),
      ],
      surfaceBlur: 0,
      // Hover genuinely lifts (2px) rather than just tinting — the accent
      // glow appears on focused/running elements only, so a running flow
      // visibly *emits* on this theme (THEMES.md §3).
      hoverLift: true,
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
      series: const [accentPrimary, info, good, warn, bad, Color(0xFF7DCFFF)],
      grid: border,
      axis: borderStrong,
      axisLabel: contentTertiary,
      capLine: contentSecondary,
      positiveFill: good.withValues(alpha: 0.16),
      qrQuietZone: const Color(0xFFFFFFFF),
    ),
    // This is Tokyo Night's home theme — used verbatim, not recolored.
    terminal: TerminalPalette.dark,
  );
}
