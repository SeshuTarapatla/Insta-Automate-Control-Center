import 'package:flutter/material.dart';

import '../../core/dependency_models.dart';

/// A one-chip-per-check glance row — ARCHITECTURE §9's "dependency strip."
/// The Services > Dependencies tab already has the detailed `DependencyRow`
/// (icon + label + full sentence + latency); this is deliberately smaller,
/// since Overview's job is "does anything need attention," not the sentence
/// explaining why.
class DependencyStrip extends StatelessWidget {
  const DependencyStrip({super.key, required this.snapshot});

  final DependencySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final dependency in snapshot.items) _DependencyChip(dependency: dependency)],
    );
  }
}

class _DependencyChip extends StatelessWidget {
  const _DependencyChip({required this.dependency});

  final Dependency dependency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = dependency.level.color(theme);

    return Tooltip(
      message: dependency.detail,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: dependency.level == DependencyLevel.ok ? scheme.outlineVariant : color.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(dependency.level.icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(dependency.label, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
