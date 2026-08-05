import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/insights_models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/surfaces.dart';

/// One flow's daily count against its current cap (PLAN CP 7.2). Sequential
/// job — "compare magnitude, day to day" — so one hue throughout, same as
/// `FunnelStage`'s bars; there is only one series here, so no legend box and
/// no categorical palette to validate (dataviz skill: single-series bar ==
/// sequential, color-formula's categorical checks don't apply). The cap is a
/// dashed threshold line, deliberately distinct from the solid hairline
/// gridlines, with one direct label — the only text this chart places beside
/// a mark rather than on the axis.
class BurndownCard extends StatelessWidget {
  const BurndownCard({super.key, required this.title, required this.days, required this.values, required this.cap});

  final String title;
  final List<BurndownDay> days;
  final String values;
  final int? cap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = theme.tokens;
    final counts = [for (final day in days) day.values[values] ?? 0];
    final maxCount = counts.isEmpty ? 0 : counts.reduce((a, b) => a > b ? a : b);
    // The chart's ceiling must clear both the tallest real bar and the cap
    // line, or a day that blew past the cap (or a cap higher than any day
    // reached) would clip.
    final ceiling = [maxCount, cap ?? 0, 1].reduce((a, b) => a > b ? a : b).toDouble();
    final interval = _niceInterval(ceiling);

    return AppPanel(
      level: SurfaceLevel.raised,
      borderRadius: tokens.geometry.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              if (cap != null)
                Text('cap $cap/day', style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary)),
            ],
          ),
          SizedBox(height: tokens.space.md),
          SizedBox(
            height: 160,
            child: days.isEmpty
                ? Center(
                    child: Text('No history yet', style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary)),
                  )
                : BarChart(
                    BarChartData(
                      maxY: ceiling * 1.15,
                      alignment: BarChartAlignment.spaceAround,
                      gridData: FlGridData(
                        drawVerticalLine: false,
                        horizontalInterval: interval,
                        getDrawingHorizontalLine: (_) => FlLine(color: tokens.chart.grid, strokeWidth: 1),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: interval,
                            reservedSize: 32,
                            getTitlesWidget: (value, meta) => Text(
                              value.round().toString(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: tokens.chart.axisLabel,
                                fontFamily: tokens.typography.mono,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 24,
                            getTitlesWidget: (value, meta) {
                              final index = value.round();
                              if (index < 0 || index >= days.length) return const SizedBox.shrink();
                              // Every day would crowd past ~10 columns — show only
                              // the ends and every few days between, never a
                              // number too wide for its slot (marks-and-anatomy's
                              // "measure first" rule).
                              final showEvery = (days.length / 6).ceil().clamp(1, days.length);
                              if (index != 0 && index != days.length - 1 && index % showEvery != 0) {
                                return const SizedBox.shrink();
                              }
                              final label = days[index].date.substring(5); // MM-DD
                              return Padding(
                                padding: EdgeInsets.only(top: tokens.space.xs),
                                child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: tokens.chart.axisLabel)),
                              );
                            },
                          ),
                        ),
                      ),
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (_) => scheme.inverseSurface,
                          getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                            '${days[group.x.toInt()].date}\n',
                            TextStyle(color: scheme.onInverseSurface, fontWeight: FontWeight.w600),
                            children: [
                              TextSpan(
                                text: rod.toY.round().toString(),
                                style: TextStyle(color: scheme.onInverseSurface, fontWeight: FontWeight.w400, fontFamily: tokens.typography.mono),
                              ),
                            ],
                          ),
                        ),
                      ),
                      extraLinesData: cap == null
                          ? const ExtraLinesData()
                          : ExtraLinesData(
                              horizontalLines: [
                                HorizontalLine(
                                  y: cap!.toDouble(),
                                  color: tokens.chart.capLine,
                                  strokeWidth: 1.5,
                                  dashArray: [6, 4],
                                  label: HorizontalLineLabel(
                                    show: true,
                                    alignment: Alignment.topRight,
                                    style: theme.textTheme.bodySmall?.copyWith(color: tokens.chart.capLine, fontWeight: FontWeight.w600),
                                    labelResolver: (_) => 'cap',
                                  ),
                                ),
                              ],
                            ),
                      barGroups: [
                        for (var i = 0; i < counts.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: counts[i].toDouble(),
                                color: tokens.chart.positiveFill,
                                width: 18,
                                borderRadius: BorderRadius.vertical(top: Radius.circular(tokens.geometry.radiusSm)),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A round-number gridline step (marks-and-anatomy's "round to clean
/// numbers") that never produces more than ~6 lines even for a small ceiling
/// like `PROFILES=10`.
double _niceInterval(double ceiling) {
  if (ceiling <= 5) return 1;
  if (ceiling <= 10) return 2;
  if (ceiling <= 25) return 5;
  if (ceiling <= 50) return 10;
  if (ceiling <= 100) return 20;
  if (ceiling <= 250) return 50;
  if (ceiling <= 500) return 100;
  return (ceiling / 5).ceilToDouble();
}
