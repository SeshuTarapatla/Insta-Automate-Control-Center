import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_snack_bar.dart';
import '../../core/file_opener.dart';
import '../../core/instagram_url.dart';
import '../../core/library_image.dart';
import '../../core/library_models.dart';
import '../../ui/icons.dart';

/// One grid cell: a thumbnail, a selection ring/badge, and the interactions
/// CP 5.3/V2.10 ask for — double-click opens the lightbox (SCREENS.md §5c;
/// copy-id lives only in the context menu now, unchanged), right-click opens
/// a context menu to open the real Instagram URL or copy the id/entity name.
/// Left-click selection semantics (plain toggle vs shift-range) are decided
/// by the caller, which owns the selection state — this widget only reports
/// whether Shift was held. A plain click always toggles (no ctrl needed), so
/// clicking several images in a row builds up a batch.
class LibraryTile extends StatelessWidget {
  const LibraryTile({
    super.key,
    required this.entry,
    required this.selected,
    required this.focused,
    required this.thumbWidth,
    required this.entityLabel,
    required this.onPrimaryTap,
    required this.onRequestFocus,
    required this.onOpenLightbox,
  });

  final LibraryImageEntry entry;
  final bool selected;
  final bool focused;
  final int thumbWidth;
  final String? entityLabel;
  final void Function({required bool shift}) onPrimaryTap;
  final VoidCallback onRequestFocus;
  final VoidCallback onOpenLightbox;

  String get _id => entry.name.endsWith('.jpg') ? entry.name.substring(0, entry.name.length - 4) : entry.name;

  void _copy(BuildContext context, String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    AppSnackBar.show(context, '$label: $value');
  }

  void _openInstagram(BuildContext context) {
    final uri = instagramUrl(entry.name);
    if (!FileOpener.openUrl(uri.toString()) && context.mounted) {
      AppSnackBar.show(context, 'Could not open $uri', isError: true);
    }
  }

  Future<void> _showMenu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selection = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        PopupMenuItem(value: 'open', child: Row(children: [AppIcon(AppIcons.openExternal, size: IconSize.sm), const SizedBox(width: 10), const Text('Open on Instagram')])),
        PopupMenuItem(value: 'copy_id', child: Row(children: [AppIcon(AppIcons.copy, size: IconSize.sm), const SizedBox(width: 10), const Text('Copy id')])),
        if (entityLabel != null)
          PopupMenuItem(value: 'copy_entity', child: Row(children: [AppIcon(AppIcons.copy, size: IconSize.sm), const SizedBox(width: 10), const Text('Copy entity name')])),
      ],
    );
    if (!context.mounted) return;
    switch (selection) {
      case 'open':
        _openInstagram(context);
      case 'copy_id':
        _copy(context, _id, 'Copied');
      case 'copy_entity':
        if (entityLabel case final label?) _copy(context, label, 'Copied entity');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderColor = selected ? scheme.primary : (focused ? scheme.outline : Colors.transparent);

    return GestureDetector(
      onTapDown: (_) {
        onRequestFocus();
        onPrimaryTap(shift: HardwareKeyboard.instance.isShiftPressed);
      },
      onDoubleTap: onOpenLightbox,
      onSecondaryTapDown: (details) {
        onRequestFocus();
        _showMenu(context, details.globalPosition);
      },
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: borderColor, width: selected ? 2.5 : 1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LibraryThumbnail(path: entry.path, width: thumbWidth),
            ),
            if (selected)
              Positioned(
                top: 4,
                right: 4,
                child: CircleAvatar(
                  radius: 9,
                  backgroundColor: scheme.primary,
                  child: AppIcon(AppIcons.check, size: IconSize.sm, color: scheme.onPrimary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
