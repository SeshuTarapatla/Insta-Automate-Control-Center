import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart' show Rect;
import 'package:win32/win32.dart';

/// The true maximized bounds for the window's current monitor, in *logical*
/// pixels — excludes the taskbar, unlike the raw display size, which is
/// exactly what real maximize uses and window_manager has no API for.
/// Reaches into Win32 directly, same reasoning as FileOpener's ShellExecute
/// calls (DECISIONS D5). Returns null if anything fails; callers should fall
/// back to `windowManager.maximize()`.
Rect? currentMonitorWorkArea(double devicePixelRatio) {
  final hwnd = GetForegroundWindow();
  if (hwnd.address == 0) return null;

  final monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  if (monitor.address == 0) return null;

  final info = calloc<MONITORINFO>();
  try {
    info.ref.cbSize = sizeOf<MONITORINFO>();
    if (!GetMonitorInfo(monitor, info)) return null;
    final work = info.ref.rcWork;
    return Rect.fromLTRB(
      work.left / devicePixelRatio,
      work.top / devicePixelRatio,
      work.right / devicePixelRatio,
      work.bottom / devicePixelRatio,
    );
  } finally {
    calloc.free(info);
  }
}
