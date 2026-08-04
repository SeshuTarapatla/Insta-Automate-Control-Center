import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_snack_bar.dart';
import '../../core/file_opener.dart';
import '../../core/theme/tokens.dart';
import '../../ui/icons.dart';
import '../../ui/surfaces.dart';

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
    final tokens = theme.tokens;

    return AppPanel(
      level: SurfaceLevel.raised,
      padding: EdgeInsets.symmetric(horizontal: tokens.space.lg, vertical: tokens.space.md),
      child: Row(
        children: [
          AppIcon(AppIcons.document, size: IconSize.md, color: tokens.content.secondary),
          SizedBox(width: tokens.space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('config.env', style: theme.textTheme.labelLarge),
                SizedBox(height: tokens.space.xs / 2),
                Text(
                  path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(fontFamily: tokens.type.mono, color: tokens.content.secondary),
                ),
              ],
            ),
          ),
          SizedBox(width: tokens.space.md),
          IconButton(
            icon: AppIcon(AppIcons.copy, size: IconSize.md),
            tooltip: 'Copy path',
            onPressed: () => _copy(context),
          ),
          IconButton(
            icon: AppIcon(AppIcons.folderOpen, size: IconSize.md),
            tooltip: 'Show in folder',
            onPressed: () => _reveal(context),
          ),
          SizedBox(width: tokens.space.xs),
          Tooltip(
            message: 'Open in your editor  (Ctrl+E)',
            child: FilledButton.tonalIcon(
              onPressed: () => _open(context),
              icon: AppIcon(AppIcons.openExternal, size: IconSize.sm),
              label: const Text('Open'),
            ),
          ),
        ],
      ),
    );
  }
}
