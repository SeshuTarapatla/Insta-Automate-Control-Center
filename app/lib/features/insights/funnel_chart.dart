import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../ui/text.dart';

/// One stage of a sequential funnel — `count` is the real number at that
/// stage, `caption` is optional extra context shown under the conversion
/// line (e.g. the male-classified-instead note, or "real all-time total").
class FunnelStageData {
  const FunnelStageData({required this.label, required this.count, this.caption});

  final String label;
  final int count;
  final String? caption;
}

/// A real narrowing funnel (PLAN CP 7.2, corrected from a flat bar-per-stage
/// layout): each stage is a trapezoid whose *top* edge matches the previous
/// stage's width and whose *bottom* edge matches its own, so the shape reads
/// as one continuous silhouette narrowing stage by stage — not five
/// identically-scaled bars that all read "% of the very first stage" and
/// therefore stop moving once a stage is already small.
///
/// Every stage is labeled with **both** conversion numbers, since either one
/// alone hides something real: "% of total" answers "how much of the
/// original pool made it this far" but flattens out for a stage several
/// filters deep (2% of scanned looks the same whether Followed dropped hard
/// this stage or was always thin); "% of previous" answers "how much of
/// *this* filter's input survived it" but says nothing about overall scale.
/// Showing both is the actual fix for what a single normalized bar can't
/// say — not a fancier bar, a different question answered per stage.
class FunnelChart extends StatelessWidget {
  const FunnelChart({super.key, required this.stages});

  final List<FunnelStageData> stages;

  // Tall enough for three lines (name+count, conversion, an optional
  // caption) plus the label's own vertical padding — measured against the
  // real font metrics, not guessed, since a caption-bearing stage is the
  // tallest content this label ever holds.
  static const _segmentHeight = 84.0;
  static const _labelWidth = 300.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (stages.isEmpty) return const SizedBox.shrink();

    final maxCount = stages.first.count == 0 ? 1 : stages.first.count;
    final fractions = [for (final stage in stages) (stage.count / maxCount).clamp(0.0, 1.0)];

    return SizedBox(
      height: _segmentHeight * stages.length,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: CustomPaint(
              painter: _FunnelPainter(fractions: fractions, color: scheme.primary, boundaryColor: scheme.surface),
            ),
          ),
          SizedBox(width: theme.tokens.space.xl),
          SizedBox(
            width: _labelWidth,
            child: Column(
              children: [
                for (var i = 0; i < stages.length; i++)
                  SizedBox(
                    height: _segmentHeight,
                    child: _FunnelLabel(
                      stage: stages[i],
                      pctOfTotal: stages[i].count / maxCount * 100,
                      pctOfPrevious: i == 0
                          ? null
                          : (stages[i - 1].count == 0 ? 0 : stages[i].count / stages[i - 1].count * 100),
                      previousLabel: i == 0 ? null : stages[i - 1].label.toLowerCase(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FunnelLabel extends StatelessWidget {
  const _FunnelLabel({required this.stage, required this.pctOfTotal, this.pctOfPrevious, this.previousLabel});

  final FunnelStageData stage;
  final double pctOfTotal;
  final double? pctOfPrevious;
  final String? previousLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conversion = pctOfPrevious == null
        ? '${pctOfTotal.toStringAsFixed(0)}% of total'
        : '${pctOfPrevious!.toStringAsFixed(0)}% of $previousLabel · ${pctOfTotal.toStringAsFixed(0)}% of total';

    final tokens = theme.tokens;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(stage.label, style: theme.textTheme.bodyMedium),
              SizedBox(width: tokens.space.xs),
              Flexible(
                child: NumericText(
                  stage.count,
                  role: TextRole.cardTitle,
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.space.xs / 2),
          Text(
            conversion,
            style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (stage.caption != null)
            Text(
              stage.caption!,
              style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

/// Draws the continuous trapezoid silhouette: stage `i`'s top edge is stage
/// `i-1`'s width (so consecutive stages connect with no visual seam) and its
/// bottom edge is its own — a real narrowing funnel, not `n` separately-
/// scaled bars. A non-zero stage is floored to a minimum visible width so a
/// genuinely thin tail (2% of the top) doesn't taper away to nothing.
class _FunnelPainter extends CustomPainter {
  _FunnelPainter({required this.fractions, required this.color, required this.boundaryColor});

  final List<double> fractions;
  final Color color;
  final Color boundaryColor;

  static const _minFraction = 0.03;

  @override
  void paint(Canvas canvas, Size size) {
    if (fractions.isEmpty || size.width <= 0 || size.height <= 0) return;
    final segmentHeight = size.height / fractions.length;
    final fillPaint = Paint()..color = color;
    final boundaryPaint = Paint()
      ..color = boundaryColor
      ..strokeWidth = 2;
    final centerX = size.width / 2;

    double widthFor(int index) {
      final fraction = fractions[index];
      final floored = fraction <= 0 ? 0.0 : fraction.clamp(_minFraction, 1.0);
      return size.width * floored;
    }

    for (var i = 0; i < fractions.length; i++) {
      final topWidth = widthFor(i == 0 ? 0 : i - 1);
      final bottomWidth = widthFor(i);
      final y0 = i * segmentHeight;
      final y1 = (i + 1) * segmentHeight;

      final path = Path()
        ..moveTo(centerX - topWidth / 2, y0)
        ..lineTo(centerX + topWidth / 2, y0)
        ..lineTo(centerX + bottomWidth / 2, y1)
        ..lineTo(centerX - bottomWidth / 2, y1)
        ..close();
      canvas.drawPath(path, fillPaint);

      if (i > 0) {
        canvas.drawLine(Offset(centerX - topWidth / 2, y0), Offset(centerX + topWidth / 2, y0), boundaryPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FunnelPainter oldDelegate) =>
      !listEquals(oldDelegate.fractions, fractions) ||
      oldDelegate.color != color ||
      oldDelegate.boundaryColor != boundaryColor;
}
