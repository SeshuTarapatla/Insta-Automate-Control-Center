import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Global show/hide hotkey (ARCHITECTURE §9, CP 7.3) — Ctrl+Alt+I, chosen for
/// being unlikely to collide with anything else on this machine. System-scope
/// (not `HotKeyScope.inapp`) so it fires even while the window is hidden or
/// another app has focus, which is the whole point of a global hotkey.
final _showHideHotKey = HotKey(
  key: LogicalKeyboardKey.keyI,
  modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
  scope: HotKeyScope.system,
);

Future<void> registerShowHideHotKey() async {
  await hotKeyManager.register(
    _showHideHotKey,
    keyDownHandler: (_) async {
      if (await windowManager.isVisible()) {
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    },
  );
}
