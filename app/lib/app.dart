import 'package:flutter/material.dart';

import 'core/theme/build_theme.dart';
import 'core/theme/themes/classic.dart';
import 'shell/app_shell.dart';

class ControlCenterApp extends StatelessWidget {
  const ControlCenterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Insta-Automate Control Center',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      // Only Classic exists through V2.1 — the theme picker (V2.4) is what
      // lets this vary, persisted via `theme_controller.dart`.
      darkTheme: buildTheme(buildClassicTokens()),
      home: const AppShell(),
    );
  }
}
