// SCREENS.md §1 — "caps become bars + sparklines, not five 340px `fl_chart`
// cards." A cap is a ratio-to-a-limit; a progress bar says that in 24px of
// height where a bar chart takes 200. The 7-day `Sparkline` (COMPONENTS §10)
// keeps the trend signal; the full `fl_chart` history stays on Insights, one
// click away (`SectionHeader.navIndex`).
import 'package:flutter/material.dart';

import '../../core/insights_models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/data.dart';
import '../../ui/status.dart';
import '../../ui/text.dart';

class _CapRow {
  const _CapRow({required this.label, required this.field, required this.days, required this.limit});
  final String label;
  final String field;
  final List<BurndownDay> days;
  final int? limit;
}

class CapsTile extends StatelessWidget {
  const CapsTile({super.key, required this.burndown});

  final Burndown burndown;

  @override
  Widget build(BuildContext context) {
    final rows = [
      _CapRow(label: 'Scan · profiles', field: 'profiles', days: burndown.scan, limit: burndown.limits['profiles']),
      _CapRow(label: 'Scan · reels', field: 'reels', days: burndown.scan, limit: burndown.limits['reels']),
      _CapRow(label: 'Scan · posts', field: 'posts', days: burndown.scan, limit: burndown.limits['posts']),
      _CapRow(label: 'Scrape', field: 'scraped', days: burndown.scrape, limit: burndown.limits['scrape']),
      _CapRow(label: 'Follow', field: 'followed', days: burndown.follow, limit: burndown.limits['follow']),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [for (final row in rows) _CapBar(row: row)],
    );
  }
}

class _CapBar extends StatelessWidget {
  const _CapBar({required this.row});

  final _CapRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final today = row.days.isEmpty ? 0 : (row.days.last.values[row.field] ?? 0);
    final limit = row.limit;
    final series = row.days.length <= 7 ? row.days : row.days.sublist(row.days.length - 7);
    final values = [for (final day in series) day.values[row.field] ?? 0];
    final fraction = limit == null || limit <= 0 ? 0.0 : (today / limit).clamp(0.0, 1.0);
    final tone = fraction >= 1.0 ? StatusKind.warn : StatusKind.info;

    return Padding(
      padding: EdgeInsets.only(bottom: tokens.space.sm),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(row.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
          ),
          SizedBox(width: tokens.space.sm),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(tokens.geometry.radiusFull),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                color: tone.fg(tokens),
                backgroundColor: tokens.surface.sunken,
              ),
            ),
          ),
          SizedBox(width: tokens.space.sm),
          NumericText(limit == null ? '$today' : '$today/$limit', role: TextRole.caption),
          SizedBox(width: tokens.space.sm),
          Sparkline(values: values, cap: limit, tone: tone),
        ],
      ),
    );
  }
}
