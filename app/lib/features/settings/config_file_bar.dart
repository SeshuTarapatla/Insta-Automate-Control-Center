import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_snack_bar.dart';
import '../../core/file_opener.dart';
import '../../core/theme/tokens.dart';

/// Quick access to the file every control on this page ultimately writes to.
/// Shows where config.env actually lives, and opens it in the user's default
/// editor (Ctrl+E), reveals it in Explorer, or copies the path.
class ConfigFileBar extends StatelessWidget {
  const ConfigFileBar({super.key, required this.path});

  final String path;

  static const openIntentKey = SingleActivator(LogicalKeyboardKey.keyE, control: true);

  Future<void> _open(BuildContext context) async {
    if (await FileOpener.openForEditing(path) || !context.mounted) return;
    AppSnackBar.show(context, 'Could not open $path', isError: true);
  }

  void _reveal(BuildContext context) {
    if (!FileOpener.revealInExplorer(path)) {
      AppSnackBar.show(context, 'Could not reveal $path', isError: true);
    }
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: path));
    if (context.mounted) AppSnackBar.show(context, 'Path copied');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('config.env', style: theme.textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(
                  path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: theme.tokens.type.mono,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.content_copy_outlined),
            tooltip: 'Copy path',
            onPressed: () => _copy(context),
          ),
          IconButton(
            icon: const Icon(Icons.folder_open_outlined),
            tooltip: 'Show in folder',
            onPressed: () => _reveal(context),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Open in your editor  (Ctrl+E)',
            child: FilledButton.tonalIcon(
              onPressed: () => _open(context),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Open'),
            ),
          ),
        ],
      ),
    );
  }
}
