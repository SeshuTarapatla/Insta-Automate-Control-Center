import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/core/theme/build_theme.dart';
import 'package:ia_control_center/core/theme/themes/classic.dart';

/// Every `ui/` widget test renders against the real built theme (not a bare
/// `ThemeData()`) since these components are the ones actually reading
/// `theme.tokens` — a bare theme would only ever exercise the fallback path
/// `AppTokensX.tokens` provides for pre-v2 tests.
Future<void> pumpUi(WidgetTester tester, Widget child, {Size size = const Size(1024, 700)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: buildTheme(buildClassicTokens()),
        home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
      ),
    ),
  );
}
