import 'package:flutter/material.dart';

import '../../../core/agent_image.dart';
import '../../../core/flow_event_models.dart';
import 'surface_common.dart';

/// entity-ingest: hero page cards for every entity added this run — the full
/// profile page (`entities/<id>.jpg`, 1080×2246), with its type/access badges.
class IngestSurface extends StatelessWidget {
  const IngestSurface({super.key, required this.events});

  final List<FlowEvent> events;

  @override
  Widget build(BuildContext context) {
    final added = events.where((e) => e.kind == 'entity.added').toList();
    if (added.isEmpty) {
      return const SurfaceEmpty(message: 'No entities added yet this run.');
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1080 / 2246 * 1.35, // room for the caption below the image
      ),
      itemCount: added.length,
      itemBuilder: (context, index) {
        // Newest first.
        final event = added[added.length - 1 - index];
        return _HeroCard(event: event);
      },
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.event});

  final FlowEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: AgentImage(imageKey: event.imageKey, width: 320, aspectRatio: 1080 / 2246)),
        const SizedBox(height: 6),
        Text(
          '@${event.entity ?? event.subject ?? '?'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium,
        ),
        if (event.extra['type'] != null || event.extra['access'] != null)
          Wrap(
            spacing: 4,
            children: [
              if (event.extra['type'] != null)
                Text(
                  '${event.extra['type']}'.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              if (event.extra['access'] != null)
                Text(
                  '${event.extra['access']}'.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
            ],
          ),
      ],
    );
  }
}
