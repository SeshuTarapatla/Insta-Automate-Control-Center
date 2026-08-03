import 'package:flutter/material.dart';

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
    final scheme = theme.colorScheme;
    final fraction = maxCount == 0 ? 0.0 : (count / maxCount).clamp(0.0, 1.0);
    final pct = maxCount == 0 ? 0.0 : (count / maxCount * 100);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              Text('$count', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Text(
                '(${pct.toStringAsFixed(0)}%)',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Container(height: 10, width: constraints.maxWidth, color: scheme.surfaceContainerHighest),
                  Container(height: 10, width: constraints.maxWidth * fraction, color: scheme.primary),
                ],
              ),
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 3),
            Text(caption!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}
