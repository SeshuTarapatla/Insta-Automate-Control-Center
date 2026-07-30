import 'dart:convert';
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

/// Persists window position/size across launches so the app reopens where
/// the user left it, instead of always centering at a default size.
class WindowGeometry with WindowListener {
  static const _prefsKey = 'window_bounds';

  Future<Rect?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return null;

    final map = jsonDecode(raw) as Map<String, dynamic>;
    return Rect.fromLTWH(
      (map['x'] as num).toDouble(),
      (map['y'] as num).toDouble(),
      (map['width'] as num).toDouble(),
      (map['height'] as num).toDouble(),
    );
  }

  void attach() => windowManager.addListener(this);

  Future<void> _save() async {
    final bounds = await windowManager.getBounds();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode({
        'x': bounds.left,
        'y': bounds.top,
        'width': bounds.width,
        'height': bounds.height,
      }),
    );
  }

  @override
  void onWindowResized() => _save();

  @override
  void onWindowMoved() => _save();

  @override
  void onWindowClose() => _save();
}
