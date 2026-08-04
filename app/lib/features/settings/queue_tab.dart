import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_snack_bar.dart';
import '../../core/queue_models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/feedback.dart';
import '../../ui/icons.dart';
import '../../ui/status.dart';
import '../../ui/surfaces.dart';
import '../../ui/text.dart';
import 'config_controller.dart';
import 'queue_controller.dart';

class QueueTab extends ConsumerWidget {
  const QueueTab({super.key});

  Future<void> _save(BuildContext context, WidgetRef ref, List<String> names) async {
    try {
      await ref.read(configControllerProvider.notifier).applyQueue(names);
    } on DioException {
      if (context.mounted) {
        AppSnackBar.show(context, 'Could not update the queue', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(queueProvider);

    return queueAsync.stateView(
      describeError: (error) => 'Failed to load queue: $error',
      onRetry: () => ref.invalidate(queueProvider),
      data: (data) => _QueueBody(
        data: data,
        onReorder: (names) => _save(context, ref, names),
      ),
    );
  }
}

class _QueueBody extends StatelessWidget {
  const _QueueBody({required this.data, required this.onReorder});

  final QueueData data;
  final ValueChanged<List<String>> onReorder;

  void _handleReorder(int oldIndex, int newIndex) {
    final names = data.queued.map((e) => e.name).toList();
    if (newIndex > oldIndex) newIndex -= 1;
    names.insert(newIndex, names.removeAt(oldIndex));
    onReorder(names);
  }

  void _remove(String name) =>
      onReorder(data.queued.map((e) => e.name).where((n) => n != name).toList());

  void _add(String name) => onReorder([...data.queued.map((e) => e.name), name]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return ListView(
      padding: EdgeInsets.all(tokens.space.lg),
      children: [
        Text('Priority order', style: theme.textTheme.titleLarge),
        SizedBox(height: tokens.space.xs),
        Text(
          'One list, used by both scrape and follow — each stage applies this order to its own '
          'folder. Anything not listed still runs, after these, oldest first.',
          style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
        ),
        SizedBox(height: tokens.space.lg),

        if (data.queued.isEmpty)
          AppCard(
            child: Row(
              children: [
                AppIcon(AppIcons.sort, color: tokens.content.secondary),
                SizedBox(width: tokens.space.md),
                Expanded(
                  child: Text(
                    'No priority set. All ${data.unqueued.length} entities run in date order, '
                    'oldest first.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          )
        else
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: _handleReorder,
            children: [
              for (final (index, entry) in data.queued.indexed)
                _QueueTile(
                  key: ValueKey(entry.name),
                  entry: entry,
                  position: index + 1,
                  dragIndex: index,
                  onRemove: () => _remove(entry.name),
                ),
            ],
          ),

        SizedBox(height: tokens.space.xxl),
        Text('Not prioritised (${data.unqueued.length})', style: theme.textTheme.titleMedium),
        SizedBox(height: tokens.space.xs),
        Text(
          'Runs after the list above, oldest first.',
          style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
        ),
        SizedBox(height: tokens.space.md),
        for (final entry in data.unqueued)
          _QueueTile(entry: entry, onAdd: () => _add(entry.name)),
      ],
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({
    super.key,
    required this.entry,
    this.position,
    this.dragIndex,
    this.onRemove,
    this.onAdd,
  });

  final QueueEntry entry;
  final int? position;
  final int? dragIndex;
  final VoidCallback? onRemove;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return Padding(
      padding: EdgeInsets.only(bottom: tokens.space.sm),
      child: AppCard(
        padding: EdgeInsets.symmetric(horizontal: tokens.space.md, vertical: tokens.space.sm),
        child: Row(
          children: [
            if (dragIndex case final index?)
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: EdgeInsets.only(right: tokens.space.sm),
                  child: AppIcon(AppIcons.dragHandle, color: tokens.content.secondary),
                ),
              ),
            if (position case final p?) ...[
              SizedBox(width: 28, child: NumericText(p, role: TextRole.cardTitle)),
              SizedBox(width: tokens.space.xs),
            ],
            Expanded(
              child: Row(
                children: [
                  Flexible(child: MonoText(entry.name, role: TextRole.bodyStrong)),
                  if (!entry.hasEntityImage) ...[
                    SizedBox(width: tokens.space.sm),
                    Tooltip(
                      message: 'No entities/${entry.name}.jpg — the pipeline would reject this',
                      child: AppIcon(AppIcons.warning, size: IconSize.sm, color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
            _CountChip(label: 'scrape', count: entry.scrapeCount),
            SizedBox(width: tokens.space.xs),
            _CountChip(label: 'follow', count: entry.followCount),
            SizedBox(width: tokens.space.sm),
            if (onRemove != null)
              IconButton(
                icon: AppIcon(AppIcons.remove, size: IconSize.md),
                tooltip: 'Remove from priority list',
                onPressed: onRemove,
              ),
            if (onAdd != null)
              IconButton(
                icon: AppIcon(AppIcons.arrowUp, size: IconSize.md),
                tooltip: 'Add to priority list',
                onPressed: onAdd,
              ),
          ],
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final muted = count == 0;
    return StatusChip(kind: muted ? StatusKind.neutral : StatusKind.info, label: '$label $count', dense: true);
  }
}
