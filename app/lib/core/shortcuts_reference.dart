import 'package:flutter/material.dart';

import 'theme/tokens.dart';

/// Every keyboard binding in the app, assembled by hand from the real call
/// sites (CP 7.3) — nothing declares these in one place today, so this is
/// the closest thing to a registry rather than a read of one. Keep in step
/// with `settings/config_file_bar.dart` (Ctrl+E), `settings/devices_tab.dart`
/// (Ctrl+F/Esc), `library/library_grid.dart` (the rest), `shell/hotkey.dart`
/// (Ctrl+Alt+I) and this file's own global `?` binding.
class ShortcutEntry {
  const ShortcutEntry({required this.keys, required this.description, required this.scope});

  final String keys;
  final String description;
  final String scope;
}

const shortcutReference = [
  ShortcutEntry(keys: 'Ctrl+Alt+I', description: 'Show or hide the window', scope: 'Global'),
  ShortcutEntry(keys: '?', description: 'Open this shortcut list', scope: 'Global'),
  ShortcutEntry(keys: 'Ctrl+E', description: 'Open config.env for editing', scope: 'Settings'),
  ShortcutEntry(keys: 'Ctrl+F', description: 'Search paired devices', scope: 'Settings › Devices'),
  ShortcutEntry(keys: 'Esc', description: 'Close device search', scope: 'Settings › Devices'),
  ShortcutEntry(keys: 'Click / Space', description: 'Toggle the focused image', scope: 'Library'),
  ShortcutEntry(keys: 'Arrow keys', description: 'Move focus by one image or row', scope: 'Library'),
  ShortcutEntry(
    keys: 'Shift + click / arrow',
    description: 'Extend the selection to here',
    scope: 'Library',
  ),
  ShortcutEntry(keys: 'Ctrl+A', description: 'Select every image in this folder', scope: 'Library'),
  ShortcutEntry(keys: 'Delete', description: 'Delete the current selection', scope: 'Library'),
];

Future<void> showShortcutsReference(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final tokens = theme.tokens;
      final byScope = <String, List<ShortcutEntry>>{};
      for (final entry in shortcutReference) {
        byScope.putIfAbsent(entry.scope, () => []).add(entry);
      }

      return AlertDialog(
        title: const Text('Keyboard shortcuts'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final scope in byScope.keys) ...[
                  Padding(
                    padding: EdgeInsets.only(top: tokens.space.md, bottom: tokens.space.xs),
                    child: Text(
                      scope,
                      style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
                    ),
                  ),
                  for (final entry in byScope[scope]!)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: tokens.space.xs / 2),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 150,
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: tokens.space.xs, vertical: tokens.space.xs / 1.3),
                              decoration: BoxDecoration(
                                color: tokens.surface.raised,
                                borderRadius: BorderRadius.circular(tokens.geometry.radiusSm),
                                border: Border.all(color: tokens.surface.border),
                              ),
                              child: Text(
                                entry.keys,
                                style: theme.textTheme.bodySmall?.copyWith(fontFamily: tokens.type.mono),
                              ),
                            ),
                          ),
                          SizedBox(width: tokens.space.md),
                          Expanded(child: Text(entry.description, style: theme.textTheme.bodySmall)),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      );
    },
  );
}
