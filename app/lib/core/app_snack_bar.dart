import 'package:flutter/material.dart';

/// One place for transient feedback, so it behaves consistently everywhere.
///
/// The important part is [ScaffoldMessenger.clearSnackBars] before each show:
/// the default messenger *queues*, so a handful of quick edits would otherwise
/// play back-to-back and read as a bar that never goes away. Replacing instead
/// means the bar always reflects the most recent action.
class AppSnackBar {
  static const _duration = Duration(seconds: 3);
  static const _width = 460.0;

  static void show(
    BuildContext context,
    String message, {
    SnackBarAction? action,
    bool isError = false,
  }) {
    final scheme = Theme.of(context).colorScheme;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: isError ? TextStyle(color: scheme.onErrorContainer) : null,
          ),
          action: action,
          duration: _duration,
          // SnackBar's constructor does `persist = persist ?? action != null`,
          // so *any* snackbar with an action opts out of its own dismiss timer
          // and hangs around forever. Undo is a 3-second offer, not a modal.
          persist: false,
          behavior: SnackBarBehavior.floating,
          width: _width,
          backgroundColor: isError ? scheme.errorContainer : null,
        ),
      );
  }
}
