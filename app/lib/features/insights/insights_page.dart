import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/feedback.dart';
import '../../core/insights_models.dart';
import '../library/entity_yield_dialog.dart';
import 'burndown_chart.dart';
import 'funnel_chart.dart';
import 'insights_controller.dart';

/// Phase 7, CP 7.2 — the whole-library views the per-entity funnel (CP 5.4)
/// and the Flows screen's own "today" counters never showed on their own:
/// where the library stands in aggregate, which entities are actually
/// yielding, and whether the daily caps are being hit. Classify-accuracy
/// sampling was scoped out of this checkpoint (no persisted verdict history
/// exists to sample from — see DECISIONS.md).
class InsightsPage extends StatelessWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: 'Funnel'),
                Tab(text: 'Ranking'),
                Tab(text: 'Daily limits'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [FunnelTab(), RankingTab(), BurndownTab()],
            ),
          ),
        ],
      ),
    );
  }
}

class FunnelTab extends ConsumerWidget {
  const FunnelTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(funnelSummaryProvider);

    return async.stateView(
      describeError: describeInsightsError,
      onRetry: () => ref.invalidate(funnelSummaryProvider),
      data: (summary) {
        final stages = [
          FunnelStageData(label: 'Scanned', count: summary.scanned),
          FunnelStageData(label: 'Private', count: summary.private),
          FunnelStageData(
            label: 'Female',
            count: summary.female,
            caption: summary.male > 0
                ? 'of ${summary.private} private — ${summary.male} classified male instead'
                : null,
          ),
          FunnelStageData(
            label: 'Scraped',
            count: summary.scraped,
            caption: 'real all-time total — Insta-Automate\'s own daily scrape counters, summed',
          ),
          FunnelStageData(
            label: 'Followed',
            count: summary.followed,
            caption: 'real all-time total — Insta-Automate\'s own daily follow counters, summed',
          ),
        ];

        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Whole library', style: theme.textTheme.titleMedium),
                      const SizedBox(width: 10),
                      Chip(
                        label: Text('${summary.entities} entities'),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Every entity with any scan or scrape activity. Each stage shows its share of the '
                    'whole library and, more usefully, its real conversion from the stage right before it.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  FunnelChart(stages: stages),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

enum _SortColumn { root, scanned, private, female }

// Fixed widths for every column except Entity, which is the one column with
// genuinely variable-length content — it gets the window's leftover space
// instead (D77). Material's stock `DataTable` can't do this: stretching it
// to a wider incoming constraint spreads the extra space evenly across
// *every* column (a `FlexColumnWidth` per column internally), which is the
// "huge gaps everywhere" look this replaced, not "the identifier column
// grows, the metric columns stay put" a real file browser gives you.
const _typeWidth = 90.0;
const _accessWidth = 90.0;
// Wide enough for the longest header label ("Scanned") plus its sort arrow
// once active, not just the numbers themselves — a real overflow caught by
// `insights_layout_test.dart`'s huge-counts case, not by inspection.
const _metricWidth = 120.0;

class RankingTab extends ConsumerStatefulWidget {
  const RankingTab({super.key});

  @override
  ConsumerState<RankingTab> createState() => RankingTabState();
}

class RankingTabState extends ConsumerState<RankingTab> {
  String _query = '';
  _SortColumn _sortColumn = _SortColumn.scanned;
  bool _sortAscending = false;

  int _value(EntityRanking row, _SortColumn column) => switch (column) {
    _SortColumn.root => 0,
    _SortColumn.scanned => row.scanned,
    _SortColumn.private => row.private,
    _SortColumn.female => row.female,
  };

  void _sortBy(_SortColumn column) => setState(() {
    if (_sortColumn == column) {
      _sortAscending = !_sortAscending;
    } else {
      _sortColumn = column;
      _sortAscending = false;
    }
  });

  Widget _headerRow(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outlineVariant))),
      child: Row(
        children: [
          Expanded(
            child: _HeaderCell(
              label: 'Entity',
              active: _sortColumn == _SortColumn.root,
              ascending: _sortAscending,
              onTap: () => _sortBy(_SortColumn.root),
            ),
          ),
          SizedBox(width: _typeWidth, child: Text('Type', style: theme.textTheme.titleSmall)),
          SizedBox(width: _accessWidth, child: Text('Access', style: theme.textTheme.titleSmall)),
          SizedBox(
            width: _metricWidth,
            child: _HeaderCell(
              label: 'Scanned',
              alignEnd: true,
              active: _sortColumn == _SortColumn.scanned,
              ascending: _sortAscending,
              onTap: () => _sortBy(_SortColumn.scanned),
            ),
          ),
          SizedBox(
            width: _metricWidth,
            child: _HeaderCell(
              label: 'Private',
              alignEnd: true,
              active: _sortColumn == _SortColumn.private,
              ascending: _sortAscending,
              onTap: () => _sortBy(_SortColumn.private),
            ),
          ),
          SizedBox(
            width: _metricWidth,
            child: _HeaderCell(
              label: 'Female',
              alignEnd: true,
              active: _sortColumn == _SortColumn.female,
              ascending: _sortAscending,
              onTap: () => _sortBy(_SortColumn.female),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataRow(BuildContext context, ThemeData theme, EntityRanking row) {
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: () => showEntityYieldDialog(context, row.root),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
        ),
        child: Row(
          children: [
            Expanded(child: Text(row.root, overflow: TextOverflow.ellipsis, maxLines: 1)),
            SizedBox(width: _typeWidth, child: Text(row.type, style: theme.textTheme.bodyMedium)),
            SizedBox(width: _accessWidth, child: Text(row.access, style: theme.textTheme.bodyMedium)),
            SizedBox(width: _metricWidth, child: Text('${row.scanned}', textAlign: TextAlign.right)),
            SizedBox(width: _metricWidth, child: Text('${row.private}', textAlign: TextAlign.right)),
            SizedBox(width: _metricWidth, child: Text('${row.female}', textAlign: TextAlign.right)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(entityRankingProvider);

    return async.stateView(
      describeError: describeInsightsError,
      onRetry: () => ref.invalidate(entityRankingProvider),
      data: (rows) {
        final filtered = _query.isEmpty
            ? rows
            : rows.where((r) => r.root.toLowerCase().contains(_query.toLowerCase())).toList();
        final sorted = [...filtered]
          ..sort((a, b) {
            final cmp = _sortColumn == _SortColumn.root
                ? a.root.compareTo(b.root)
                : _value(a, _sortColumn).compareTo(_value(b, _sortColumn));
            return _sortAscending ? cmp : -cmp;
          });

        if (rows.isEmpty) {
          return const EmptyView(
            icon: Icons.insights_outlined,
            title: 'No entity has any scan or scrape activity yet.',
          );
        }

        final searchRow = Row(
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Filter by root…',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${sorted.length} of ${rows.length}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        );

        final tableCard = Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _headerRow(theme),
              for (final row in sorted) _dataRow(context, theme, row),
            ],
          ),
        );

        // One scrollable for the whole tab (search row + table), same as
        // before — the table itself no longer needs its own horizontal
        // scroller since every column now genuinely fits any width the
        // window can produce (D77): Entity absorbs whatever space is left
        // over, the rest stay fixed.
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          children: [searchRow, const SizedBox(height: 12), tableCard],
        );
      },
    );
  }
}

/// A sortable column header: the label plus a direction arrow once it's the
/// active sort column — Material's own `DataColumn` sort-arrow convention,
/// reused here since the rest of this table is now hand-built.
class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.label, this.alignEnd = false, required this.active, required this.ascending, required this.onTap});

  final String label;
  final bool alignEnd;
  final bool active;
  final bool ascending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisAlignment: alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.titleSmall),
          if (active) ...[
            const SizedBox(width: 2),
            Icon(ascending ? Icons.arrow_upward : Icons.arrow_downward, size: 14),
          ],
        ],
      ),
    );
  }
}

const _dayOptions = [7, 14, 30, 90];

class BurndownTab extends ConsumerWidget {
  const BurndownTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selectedDays = ref.watch(burndownDaysProvider);
    final async = ref.watch(burndownProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Last', style: theme.textTheme.bodyMedium),
            for (final option in _dayOptions)
              ChoiceChip(
                label: Text('${option}d'),
                selected: selectedDays == option,
                onSelected: (_) => ref.read(burndownDaysProvider.notifier).select(option),
              ),
          ],
        ),
        const SizedBox(height: 16),
        async.stateView(
          describeError: describeInsightsError,
          onRetry: () => ref.invalidate(burndownProvider),
          data: (burndown) => Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _burndownCard(context, 'Scan — profiles', burndown.scan, 'profiles', burndown.limits['profiles']),
              _burndownCard(context, 'Scan — reels', burndown.scan, 'reels', burndown.limits['reels']),
              _burndownCard(context, 'Scan — posts', burndown.scan, 'posts', burndown.limits['posts']),
              _burndownCard(context, 'Scrape', burndown.scrape, 'scraped', burndown.limits['scrape']),
              _burndownCard(context, 'Follow', burndown.follow, 'followed', burndown.limits['follow']),
            ],
          ),
        ),
      ],
    );
  }

  Widget _burndownCard(BuildContext context, String title, List<BurndownDay> days, String field, int? cap) {
    return SizedBox(
      width: 420,
      child: BurndownCard(title: title, days: days, values: field, cap: cap),
    );
  }
}
