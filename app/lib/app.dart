import 'package:flutter/material.dart';

import 'core/app_theme.dart';
import 'shell/app_shell.dart';

class ControlCenterApp extends StatelessWidget {
  const ControlCenterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Insta-Automate Control Center',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF6C63FF),
        scaffoldBackgroundColor: Colors.transparent,
        extensions: const [AppPalette.dark],
      ),
      home: const AppShell(),
    );
  }
}
