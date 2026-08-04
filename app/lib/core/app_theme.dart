import 'package:flutter/material.dart';

import 'theme/tokens.dart';

/// The pre-v2 status palette (CP 7.3). **Deprecated shim** (DESIGN_SYSTEM.md
/// §1/§1.4, PLAN_V2.md V2.1): kept only so the ~5 call sites that still read
/// `theme.palette.statusGood`/`.terminal` keep compiling until V2.3 migrates
/// them onto `theme.tokens.status`/`.terminal` directly. Never construct one
/// of these directly — go through `AppPaletteX.palette` below, which reads
/// the real values from the registered `AppTokens`.
@immutable
@Deprecated('Read theme.tokens.status / theme.tokens.terminal instead — this shim is removed once V2.3 migrates the last call site.')
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({required this.statusGood, required this.statusInfo, required this.statusWarn, required this.terminal});

  final Color statusGood;
  final Color statusInfo;
  final Color statusWarn;
  final TerminalPalette terminal;

  /// Only reached when no `AppTokens` extension is registered — real widget
  /// tests that build a bare `ThemeData()` with no theme wiring at all. The
  /// app itself always registers `AppTokens` via `buildTheme()`.
  static const dark = AppPalette(
    statusGood: Color(0xFF3DD68C),
    statusInfo: Color(0xFF6EA8FE),
    statusWarn: Color(0xFFFFB454),
    terminal: TerminalPalette.dark,
  );

  @override
  AppPalette copyWith({Color? statusGood, Color? statusInfo, Color? statusWarn, TerminalPalette? terminal}) =>
      AppPalette(
        statusGood: statusGood ?? this.statusGood,
        statusInfo: statusInfo ?? this.statusInfo,
        statusWarn: statusWarn ?? this.statusWarn,
        terminal: terminal ?? this.terminal,
      );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) => t < 0.5 ? this : (other as AppPalette? ?? this);
}

/// Deprecated shim (see `AppPalette` above) — builds the legacy shape on
/// demand from whichever `AppTokens` is actually registered, so a theme
/// switch (V2.4) is still reflected everywhere this getter is still used.
extension AppPaletteX on ThemeData {
  // ignore: deprecated_member_use_from_same_package
  AppPalette get palette {
    final tokens = extension<AppTokens>();
    if (tokens == null) {
      // ignore: deprecated_member_use_from_same_package
      return AppPalette.dark;
    }
    // ignore: deprecated_member_use_from_same_package
    return AppPalette(
      statusGood: tokens.status.good.fg,
      statusInfo: tokens.status.info.fg,
      statusWarn: tokens.status.warn.fg,
      terminal: tokens.terminal,
    );
  }
}
