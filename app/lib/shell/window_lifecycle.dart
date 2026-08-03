import 'package:window_manager/window_manager.dart';

/// With a tray icon (CP 7.3), the title bar's close button — already wired
/// to plain `windowManager.close` (`title_bar.dart`, unchanged) — should hide
/// the window rather than exit the process, since a global show/hide hotkey
/// and a tray icon both need something still running to bring back. Real
/// quit becomes the tray menu's own Quit entry (`tray.dart`), which flips
/// `setPreventClose` back off first.
///
/// `windowManager.close()` calling into this instead of actually closing is
/// exactly what `setPreventClose(true)` is for — every `WindowListener` still
/// fires, `onWindowClose` included, so this is the standard interception
/// point, not a workaround.
class CloseToTrayListener with WindowListener {
  @override
  void onWindowClose() {
    windowManager.hide();
  }
}
