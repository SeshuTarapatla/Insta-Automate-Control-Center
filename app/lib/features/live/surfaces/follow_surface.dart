import 'package:flutter/material.dart';

import '../../../core/agent_image.dart';
import '../../../core/flow_event_models.dart';
import '../../../core/theme/tokens.dart';
import '../../../ui/status.dart';
import '../../../ui/surfaces.dart';
import 'surface_common.dart';

/// entity-follow: the profile report card with its outcome — FOLLOWED,
/// REQUESTED, FOLLOWING, FOLLOWED_BY, WANTS_TO_FOLLOW or FAILED.
class FollowSurface extends StatelessWidget {
  const FollowSurface({super.key, required this.events, this.selectedVerdicts = const {}});

  final List<FlowEvent> events;

  /// The active `run_summary.dart` counter-chip filter — empty shows every
  /// subject, otherwise only subjects whose resolved verdict is in the set.
  /// A subject still `attempting…` (no `follow.result` yet) has no resolved
  /// verdict to match, so it's hidden while a filter is active.
  final Set<String> selectedVerdicts;

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
    final subjects = bySubject.keys.where((subject) {
      if (selectedVerdicts.isEmpty) return true;
      final results = bySubject[subject]!.where((e) => e.kind == 'follow.result');
      return results.isNotEmpty && selectedVerdicts.contains(results.first.verdict);
    }).toList();
    if (subjects.isEmpty) {
      return const SurfaceEmpty(message: 'No follow activity matches the selected filter.');
    }

    // Wrapped left-to-right at a capped width per card rather than one
    // full-bleed row each — same reasoning as `scrape_surface.dart`'s
    // `_HistoryWrap` (D43's follow-up): a single-column list of `Row`-shaped
    // cards left most of the pane's width empty once the visualization
    // surface got more room. A higher minimum than scrape's own cards since
    // the outcome badge here (e.g. `WANTS_TO_FOLLOW`) needs more room.
    final tokens = theme.tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Computed rather than the old hardcoded 420 (D45, tuned to follow
        // alone) — SCREENS §3's "no ragged gutter at any window size."
        final width = wrapCardWidth(
          constraints.maxWidth - tokens.space.md * 2,
          minWidth: 360,
          maxWidth: 500,
          spacing: tokens.space.md,
        );
        return SingleChildScrollView(
          padding: EdgeInsets.all(tokens.space.md),
          child: Wrap(
            spacing: tokens.space.md,
            runSpacing: tokens.space.md,
            children: [
              for (final subject in subjects.reversed)
                SizedBox(width: width, child: _FollowCard(events: bySubject[subject]!, theme: theme)),
            ],
          ),
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
    final root = rootFromImage((result ?? attempt)?.image);

    final tokens = theme.tokens;

    return ResultCardActions(
      subject: (result ?? attempt)?.subject,
      root: root,
      child: AppCard(
        padding: EdgeInsets.all(tokens.space.sm),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              // follow_queued/<root>/<user>.jpg is the same scraped composite
              // entity-scrape produces (1080×~2000, not the 1080×2246 entity
              // page) — profile_follow's own `img` parameter is that file.
              child: AgentImage(imageKey: (result ?? attempt)?.imageKey, width: 180, aspectRatio: 1080 / 2000),
            ),
            SizedBox(width: tokens.space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('@$subject', style: theme.textTheme.bodyMedium),
                  if (root != null)
                    Text(
                      'root: $root',
                      style: theme.textTheme.labelSmall?.copyWith(color: tokens.content.secondary),
                    ),
                  if (result != null && result.reason != null)
                    Padding(
                      padding: EdgeInsets.only(top: tokens.space.xs),
                      child: Text(
                        result.reason!,
                        style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
                      ),
                    ),
                ],
              ),
            ),
            OutcomeBadge(label: result?.verdict ?? 'attempting…', kind: toneFor(result?.verdict)),
          ],
        ),
      ),
    );
  }
}
