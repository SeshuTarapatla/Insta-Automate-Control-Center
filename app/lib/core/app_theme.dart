import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// The palette every page was independently hand-coding the same handful of
/// colors from — service/flow/dependency status (green/amber/red reads as
/// health at a glance; the seed scheme's own primary does not), the
/// connection dot, and the service terminal's full ANSI set. Centralized
/// here as a `ThemeExtension` (CP 7.3) so a future palette tweak is one file
/// instead of a grep across a dozen — same visual result as before, one
/// source of truth. Registered once on `app.dart`'s `darkTheme`; the app
/// stays dark-only, no light variant was asked for.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.statusGood,
    required this.statusInfo,
    required this.statusWarn,
    required this.terminal,
  });

  /// Running / connected / ok.
  final Color statusGood;

  /// Starting / connecting / waiting.
  final Color statusInfo;

  /// Backoff / unhealthy / warn.
  final Color statusWarn;

  /// Bad/failed status stays `scheme.error` at every call site instead of a
  /// fourth palette color — it's already exactly this red and already
  /// themeable on its own.
  final TerminalPalette terminal;

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

  // A discrete named palette, not a continuum — there's no meaningful
  // in-between of "amber" and "green" to interpolate toward, so this only
  // ever needs to support Flutter's implicit theme-change animations
  // without throwing, not actually blend.
  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) => t < 0.5 ? this : (other as AppPalette? ?? this);
}

/// Mirrors `service_terminal.dart`'s previously-inline `TerminalTheme` —
/// same colors, just named and reused instead of redeclared.
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

/// `app.dart`'s real `ThemeData` always registers `AppPalette.dark`; the
/// fallback here only matters for widget tests that build their own bare
/// `ThemeData` — this app is dark-only, so falling back to the same dark
/// palette is the correct value there too, not a workaround.
extension AppPaletteX on ThemeData {
  AppPalette get palette => extension<AppPalette>() ?? AppPalette.dark;
}
