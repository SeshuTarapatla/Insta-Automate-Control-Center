import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../ui/feedback.dart';
import '../../core/dependency_models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/icons.dart';
import '../../ui/surfaces.dart';
import '../../ui/text.dart';
import 'dependencies_controller.dart';
import 'services_controller.dart';

/// `ui/status.dart`'s icon vocabulary lives behind `AppIcons`
/// (a `ui/` concern) — `core/dependency_models.dart` can't reach it without
/// inverting the `core/` → `ui/` layering (D100's precedent), so the mapping
/// lives here instead, the only consumer.
extension _DependencyLevelIconX on DependencyLevel {
  PhosphorIconData Function(PhosphorIconsStyle) get glyph => switch (this) {
    DependencyLevel.ok => AppIcons.success,
    DependencyLevel.warn => AppIcons.warning,
    DependencyLevel.fail => AppIcons.error,
  };
}

/// The read-only half of Phase 2: k3s, Postgres, Prefect, the two pods, the
/// phone, the internet, Syncthing and disk. The agent supervises none of these,
/// so there is nothing to click — the value is knowing which one is why a flow
/// is failing.
class DependenciesTab extends ConsumerStatefulWidget {
  const DependenciesTab({super.key});

  @override
  ConsumerState<DependenciesTab> createState() => _DependenciesTabState();
}

class _DependenciesTabState extends ConsumerState<DependenciesTab> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await ref.read(dependenciesControllerProvider.notifier).refresh();
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(dependenciesControllerProvider);

    return async.stateView(
      describeError: describeAgentError,
      onRetry: _refresh,
      data: (snapshot) {
        final tokens = theme.tokens;
        return ListView(
          padding: EdgeInsets.all(tokens.space.lg),
          children: [
            _summary(theme, snapshot),
            SizedBox(height: tokens.space.xl),
            for (final group in DependencyGroup.values)
              if (snapshot.inGroup(group).isNotEmpty) ...[
                _groupHeader(theme, group),
                SizedBox(height: tokens.space.sm),
                for (final dependency in snapshot.inGroup(group))
                  Padding(
                    padding: EdgeInsets.only(bottom: tokens.space.sm),
                    child: DependencyRow(dependency: dependency),
                  ),
                SizedBox(height: tokens.space.lg + tokens.space.xs),
              ],
          ],
        );
      },
    );
  }

  Widget _summary(ThemeData theme, DependencySnapshot snapshot) {
    final tokens = theme.tokens;
    final worst = snapshot.worst;
    final headline = switch (worst) {
      DependencyLevel.ok => 'Everything the pipeline depends on is up',
      DependencyLevel.warn => '${snapshot.warn} need attention',
      DependencyLevel.fail => '${snapshot.fail} down',
    };

    return AppPanel(
      level: SurfaceLevel.raised,
      borderRadius: tokens.geometry.radiusLg,
      child: Row(
        children: [
          AppIcon(worst.glyph, color: worst.color(theme)),
          SizedBox(width: tokens.space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(headline, style: theme.textTheme.titleMedium),
                SizedBox(height: tokens.space.xs / 2),
                Text(
                  '${snapshot.ok} ok · ${snapshot.warn} warning · ${snapshot.fail} failed — '
                  'checked ${TimeOfDay.fromDateTime(snapshot.checkedAt).format(context)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
                ),
              ],
            ),
          ),
          _refreshing
              ? Padding(
                  padding: EdgeInsets.symmetric(horizontal: tokens.space.lg),
                  child: const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : FilledButton.tonalIcon(
                  onPressed: _refresh,
                  icon: AppIcon(AppIcons.refresh, size: IconSize.sm),
                  label: const Text('Re-check'),
                ),
        ],
      ),
    );
  }

  Widget _groupHeader(ThemeData theme, DependencyGroup group) {
    final tokens = theme.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(group.label, style: theme.textTheme.titleSmall),
        SizedBox(width: tokens.space.sm),
        Expanded(
          child: Text(group.blurb, style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary)),
        ),
      ],
    );
  }
}

/// Public for the layout test: a failing dependency's sentence is the longest
/// text on the screen, and it has to survive the narrow pane.
class DependencyRow extends StatelessWidget {
  const DependencyRow({super.key, required this.dependency});

  final Dependency dependency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final color = dependency.level.color(theme);

    return AppPanel(
      level: SurfaceLevel.raised,
      padding: EdgeInsets.symmetric(horizontal: tokens.space.md, vertical: tokens.space.sm + 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: tokens.space.xs / 2),
            child: AppIcon(dependency.level.glyph, size: IconSize.sm, color: color),
          ),
          SizedBox(width: tokens.space.md),
          SizedBox(
            width: 140,
            child: Text(
              dependency.label,
              style: theme.textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(
              dependency.detail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: dependency.level == DependencyLevel.ok ? tokens.content.secondary : null,
              ),
            ),
          ),
          SizedBox(width: tokens.space.md),
          NumericText(
            '${dependency.latencyMs.round()} ms',
            role: TextRole.caption,
            color: tokens.content.secondary.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }
}
