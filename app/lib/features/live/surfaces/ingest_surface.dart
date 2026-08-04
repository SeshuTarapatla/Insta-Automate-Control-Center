import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/flow_event_models.dart';
import '../../../core/theme/tokens.dart';
import '../../../ui/icons.dart';
import '../../../ui/status.dart';
import '../../../ui/surfaces.dart';
import 'surface_common.dart';

/// entity-ingest: a metadata card per entity added this run. Ingest never
/// produces an image of its own — `entities/<id>.jpg` (the full profile
/// page screenshot the event's `image` field names) isn't written until a
/// *later* flow (`entity_scan`'s `scan_entity_init`) opens the entity, so at
/// ingest time it never exists yet. An earlier version tried to show it
/// anyway and always rendered a broken-looking placeholder; this shows what
/// ingest actually has — the entity's type/access/URL — instead.
class IngestSurface extends StatelessWidget {
  const IngestSurface({super.key, required this.events});

  final List<FlowEvent> events;

  @override
  Widget build(BuildContext context) {
    final added = events.where((e) => e.kind == 'entity.added').toList();
    if (added.isEmpty) {
      return const SurfaceEmpty(message: 'No entities added yet this run.');
    }

    return ListView.separated(
      padding: EdgeInsets.all(Theme.of(context).tokens.space.md),
      itemCount: added.length,
      separatorBuilder: (_, _) => SizedBox(height: Theme.of(context).tokens.space.sm),
      itemBuilder: (context, index) {
        // Newest first, no scrolling needed to see the latest.
        final event = added[added.length - 1 - index];
        return _EntityCard(event: event);
      },
    );
  }
}

PhosphorIconData Function(PhosphorIconsStyle) _iconForType(String? type) => switch (type?.toLowerCase()) {
  'reel' => AppIcons.movie,
  'post' => AppIcons.grid,
  'profile' => AppIcons.person,
  _ => AppIcons.help,
};

class _EntityCard extends StatelessWidget {
  const _EntityCard({required this.event});

  final FlowEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = event.extra['type'] as String?;
    final access = event.extra['access'] as String?;
    final url = event.extra['url'] as String?;

    final tokens = theme.tokens;

    return ResultCardActions(
      subject: event.entity ?? event.subject,
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: AppIcon(_iconForType(type), color: tokens.content.secondary),
            ),
            SizedBox(width: tokens.space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '@${event.entity ?? event.subject ?? '?'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (url != null)
                    Padding(
                      padding: EdgeInsets.only(top: tokens.space.xs / 2),
                      child: Text(
                        url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
                      ),
                    ),
                  if (type != null || access != null)
                    Padding(
                      padding: EdgeInsets.only(top: tokens.space.xs),
                      child: Wrap(
                        spacing: tokens.space.xs,
                        children: [
                          if (type != null) OutcomeBadge(label: type.toUpperCase(), kind: StatusKind.neutral),
                          if (access != null)
                            OutcomeBadge(label: access.toUpperCase(), kind: toneFor(access.toUpperCase())),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
