import 'package:flutter/material.dart';

import '../../../core/agent_image.dart';
import '../../../core/flow_event_models.dart';
import 'surface_common.dart';

/// entity-follow: the profile report card with its outcome — FOLLOWED,
/// REQUESTED, FOLLOWING, FOLLOWED_BY, WANTS_TO_FOLLOW or FAILED.
class FollowSurface extends StatelessWidget {
  const FollowSurface({super.key, required this.events});

  final List<FlowEvent> events;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = events.where((e) => e.kind == 'follow.attempt' || e.kind == 'follow.result').toList();
    if (items.isEmpty) {
      return const SurfaceEmpty(message: 'No follow activity yet for this run.');
    }

    final bySubject = <String, List<FlowEvent>>{};
    for (final event in items) {
      bySubject.putIfAbsent(event.subject ?? event.id, () => []).add(event);
    }
    final subjects = bySubject.keys.toList();

    // Wrapped left-to-right at a capped width per card rather than one
    // full-bleed row each — same reasoning as `scrape_surface.dart`'s
    // `_HistoryWrap` (D43's follow-up): a single-column list of `Row`-shaped
    // cards left most of the pane's width empty once the visualization
    // surface got more room. Slightly wider than scrape's own cards since
    // the outcome badge here (e.g. `WANTS_TO_FOLLOW`) needs more room.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final subject in subjects.reversed)
            SizedBox(width: 420, child: _FollowCard(events: bySubject[subject]!, theme: theme)),
        ],
      ),
    );
  }
}

class _FollowCard extends StatelessWidget {
  const _FollowCard({required this.events, required this.theme});

  final List<FlowEvent> events;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final result = events.where((e) => e.kind == 'follow.result').isNotEmpty
        ? events.firstWhere((e) => e.kind == 'follow.result')
        : null;
    final attempt = events.where((e) => e.kind == 'follow.attempt').isNotEmpty
        ? events.firstWhere((e) => e.kind == 'follow.attempt')
        : null;
    final subject = (result ?? attempt)?.subject ?? '?';
    final root = rootFromImage((result ?? attempt)?.image);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              // follow_queued/<root>/<user>.jpg is the same scraped composite
              // entity-scrape produces (1080×~2000, not the 1080×2246 entity
              // page) — profile_follow's own `img` parameter is that file.
              child: AgentImage(imageKey: (result ?? attempt)?.imageKey, width: 180, aspectRatio: 1080 / 2000),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('@$subject', style: theme.textTheme.bodyMedium),
                  if (root != null)
                    Text(
                      'root: $root',
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  if (result != null && result.reason != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        result.reason!,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
            OutcomeBadge(label: result?.verdict ?? 'attempting…', tone: toneFor(result?.verdict)),
          ],
        ),
      ),
    );
  }
}
