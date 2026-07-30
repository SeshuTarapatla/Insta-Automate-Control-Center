import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/window_geometry.dart';

const _defaultSize = Size(1280, 820);
const _minimumSize = Size(1024, 700);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await Window.initialize();

  final geometry = WindowGeometry();
  final savedBounds = await geometry.load();

  const windowOptions = WindowOptions(
    size: _defaultSize,
    minimumSize: _minimumSize,
    center: true,
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (savedBounds != null) {
      await windowManager.setBounds(savedBounds);
    }
    geometry.attach();
    await Window.setEffect(effect: WindowEffect.mica, dark: true);
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const ProviderScope(child: ControlCenterApp()));
}
