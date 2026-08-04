// The one place `AppTokens` becomes a real `ThemeData` — DESIGN_SYSTEM.md §1
// and §4's rule: "Depth is expressed once, by `EffectTokens.depth`, and
// applied by `build_theme.dart`. Feature code never sets `elevation`, never
// sets a `BoxShadow`, and never draws its own border." Everything below is
// mechanical translation from tokens to Material's ~40 component sub-themes;
// nothing here is a design decision — those all live in `themes/*.dart`.
import 'package:flutter/material.dart';

import 'density.dart';
import 'tokens.dart';

ThemeData buildTheme(AppTokens rawTokens, {Density density = Density.comfortable}) {
  final tokens = _applyDensity(rawTokens, density);
  final scheme = _colorScheme(tokens);
  final textTheme = _textTheme(tokens);
  final hasBorder = tokens.effects.depth == DepthStrategy.border || tokens.effects.depth == DepthStrategy.both;
  final hasShadow = tokens.effects.depth == DepthStrategy.shadow || tokens.effects.depth == DepthStrategy.both;
  final hasGlow = tokens.effects.depth == DepthStrategy.glow;

  BorderSide edge([Color? color]) => hasBorder
      ? BorderSide(color: color ?? tokens.surface.border, width: tokens.geometry.borderWidth)
      : BorderSide.none;

  List<BoxShadow> depthShadow(List<BoxShadow> shadow) => hasShadow || hasGlow ? shadow : const [];

  RoundedRectangleBorder panelShape(double radius, {Color? borderColor}) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: edge(borderColor));

  WidgetStateProperty<Color?> hoverTint(Color base, Color tintTowards) => WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.disabled)) return null;
    if (states.contains(WidgetState.pressed)) {
      return Color.alphaBlend(tintTowards.withValues(alpha: tokens.effects.hoverTintAlpha * 1.6), base);
    }
    if (states.contains(WidgetState.hovered) || states.contains(WidgetState.focused)) {
      return Color.alphaBlend(tintTowards.withValues(alpha: tokens.effects.hoverTintAlpha), base);
    }
    return null;
  });

  return ThemeData(
    useMaterial3: true,
    brightness: tokens.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: tokens.surface.canvas,
    canvasColor: tokens.surface.canvas,
    dividerColor: tokens.surface.border,
    disabledColor: tokens.content.tertiary,
    hoverColor: tokens.accent.primary.withValues(alpha: tokens.effects.hoverTintAlpha),
    focusColor: tokens.accent.primary.withValues(alpha: tokens.effects.hoverTintAlpha * 1.5),
    splashFactory: tokens.motion.reduced ? NoSplash.splashFactory : InkSparkle.splashFactory,
    fontFamily: tokens.type.body,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    iconTheme: IconThemeData(color: tokens.content.secondary, size: tokens.space.iconMd),
    primaryIconTheme: IconThemeData(color: tokens.content.secondary, size: tokens.space.iconMd),
    visualDensity: VisualDensity.standard,
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final platform in TargetPlatform.values) platform: const FadeUpwardsPageTransitionsBuilder(),
      },
    ),
    extensions: [tokens],

    // — App bar ----------------------------------------------------------
    appBarTheme: AppBarThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: tokens.content.primary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
      iconTheme: IconThemeData(color: tokens.content.secondary, size: tokens.space.iconMd),
      actionsIconTheme: IconThemeData(color: tokens.content.secondary, size: tokens.space.iconMd),
    ),

    // — Surfaces: card / dialog / bottom sheet / menus --------------------
    cardTheme: CardThemeData(
      color: tokens.surface.base,
      surfaceTintColor: Colors.transparent,
      shadowColor: hasShadow || hasGlow ? const Color(0xFF000000) : Colors.transparent,
      elevation: hasShadow ? 1 : 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: panelShape(tokens.geometry.radiusMd),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.surface.overlay,
      surfaceTintColor: Colors.transparent,
      elevation: hasShadow || hasGlow ? 6 : 0,
      shadowColor: const Color(0xFF000000),
      shape: panelShape(tokens.geometry.radiusLg, borderColor: tokens.surface.borderStrong),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tokens.surface.overlay,
      surfaceTintColor: Colors.transparent,
      elevation: hasShadow || hasGlow ? 4 : 0,
      modalBackgroundColor: tokens.surface.overlay,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(tokens.geometry.radiusLg)),
        side: edge(tokens.surface.borderStrong),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: tokens.surface.overlay,
      surfaceTintColor: Colors.transparent,
      elevation: hasShadow || hasGlow ? 4 : 0,
      shape: panelShape(tokens.geometry.radiusMd, borderColor: tokens.surface.borderStrong),
      textStyle: textTheme.bodyMedium,
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(tokens.surface.overlay),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(hasShadow || hasGlow ? 4 : 0),
        shape: WidgetStatePropertyAll(panelShape(tokens.geometry.radiusMd, borderColor: tokens.surface.borderStrong)),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(tokens.content.primary),
        textStyle: WidgetStatePropertyAll(textTheme.bodyMedium),
        overlayColor: hoverTint(tokens.surface.overlay, tokens.accent.primary),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(tokens.surface.overlay),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(hasShadow || hasGlow ? 4 : 0),
        shape: WidgetStatePropertyAll(panelShape(tokens.geometry.radiusMd, borderColor: tokens.surface.borderStrong)),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: tokens.surface.sunken,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(tokens.geometry.radiusMd), borderSide: edge()),
      ),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      backgroundColor: Colors.transparent,
      collapsedBackgroundColor: Colors.transparent,
      iconColor: tokens.content.secondary,
      collapsedIconColor: tokens.content.tertiary,
      textColor: tokens.content.primary,
      collapsedTextColor: tokens.content.primary,
      shape: const RoundedRectangleBorder(side: BorderSide.none),
      collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
    ),

    // — Inputs -------------------------------------------------------------
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: tokens.surface.sunken,
      hintStyle: textTheme.bodyMedium?.copyWith(color: tokens.content.tertiary),
      labelStyle: textTheme.bodyMedium?.copyWith(color: tokens.content.secondary),
      helperStyle: textTheme.bodySmall?.copyWith(color: tokens.content.tertiary),
      errorStyle: textTheme.bodySmall?.copyWith(color: scheme.error),
      contentPadding: EdgeInsets.symmetric(horizontal: tokens.space.md, vertical: tokens.space.sm),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(tokens.geometry.radiusMd), borderSide: edge()),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(tokens.geometry.radiusMd), borderSide: edge()),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.geometry.radiusMd),
        borderSide: BorderSide(color: tokens.accent.primary, width: tokens.geometry.focusRingWidth),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.geometry.radiusMd),
        borderSide: BorderSide(color: scheme.error, width: tokens.geometry.borderWidth),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.geometry.radiusMd),
        borderSide: BorderSide(color: tokens.surface.borderSubtle, width: tokens.geometry.borderWidth),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: tokens.accent.primary,
      selectionColor: tokens.accent.primary.withValues(alpha: 0.32),
      selectionHandleColor: tokens.accent.primary,
    ),

    // — Buttons --------------------------------------------------------
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(tokens.surface.raised),
        foregroundColor: WidgetStatePropertyAll(tokens.content.primary),
        overlayColor: hoverTint(tokens.surface.raised, tokens.accent.primary),
        elevation: const WidgetStatePropertyAll(0),
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: tokens.space.lg)),
        minimumSize: WidgetStatePropertyAll(Size(0, tokens.space.controlHeight)),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.geometry.radiusSm), side: edge())),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? tokens.surface.raised : tokens.accent.primary,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? tokens.content.tertiary : tokens.accent.onPrimary,
        ),
        overlayColor: WidgetStatePropertyAll(tokens.accent.onPrimary.withValues(alpha: tokens.effects.hoverTintAlpha)),
        elevation: const WidgetStatePropertyAll(0),
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: tokens.space.lg)),
        minimumSize: WidgetStatePropertyAll(Size(0, tokens.space.controlHeight)),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.geometry.radiusSm))),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(tokens.content.primary),
        overlayColor: hoverTint(Colors.transparent, tokens.accent.primary),
        side: WidgetStatePropertyAll(BorderSide(color: tokens.surface.borderStrong, width: tokens.geometry.borderWidth)),
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: tokens.space.lg)),
        minimumSize: WidgetStatePropertyAll(Size(0, tokens.space.controlHeight)),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.geometry.radiusSm))),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(tokens.accent.primary),
        overlayColor: hoverTint(Colors.transparent, tokens.accent.primary),
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: tokens.space.md)),
        minimumSize: WidgetStatePropertyAll(Size(0, tokens.space.controlHeight)),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.geometry.radiusSm))),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? tokens.content.tertiary : tokens.content.secondary,
        ),
        overlayColor: hoverTint(Colors.transparent, tokens.accent.primary),
        iconSize: WidgetStatePropertyAll(tokens.space.iconMd),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? tokens.accent.muted : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? tokens.accent.primary : tokens.content.secondary,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: tokens.surface.borderStrong, width: tokens.geometry.borderWidth)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.geometry.radiusSm))),
        textStyle: WidgetStatePropertyAll(textTheme.labelMedium),
      ),
    ),

    // — Selection controls -------------------------------------------------
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? tokens.accent.onPrimary : tokens.content.secondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? tokens.accent.primary : tokens.surface.borderStrong,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? tokens.accent.primary : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(tokens.accent.onPrimary),
      side: BorderSide(color: tokens.surface.borderStrong, width: tokens.geometry.borderWidth),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.geometry.radiusSm / 2)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? tokens.accent.primary : tokens.surface.borderStrong,
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: tokens.accent.primary,
      inactiveTrackColor: tokens.surface.border,
      thumbColor: tokens.accent.primary,
      overlayColor: tokens.accent.primary.withValues(alpha: tokens.effects.hoverTintAlpha),
      valueIndicatorColor: tokens.surface.overlay,
      valueIndicatorTextStyle: textTheme.labelMedium?.copyWith(color: tokens.content.primary),
    ),

    // — Feedback -------------------------------------------------------
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: tokens.surface.overlay,
        borderRadius: BorderRadius.circular(tokens.geometry.radiusSm),
        border: hasBorder ? Border.fromBorderSide(edge(tokens.surface.borderStrong)) : null,
        boxShadow: depthShadow(tokens.effects.shadowSm),
      ),
      textStyle: textTheme.bodySmall?.copyWith(color: tokens.content.primary),
      padding: EdgeInsets.symmetric(horizontal: tokens.space.sm, vertical: tokens.space.xs),
      waitDuration: tokens.motion.standard,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.onInverseSurface),
      actionTextColor: tokens.accent.primary,
      behavior: SnackBarBehavior.floating,
      elevation: hasShadow || hasGlow ? 4 : 0,
      shape: panelShape(tokens.geometry.radiusMd),
    ),
    badgeTheme: BadgeThemeData(
      backgroundColor: tokens.accent.primary,
      textColor: tokens.accent.onPrimary,
      textStyle: textTheme.labelSmall?.copyWith(color: tokens.accent.onPrimary),
      padding: EdgeInsets.symmetric(horizontal: tokens.space.xs),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: tokens.accent.primary,
      linearTrackColor: tokens.surface.border,
      circularTrackColor: tokens.surface.border,
    ),

    // — Lists, chips, dividers, scrollbars ------------------------------
    chipTheme: ChipThemeData(
      backgroundColor: tokens.surface.raised,
      side: edge(),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.geometry.radiusSm)),
      labelStyle: textTheme.labelMedium?.copyWith(color: tokens.content.primary),
      // The chip's fill when selected is `accent.muted` — a translucent tint,
      // still close to the page background — not a solid `accent.primary`
      // fill. `onPrimary` (dark, meant for text on a solid accent fill) was
      // unreadable here; `accent.primary` itself is what actually contrasts
      // against the muted background, matching `checkmarkColor` below.
      secondaryLabelStyle: textTheme.labelMedium?.copyWith(color: tokens.accent.primary),
      selectedColor: tokens.accent.muted,
      disabledColor: tokens.surface.base,
      checkmarkColor: tokens.accent.primary,
      iconTheme: IconThemeData(size: tokens.space.iconSm, color: tokens.content.secondary),
      padding: EdgeInsets.symmetric(horizontal: tokens.space.sm),
    ),
    dividerTheme: DividerThemeData(color: tokens.surface.border, thickness: tokens.geometry.hairline, space: tokens.geometry.hairline),
    listTileTheme: ListTileThemeData(
      iconColor: tokens.content.secondary,
      textColor: tokens.content.primary,
      selectedColor: tokens.accent.primary,
      selectedTileColor: tokens.accent.muted,
      titleTextStyle: textTheme.bodyLarge,
      subtitleTextStyle: textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
      contentPadding: EdgeInsets.symmetric(horizontal: tokens.space.md),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(tokens.content.tertiary.withValues(alpha: 0.5)),
      trackColor: const WidgetStatePropertyAll(Colors.transparent),
      radius: Radius.circular(tokens.geometry.radiusFull),
      thickness: const WidgetStatePropertyAll(8),
    ),
    dataTableTheme: DataTableThemeData(
      headingTextStyle: textTheme.labelMedium?.copyWith(color: tokens.content.secondary),
      dataTextStyle: textTheme.bodyMedium,
      dividerThickness: tokens.geometry.hairline,
      headingRowColor: WidgetStatePropertyAll(tokens.surface.raised),
      dataRowColor: hoverTint(Colors.transparent, tokens.accent.primary),
    ),

    // — Navigation -------------------------------------------------------
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: tokens.accent.muted,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.geometry.radiusSm)),
      selectedIconTheme: IconThemeData(color: tokens.accent.primary, size: tokens.space.iconMd),
      unselectedIconTheme: IconThemeData(color: tokens.content.secondary, size: tokens.space.iconMd),
      selectedLabelTextStyle: textTheme.labelMedium?.copyWith(color: tokens.accent.primary),
      unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(color: tokens.content.secondary),
      useIndicator: true,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: tokens.accent.primary,
      unselectedLabelColor: tokens.content.secondary,
      labelStyle: textTheme.labelLarge,
      unselectedLabelStyle: textTheme.labelLarge,
      indicatorColor: tokens.accent.primary,
      dividerColor: tokens.surface.border,
      overlayColor: hoverTint(Colors.transparent, tokens.accent.primary),
    ),
  );
}

ColorScheme _colorScheme(AppTokens t) => ColorScheme(
  brightness: t.brightness,
  primary: t.accent.primary,
  onPrimary: t.accent.onPrimary,
  primaryContainer: t.accent.muted,
  onPrimaryContainer: t.accent.primary,
  secondary: t.accent.secondary,
  onSecondary: t.accent.onPrimary,
  secondaryContainer: t.accent.secondary.withValues(alpha: 0.18),
  onSecondaryContainer: t.accent.secondary,
  tertiary: t.status.info.fg,
  onTertiary: t.accent.onPrimary,
  tertiaryContainer: t.status.info.container,
  onTertiaryContainer: t.status.info.onContainer,
  error: t.status.bad.fg,
  onError: t.accent.onPrimary,
  errorContainer: t.status.bad.container,
  onErrorContainer: t.status.bad.onContainer,
  surface: t.surface.base,
  onSurface: t.content.primary,
  surfaceContainerLowest: t.surface.sunken,
  surfaceContainerLow: t.surface.base,
  surfaceContainer: t.surface.base,
  surfaceContainerHigh: t.surface.raised,
  surfaceContainerHighest: t.surface.overlay,
  onSurfaceVariant: t.content.secondary,
  outline: t.surface.borderStrong,
  outlineVariant: t.surface.border,
  shadow: const Color(0xFF000000),
  scrim: t.surface.scrim,
  inverseSurface: Color.lerp(t.surface.base, t.content.primary, 0.9)!,
  onInverseSurface: t.surface.base,
  inversePrimary: t.accent.primary,
  surfaceTint: Colors.transparent,
);

TextTheme _textTheme(AppTokens t) {
  final scale = t.type.scale;
  final tight = t.type.tightTracking;
  final loose = t.type.looseTracking;
  final lineHeight = t.type.bodyHeight;
  final headingColor = t.content.primary;
  final bodyColor = t.content.primary;
  final mutedColor = t.content.secondary;

  TextStyle heading(double size) =>
      TextStyle(fontFamily: t.type.display, fontSize: size * scale, fontWeight: t.type.headingWeight, letterSpacing: tight, height: lineHeight, color: headingColor);

  TextStyle body(double size, {FontWeight? weight, Color? color, double? height, double tracking = 0}) => TextStyle(
    fontFamily: t.type.body,
    fontSize: size * scale,
    fontWeight: weight ?? t.type.bodyWeight,
    letterSpacing: tracking,
    height: height ?? lineHeight,
    color: color ?? bodyColor,
  );

  return TextTheme(
    displayLarge: heading(52),
    displayMedium: heading(41),
    displaySmall: heading(33),
    headlineLarge: heading(29),
    headlineMedium: heading(26),
    // pageTitle
    headlineSmall: heading(22),
    // sectionTitle
    titleLarge: heading(17),
    // cardTitle
    titleMedium: body(15, weight: FontWeight.w600),
    // subTitle
    titleSmall: body(13, weight: FontWeight.w600),
    // body
    bodyMedium: body(13.5),
    // bodyStrong
    bodyLarge: body(14, weight: FontWeight.w600),
    // caption
    bodySmall: body(12, color: mutedColor),
    labelLarge: body(13, weight: FontWeight.w600, height: 1.2),
    // label
    labelMedium: body(12, weight: FontWeight.w600, height: 1.2, tracking: loose),
    // micro
    labelSmall: body(10.5, weight: FontWeight.w700, height: 1.2, tracking: loose, color: mutedColor),
  );
}

/// DESIGN_SYSTEM §1.8 — density is applied once, here, to `space` and
/// `type.scale`. Nothing outside `core/theme/` knows density exists.
AppTokens _applyDensity(AppTokens tokens, Density density) {
  if (density == Density.comfortable) return tokens;
  return tokens.copyWith(
    space: tokens.space.scaled(density.spaceScale),
    type: TypographyTokens(
      display: tokens.type.display,
      body: tokens.type.body,
      mono: tokens.type.mono,
      scale: tokens.type.scale * density.typeScale,
      bodyHeight: tokens.type.bodyHeight,
      tightTracking: tokens.type.tightTracking,
      looseTracking: tokens.type.looseTracking,
      bodyWeight: tokens.type.bodyWeight,
      headingWeight: tokens.type.headingWeight,
      uppercaseLabels: tokens.type.uppercaseLabels,
      iconWeight: tokens.type.iconWeight,
    ),
  );
}
