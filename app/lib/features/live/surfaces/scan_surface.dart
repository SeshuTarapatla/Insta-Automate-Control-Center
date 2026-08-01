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
  final _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final started = widget.events.where((e) => e.kind == 'scan.started').lastOrNull;
    final items = widget.events.where((e) => e.kind == 'scan.item').toList();
    final completed = widget.events.where((e) => e.kind == 'scan.completed').lastOrNull;

    if (started == null && items.isEmpty && completed == null) {
      return const SurfaceEmpty(message: 'No scan activity yet for this run.');
    }

    if (items.length != _lastCount) {
      _lastCount = items.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });
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
                : ListView.separated(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return SizedBox(
                        width: 180,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AgentImage(imageKey: item.imageKey, width: 180, aspectRatio: 1080 / 198),
                            const SizedBox(height: 4),
                            Text(
                              '@${item.subject ?? '?'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall,
                            ),
                          ],
                        ),
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
