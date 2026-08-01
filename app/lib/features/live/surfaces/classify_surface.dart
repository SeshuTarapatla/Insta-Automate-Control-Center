import 'package:flutter/material.dart';

import '../../../core/agent_image.dart';
import '../../../core/flow_event_models.dart';
import 'surface_common.dart';

/// entity-classify: a verdict card stream (`classify.access`/`classify.gender`)
/// with a running img/s rate — the row-crop aspect ratio matches
/// ARCHITECTURE §5.1's `scanned/<root>/<user>.jpg` shape.
class ClassifySurface extends StatelessWidget {
  const ClassifySurface({super.key, required this.events});

  final List<FlowEvent> events;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verdicts = events.where((e) => e.kind == 'classify.access' || e.kind == 'classify.gender').toList();
    if (verdicts.isEmpty) {
      return const SurfaceEmpty(message: 'No verdicts yet for this run.');
    }

    final rate = _rate(verdicts);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text('${verdicts.length} classified', style: theme.textTheme.titleMedium),
              const SizedBox(width: 10),
              if (rate != null)
                Chip(label: Text('${rate.toStringAsFixed(1)} img/s'), visualDensity: VisualDensity.compact),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            reverse: true,
            itemCount: verdicts.length,
            itemBuilder: (context, index) {
              // reverse: true walks newest-first while keeping list order intact.
              final event = verdicts[verdicts.length - 1 - index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 100,
                          child: AgentImage(imageKey: event.imageKey, width: 200, aspectRatio: 1080 / 198),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '@${event.subject ?? '?'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        OutcomeBadge(label: event.verdict ?? '?', tone: toneFor(event.verdict)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  double? _rate(List<FlowEvent> verdicts) {
    if (verdicts.length < 2) return null;
    final first = verdicts.first.ts;
    final last = verdicts.last.ts;
    if (first is! num || last is! num) return null;
    final seconds = last - first;
    if (seconds <= 0) return null;
    return verdicts.length / seconds;
  }
}
