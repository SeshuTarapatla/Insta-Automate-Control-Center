import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_state_view.dart';
import '../../core/dependency_models.dart';
import 'dependencies_controller.dart';
import 'services_controller.dart';

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
      data: (snapshot) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        children: [
          _summary(theme, snapshot),
          const SizedBox(height: 20),
          for (final group in DependencyGroup.values)
            if (snapshot.inGroup(group).isNotEmpty) ...[
              _groupHeader(theme, group),
              const SizedBox(height: 10),
              for (final dependency in snapshot.inGroup(group))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DependencyRow(dependency: dependency),
                ),
              const SizedBox(height: 18),
            ],
        ],
      ),
    );
  }

  Widget _summary(ThemeData theme, DependencySnapshot snapshot) {
    final scheme = theme.colorScheme;
    final worst = snapshot.worst;
    final headline = switch (worst) {
      DependencyLevel.ok => 'Everything the pipeline depends on is up',
      DependencyLevel.warn => '${snapshot.warn} need attention',
      DependencyLevel.fail => '${snapshot.fail} down',
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: worst.color(theme).withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(worst.icon, color: worst.color(theme)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(headline, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  '${snapshot.ok} ok · ${snapshot.warn} warning · ${snapshot.fail} failed — '
                  'checked ${TimeOfDay.fromDateTime(snapshot.checkedAt).format(context)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          _refreshing
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : FilledButton.tonalIcon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Re-check'),
                ),
        ],
      ),
    );
  }

  Widget _groupHeader(ThemeData theme, DependencyGroup group) {
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(group.label, style: theme.textTheme.titleSmall),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            group.blurb,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
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
    final scheme = theme.colorScheme;
    final color = dependency.level.color(theme);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: dependency.level == DependencyLevel.ok
              ? scheme.outlineVariant
              : color.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(dependency.level.icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
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
                color: dependency.level == DependencyLevel.ok ? scheme.onSurfaceVariant : null,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${dependency.latencyMs.round()} ms',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
