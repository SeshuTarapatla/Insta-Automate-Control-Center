import 'package:flutter/material.dart';

import '../../../core/agent_image.dart';
import '../../../core/flow_event_models.dart';
import 'surface_common.dart';

/// entity-scan: a live-growing filmstrip of the followers/following (or
/// likers) rows as they're scanned, wide (5.5:1) row crops — matches
/// ARCHITECTURE §5.1's shape for `scanned/<root>/<user>.jpg`.
class ScanSurface extends StatefulWidget {
  const ScanSurface({super.key, required this.events});

  final List<FlowEvent> events;

  @override
  State<ScanSurface> createState() => _ScanSurfaceState();
}

class _ScanSurfaceState extends State<ScanSurface> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final started = widget.events.where((e) => e.kind == 'scan.started').lastOrNull;
    final items = widget.events.where((e) => e.kind == 'scan.item').toList();
    final completed = widget.events.where((e) => e.kind == 'scan.completed').lastOrNull;

    if (started == null && items.isEmpty && completed == null) {
      return const SurfaceEmpty(message: 'No scan activity yet for this run.');
    }

    final counters = (completed ?? items.lastOrNull)?.counters;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (started != null)
            Row(
              children: [
                SizedBox(
                  width: 90,
                  child: AgentImage(imageKey: started.imageKey, width: 200, aspectRatio: 1080 / 2246),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Scanning ${started.entity ?? '?'}', style: theme.textTheme.titleMedium),
                      if (started.extra['list'] != null)
                        Text(
                          'list: ${started.extra['list']} '
                          '(f1=${started.extra['f1']}, f2=${started.extra['f2']})',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      if (counters != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'added ${counters['added']} / scanned ${counters['scanned']}',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          Expanded(
            child: items.isEmpty
                ? const SurfaceEmpty(message: 'No rows scanned yet.')
                // Vertical, one full-width item per row, newest at the top -
                // NOT `reverse: true` (that's the chat-message pattern:
                // newest at the *bottom*, index 0 anchored there). Here the
                // newest item is simply rendered first in normal top-down
                // order, so it's always visible without any scrolling at
                // all; older items sink down and off-screen as new ones
                // arrive above them.
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = items[items.length - 1 - index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Full pane width, not a fixed thumbnail - the
                          // 1080:198 row crop was cramped and hard to read
                          // at 180px wide next to its caption.
                          AgentImage(imageKey: item.imageKey, width: 400, aspectRatio: 1080 / 198),
                          const SizedBox(height: 4),
                          Text(
                            '@${item.subject ?? '?'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

extension _LastOrNull<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
