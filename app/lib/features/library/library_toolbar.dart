import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_snack_bar.dart';
import '../../core/library_models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/icons.dart';
import '../../ui/status.dart';
import '../../ui/text.dart';
import 'entity_yield_dialog.dart';
import 'library_controller.dart';

/// Shared by the toolbar's Delete button and the grid's Delete-key shortcut
/// (`library_grid.dart`) so both paths confirm and report identically.
Future<void> deleteLibrarySelection(BuildContext context, WidgetRef ref, List<LibraryImageEntry> selectedEntries) async {
  if (selectedEntries.isEmpty) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete these images?'),
      content: Text('${selectedEntries.length} image(s) will be sent to the Recycle Bin.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    final paths = selectedEntries.map((e) => e.path).toList();
    final result = await ref.read(libraryImagesControllerProvider.notifier).delete(paths);
    ref.read(librarySelectionProvider.notifier).clear();
    if (context.mounted) {
      AppSnackBar.show(
        context,
        '${result.deleted.length} sent to the Recycle Bin${result.errors.isEmpty ? '' : ' (${result.errors.length} failed)'}',
        isError: result.errors.isNotEmpty,
      );
    }
  } on DioException catch (error) {
    if (context.mounted) AppSnackBar.show(context, describeLibraryError(error), isError: true);
  }
}

/// Selection count + bulk actions + zoom, sitting above the grid. Apply and
/// Delete both confirm first, naming exactly what happens — the same "the
/// dialog names what actually stops" rule `flow_switch_confirm.dart` already
/// established for turning a flow off.
class LibraryToolbar extends ConsumerWidget {
  const LibraryToolbar({super.key, required this.folder, required this.entity});

  final String folder;
  final String? entity;

  Future<void> _selectAll(WidgetRef ref) async {
    final names = await ref.read(libraryImagesControllerProvider.notifier).loadAllNames();
    ref.read(librarySelectionProvider.notifier).selectAll(names);
  }

  Future<void> _apply(BuildContext context, WidgetRef ref, Set<String> selected, String target) async {
    final total = ref.read(libraryImagesControllerProvider).value?.total ?? selected.length;
    final discarded = total - selected.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply this review?'),
        content: Text(
          target == folder
              ? 'Keep ${selected.length} selected image(s) here; send the other $discarded to the Recycle Bin.'
              : 'Move ${selected.length} selected image(s) to "$target"; send the other $discarded to the '
                    'Recycle Bin.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Apply')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final result = await ref.read(libraryImagesControllerProvider.notifier).apply(selected.toList());
      ref.read(librarySelectionProvider.notifier).clear();
      if (context.mounted) {
        final where = result.target == folder ? 'kept' : 'moved to ${result.target}';
        AppSnackBar.show(
          context,
          '${result.moved.length} $where, ${result.trashed.length} sent to the Recycle Bin'
          '${result.errors.isEmpty ? '' : ' (${result.errors.length} failed)'}',
          isError: result.errors.isNotEmpty,
        );
      }
    } on DioException catch (error) {
      if (context.mounted) AppSnackBar.show(context, describeLibraryError(error), isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selection = ref.watch(librarySelectionProvider);
    final images = ref.watch(libraryImagesControllerProvider).value;
    final targets = ref.watch(moveTargetsControllerProvider).value;
    final target = targets?[folder] ?? folder;
    final selectedEntries = images == null
        ? const <LibraryImageEntry>[]
        : images.images.where((e) => selection.selected.contains(e.name)).toList();

    final tokens = theme.tokens;

    return Padding(
      padding: EdgeInsets.fromLTRB(tokens.space.md, tokens.space.sm, tokens.space.md, tokens.space.xs),
      // A single Row here would overflow well before the app's 1024px floor:
      // breadcrumb + count + select-all + a selection cluster + zoom easily
      // exceeds what's left after the folder/entity rail columns. Row 1 keeps
      // only the one thing that must stay on top (the breadcrumb, protected
      // by its own Expanded+ellipsis); everything else is a Wrap, which
      // degrades to more rows instead of overflowing at any width.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entity == null ? folder : '$folder / $entity',
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (entity != null)
                IconButton(
                  tooltip: 'View entity across every stage',
                  icon: AppIcon(AppIcons.insight, size: IconSize.md),
                  onPressed: () => showEntityYieldDialog(context, entity!),
                ),
              if (images != null) ...[
                SizedBox(width: tokens.space.sm),
                NumericText('${images.total}', role: TextRole.caption),
              ],
            ],
          ),
          SizedBox(height: tokens.space.xs),
          Wrap(
            spacing: tokens.space.xs,
            runSpacing: tokens.space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: images == null || images.total == 0 ? null : () => _selectAll(ref),
                child: const Text('Select all'),
              ),
              if (selection.selected.isNotEmpty) ...[
                Text('${selection.selected.length} selected', style: theme.textTheme.bodyMedium),
                _MoveTargetPicker(folder: folder, target: target),
                FilledButton.tonalIcon(
                  onPressed: () => _apply(context, ref, selection.selected, target),
                  icon: AppIcon(AppIcons.apply, size: IconSize.sm),
                  label: const Text('Apply'),
                ),
                OutlinedButton.icon(
                  onPressed: () => deleteLibrarySelection(context, ref, selectedEntries),
                  icon: AppIcon(AppIcons.discard, size: IconSize.sm),
                  label: const Text('Delete'),
                ),
              ],
              const _ZoomControl(),
            ],
          ),
        ],
      ),
    );
  }
}

class _MoveTargetPicker extends ConsumerWidget {
  const _MoveTargetPicker({required this.folder, required this.target});

  final String folder;
  final String target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(libraryFoldersControllerProvider).value ?? const [];
    return PopupMenuButton<String>(
      tooltip: 'Where "Apply" sends the selection',
      initialValue: target,
      onSelected: (value) => ref.read(moveTargetsControllerProvider.notifier).setTarget(folder, value),
      itemBuilder: (context) => [
        for (final f in folders)
          PopupMenuItem(
            value: f.name,
            child: Text(f.name == folder ? '${f.name} (no move — just keep the selection)' : '→ ${f.name}'),
          ),
      ],
      child: StatusChip(kind: StatusKind.neutral, label: target == folder ? 'keep selection' : '→ $target', dense: true),
    );
  }
}

class _ZoomControl extends ConsumerWidget {
  const _ZoomControl();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zoom = ref.watch(libraryZoomProvider);
    return SegmentedButton<LibraryZoom>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(value: LibraryZoom.small, icon: AppIcon(AppIcons.densitySmall, size: IconSize.sm), tooltip: 'Small'),
        ButtonSegment(value: LibraryZoom.medium, icon: AppIcon(AppIcons.densityMedium, size: IconSize.sm), tooltip: 'Medium'),
        ButtonSegment(value: LibraryZoom.large, icon: AppIcon(AppIcons.densityLarge, size: IconSize.sm), tooltip: 'Large'),
      ],
      selected: {zoom},
      onSelectionChanged: (selected) => ref.read(libraryZoomProvider.notifier).set(selected.first),
    );
  }
}
