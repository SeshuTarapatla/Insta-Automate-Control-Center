import 'package:flutter/material.dart';

import 'theme/tokens.dart';

/// One bar: a fixed-height track plus a fill proportional to `count/maxCount`
/// — the same hue throughout (one metric across stages, not several series,
/// so there is nothing for color to distinguish), magnitude carried entirely
/// by length. A direct count + percentage label sits above each bar rather
/// than inside it, since several bars are too thin at the tail end of a
/// funnel to hold text. Originally CP 5.4's private `_FunnelStage` in
/// `entity_yield_dialog.dart`; made public and shared once CP 7.2's
/// library-wide funnel became a second real consumer of the exact same bar.
class FunnelStage extends StatelessWidget {
  const FunnelStage({super.key, required this.label, required this.count, required this.maxCount, this.caption});

  final String label;
  final int count;
  final int maxCount;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final fraction = maxCount == 0 ? 0.0 : (count / maxCount).clamp(0.0, 1.0);
    final pct = maxCount == 0 ? 0.0 : (count / maxCount * 100);
    // NumericText (`ui/text.dart`) can't be reached from here without
    // inverting the `core/` → `ui/` layering (D100's precedent) — tabular
    // figures on this count are a small enough loss to accept rather than
    // move this widget out of `core/`.
    final countStyle = theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontFamily: tokens.typography.mono);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              Text('$count', style: countStyle),
              SizedBox(width: tokens.space.xs),
              Text(
                '(${pct.toStringAsFixed(0)}%)',
                style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
              ),
            ],
          ),
          SizedBox(height: tokens.space.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(tokens.geometry.radiusSm),
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Container(height: 10, width: constraints.maxWidth, color: tokens.surface.raised),
                  Container(height: 10, width: constraints.maxWidth * fraction, color: tokens.accent.primary),
                ],
              ),
            ),
          ),
          if (caption != null) ...[
            SizedBox(height: tokens.space.xs * 0.75),
            Text(caption!, style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary)),
          ],
        ],
      ),
    );
  }
}
