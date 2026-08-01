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

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: subjects.length,
      itemBuilder: (context, index) {
        final subject = subjects[subjects.length - 1 - index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _FollowCard(events: bySubject[subject]!, theme: theme),
        );
      },
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

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: AgentImage(imageKey: (result ?? attempt)?.imageKey, width: 180, aspectRatio: 1080 / 2246),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('@$subject', style: theme.textTheme.bodyMedium),
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
