import 'package:flutter/material.dart';

import '../../../core/agent_image.dart';
import '../../../core/flow_event_models.dart';
import '../../../ui/status.dart';
import 'surface_common.dart';

/// entity-scrape: the queued row strip resolves into either a reason chip
/// (skipped, with the real numbers ARCHITECTURE §5.1 calls for) or the full
/// profile-report composite (done) — most recent item large, history below.
class ScrapeSurface extends StatelessWidget {
  const ScrapeSurface({super.key, required this.events});

  final List<FlowEvent> events;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = events
        .where((e) => e.kind == 'scrape.started' || e.kind == 'scrape.skipped' || e.kind == 'scrape.done')
        .toList();
    if (items.isEmpty) {
      return const SurfaceEmpty(message: 'No scrape activity yet for this run.');
    }

    // Group by subject so a skip/done resolves the same subject's earlier
    // "started" row rather than appearing as an unrelated new item.
    final bySubject = <String, List<FlowEvent>>{};
    for (final event in items) {
      bySubject.putIfAbsent(event.subject ?? event.id, () => []).add(event);
    }
    final subjects = bySubject.keys.toList();
    final latestEvents = bySubject[subjects.last]!;
    // Large treatment is only for a subject still being worked on — the
    // instant it resolves (done/skipped) it belongs in history like every
    // other finished card, not pinned above it just for being most recent.
    final latestInProgress = !latestEvents.any((e) => e.kind == 'scrape.done' || e.kind == 'scrape.skipped');

    if (!latestInProgress) {
      return _HistoryWrap(subjects: subjects.reversed, bySubject: bySubject, theme: theme);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: _ScrapeCard(events: latestEvents, theme: theme, large: true),
        ),
        const Divider(height: 1),
        Expanded(
          // Newest-first, skipping the subject already shown large above.
          child: _HistoryWrap(subjects: subjects.reversed.skip(1), bySubject: bySubject, theme: theme),
        ),
      ],
    );
  }
}

/// The resolved-card history, wrapped left-to-right at a capped width per
/// card rather than one full-bleed row each — a single-column `ListView` of
/// `Row`-shaped cards left most of a wide pane empty to the right of every
/// card's actual content once the visualization surface got the extra room
/// D43 gave it. `SizedBox`-capping each card and `Wrap`ping them fills that
/// space with more cards instead, without needing to redesign the card
/// itself away from the image-left/text-right shape that already works well
/// at a fixed width.
class _HistoryWrap extends StatelessWidget {
  const _HistoryWrap({required this.subjects, required this.bySubject, required this.theme});

  final Iterable<String> subjects;
  final Map<String, List<FlowEvent>> bySubject;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final subject in subjects)
            SizedBox(width: 380, child: _ScrapeCard(events: bySubject[subject]!, theme: theme, large: false)),
        ],
      ),
    );
  }
}

class _ScrapeCard extends StatelessWidget {
  const _ScrapeCard({required this.events, required this.theme, required this.large});

  final List<FlowEvent> events;
  final ThemeData theme;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final done = events.where((e) => e.kind == 'scrape.done').isNotEmpty ? events.firstWhere((e) => e.kind == 'scrape.done') : null;
    final skipped = events.where((e) => e.kind == 'scrape.skipped').isNotEmpty ? events.firstWhere((e) => e.kind == 'scrape.skipped') : null;
    final started = events.where((e) => e.kind == 'scrape.started').isNotEmpty ? events.firstWhere((e) => e.kind == 'scrape.started') : null;
    final subject = (done ?? skipped ?? started)?.subject ?? '?';
    final root = rootFromImage((done ?? skipped ?? started)?.image);
    final inProgress = done == null && skipped == null;

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('@$subject', style: large ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium),
        if (root != null)
          Text('root: $root', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        if (done != null) ...[
          OutcomeBadge(label: 'SCRAPED', kind: StatusKind.good),
          const SizedBox(height: 6),
          Text(
            'posts ${done.counters['posts']} · followers ${done.counters['followers']} · '
            'following ${done.counters['following']}',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ] else if (skipped != null) ...[
          OutcomeBadge(label: 'SKIPPED', kind: StatusKind.bad),
          const SizedBox(height: 6),
          Text(skipped.reason ?? '', style: theme.textTheme.bodySmall),
        ] else
          Text('scraping…', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );

    // Still in progress means the only image on hand is the queued row crop
    // (scrape_queued/<root>/<user>.jpg, 1080×198 — the same wide strip shape
    // scan/classify's row crops are, not the tall scraped composite) — laid
    // out as a strip on top rather than squeezed into the portrait-oriented
    // Row every resolved card uses, which assumes a tall image.
    if (large && inProgress) {
      return ResultCardActions(
        subject: (done ?? skipped ?? started)?.subject,
        root: root,
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AgentImage(imageKey: started?.imageKey, width: 600, aspectRatio: 1080 / 198),
                const SizedBox(height: 10),
                details,
              ],
            ),
          ),
        ),
      );
    }

    // Everything else is resolved: `done` has a real scraped composite
    // (portrait, ~1080×2000); `skipped` never gets one, so it still only
    // ever has the queued row crop — shown at its own real (wide) shape
    // rather than squeezed into the composite's, same reasoning as above.
    return ResultCardActions(
      subject: (done ?? skipped ?? started)?.subject,
      root: root,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: large ? 140.0 : 90.0,
                child: AgentImage(
                  imageKey: (done ?? skipped ?? started)?.imageKey,
                  width: large ? 200 : 100,
                  aspectRatio: done != null ? 1080 / 2000 : 1080 / 198,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: details),
            ],
          ),
        ),
      ),
    );
  }
}
