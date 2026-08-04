import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/dependency_models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/icons.dart';
import '../../ui/surfaces.dart';

/// `ui/status.dart`'s icon vocabulary lives behind `AppIcons` (a `ui/`
/// concern) — `core/dependency_models.dart` can't reach it without inverting
/// the `core/` → `ui/` layering (D100's precedent), so the mapping lives at
/// each consumer instead; `dependencies_tab.dart` has its own copy.
extension _DependencyLevelIconX on DependencyLevel {
  PhosphorIconData Function(PhosphorIconsStyle) get glyph => switch (this) {
    DependencyLevel.ok => AppIcons.success,
    DependencyLevel.warn => AppIcons.warning,
    DependencyLevel.fail => AppIcons.error,
  };
}

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
    final tokens = Theme.of(context).tokens;
    return Wrap(
      spacing: tokens.space.xs,
      runSpacing: tokens.space.xs,
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
    final tokens = theme.tokens;
    final color = dependency.level.color(theme);

    return Tooltip(
      message: dependency.detail,
      child: AppPanel(
        level: SurfaceLevel.raised,
        padding: EdgeInsets.symmetric(horizontal: tokens.space.sm, vertical: tokens.space.xs),
        borderRadius: tokens.geometry.radiusFull,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(dependency.level.glyph, size: IconSize.sm, color: color),
            SizedBox(width: tokens.space.xs),
            Text(dependency.label, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
