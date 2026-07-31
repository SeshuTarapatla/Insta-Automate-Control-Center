import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_snack_bar.dart';
import '../../core/queue_models.dart';
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

    return queueAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Failed to load queue: $error')),
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

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Priority order', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'One list, used by both scrape and follow — each stage applies this order to its own '
          'folder. Anything not listed still runs, after these, oldest first.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),

        if (data.queued.isEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.low_priority, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No priority set. All ${data.unqueued.length} entities run in date order, '
                      'oldest first.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
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

        const SizedBox(height: 32),
        Text('Not prioritised (${data.unqueued.length})', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Runs after the list above, oldest first.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (dragIndex case final index?)
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.drag_indicator, color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            if (position case final p?) ...[
              SizedBox(
                width: 28,
                child: Text('$p', style: theme.textTheme.titleMedium),
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      entry.name,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(fontFamily: 'Consolas'),
                    ),
                  ),
                  if (!entry.hasEntityImage) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'No entities/${entry.name}.jpg — the pipeline would reject this',
                      child: Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _CountChip(label: 'scrape', count: entry.scrapeCount),
            const SizedBox(width: 6),
            _CountChip(label: 'follow', count: entry.followCount),
            const SizedBox(width: 8),
            if (onRemove != null)
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: 'Remove from priority list',
                onPressed: onRemove,
              ),
            if (onAdd != null)
              IconButton(
                icon: const Icon(Icons.arrow_upward),
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
    final theme = Theme.of(context);
    final muted = count == 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: muted ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label $count',
        style: theme.textTheme.labelSmall?.copyWith(
          color: muted
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
