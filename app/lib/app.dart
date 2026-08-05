import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/build_theme.dart';
import 'core/theme/registry.dart';
import 'core/theme/theme_controller.dart';
import 'core/theme/tokens.dart';
import 'shell/app_shell.dart';

class ControlCenterApp extends ConsumerStatefulWidget {
  const ControlCenterApp({super.key});

  @override
  ConsumerState<ControlCenterApp> createState() => _ControlCenterAppState();
}

/// `WidgetsBindingObserver` rather than reading `MediaQuery` — the theme is
/// built here, above `MaterialApp`, specifically so a theme switch can
/// animate the whole app via `MaterialApp`'s own `AnimatedTheme` (DESIGN_
/// SYSTEM.md §8); `platformDispatcher.accessibilityFeatures` is the same OS
/// signal without needing a `BuildContext` that's guaranteed to already sit
/// under a `MediaQuery`.
class _ControlCenterAppState extends ConsumerState<ControlCenterApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAccessibilityFeatures() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(themeControllerProvider);
    final osReducedMotion = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    final reduced = switch (prefs.reduceMotion) {
      ReduceMotionSetting.always => true,
      ReduceMotionSetting.never => false,
      ReduceMotionSetting.auto => osReducedMotion,
    };

    final rawTokens = buildTokensFor(prefs.themeId);
    var tokens = rawTokens.copyWith(motion: rawTokens.motion.withReduced(reduced));
    if (prefs.terminalOverride == TerminalOverride.alwaysDark) {
      tokens = tokens.copyWith(terminal: TerminalPalette.dark);
    }
    final themeData = buildTheme(tokens, density: prefs.density);

    return MaterialApp(
      title: 'Insta-Automate Control Center',
      debugShowCheckedModeBanner: false,
      // The app picks its own brightness via `AppTokens.brightness`
      // (Daylight/Swiss are light, the rest dark) rather than following the
      // OS — `theme:` is always the one MaterialApp uses.
      themeMode: ThemeMode.light,
      theme: themeData,
      // DESIGN_SYSTEM §8 — "the switch animates rather than hard-cutting."
      // `MaterialApp` already wraps its child in `AnimatedTheme`; this is
      // the only wiring a real crossfade needs once `AppTokens.lerp` does
      // real interpolation. Zero under reduced motion, same as every other
      // duration in the token set.
      themeAnimationDuration: reduced ? Duration.zero : tokens.motion.slow,
      themeAnimationCurve: tokens.motion.enter,
      home: const AppShell(),
    );
  }
}
