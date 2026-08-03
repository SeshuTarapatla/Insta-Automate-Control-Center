import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'shell/hotkey.dart';
import 'shell/tray.dart';
import 'shell/window_lifecycle.dart';

const _minimumSize = Size(1024, 700);

// scrcpy's own launch geometry (my_modules/scrcpy.py, D55/D65's fix) is
// fixed: --window-x=1, --window-y=45, --window-height=1480, width scaled to
// the phone's aspect ratio (~464:1024 for the current test phone, ~671px).
// These are the *physical* pixels scrcpy (a native SDL app) actually uses -
// window_manager/screen_retriever both work in Flutter's logical pixels, so
// this gets divided by the display's scale factor below before being
// handed to setPosition (D67's first attempt skipped that conversion
// entirely and positioned the window ~1.5x too far right on a 150%-scaled
// display). Hardcoded here rather than queried live from the agent (a more
// robust alternative considered and deferred - would need a new endpoint
// exposing the mirror's real on-screen bounds) so the app opens filling
// the space right next to the mirror instead of leaving a visible gap.
// Revisit if a different phone's aspect ratio (hence scrcpy's window
// width) ever makes this stale.
const _mirrorRightEdgePhysical = 1 + 671.0;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await Window.initialize();

  final display = await screenRetriever.getPrimaryDisplay();
  final scale = (display.scaleFactor ?? 1).toDouble();
  // `display.size`/`.position` are the full monitor bounds — taskbar
  // included. Sizing the window to that (as this did until found live,
  // CP 7.1 checkpoint testing) extends its bottom edge under the taskbar,
  // clipping whatever's rendered there — the exact "content overflows off
  // the bottom" report. `visibleSize`/`visiblePosition` are the work area
  // the OS actually keeps clear of taskbars/docked toolbars on any edge,
  // which is what "fill the exact space next to the mirror" (D69) always
  // meant. Falls back to the full bounds only if the platform channel ever
  // returns null for these (undocumented when that happens, if ever).
  final visibleSize = display.visibleSize ?? display.size;
  final visiblePosition = display.visiblePosition ?? Offset.zero;
  // Flush against the mirror, not a few px short of it — a gap there was
  // reported as wasted space too, not just the app's own width falling
  // short of the screen's right edge. The -5 corrects a small residual
  // (a few logical px) still visible after the scale-factor fix alone —
  // likely DWM's own invisible border/shadow around a borderless window,
  // not something further unit-conversion math explains — tuned by hand
  // against the real screen (D69) rather than guessed.
  final startX = _mirrorRightEdgePhysical / scale - 5;
  final width = visibleSize.width - startX;

  final windowOptions = WindowOptions(
    size: Size(width < _minimumSize.width ? _minimumSize.width : width, visibleSize.height),
    minimumSize: _minimumSize,
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );

  // Sequenced directly here, not via `waitUntilReadyToShow`'s own callback
  // argument — that callback is invoked fire-and-forget (never awaited by
  // the library itself), so `runApp()` right after it could start building
  // the widget tree before `setPosition`/`show` below actually finish,
  // racing whatever position the OS gives the window by default.
  await windowManager.waitUntilReadyToShow(windowOptions);

  // Deliberately not restoring a saved size/position across launches
  // (the `WindowGeometry` mechanism this replaced) — the app is meant to
  // fill the exact space next to the mirror every time, and a remembered
  // size from a previous manual resize is exactly what left the screen's
  // right edge unused here (D69).
  await windowManager.setPosition(Offset(startX, visiblePosition.dy));
  await Window.setEffect(effect: WindowEffect.mica, dark: true);
  await windowManager.show();
  await windowManager.focus();

  // CP 7.3: a tray icon + global hotkey need something to bring back, so the
  // title bar's close button (unchanged — still plain `windowManager.close`)
  // now hides instead of exiting; `setPreventClose` is what makes `close()`
  // reach `CloseToTrayListener` instead of actually closing.
  windowManager.addListener(CloseToTrayListener());
  await windowManager.setPreventClose(true);
  await registerShowHideHotKey();

  // A real `ProviderContainer`, not just `ProviderScope`'s implicit one —
  // the tray menu (`AppTray`) reads/watches providers from outside the
  // widget tree entirely, the same reason the window setup above already
  // can't go through a `BuildContext`.
  final container = ProviderContainer();
  await AppTray(container).init();

  runApp(UncontrolledProviderScope(container: container, child: const ControlCenterApp()));
}
