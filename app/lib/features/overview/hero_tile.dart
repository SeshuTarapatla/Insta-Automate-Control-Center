// SCREENS.md §1 — "the headline the page has never had": one computed
// sentence plus, at most, two actions, with its `StatusKind` driving the
// whole tile's `accentEdge` so overall health is legible from peripheral
// vision. Priority, worst first: agent disconnected → bad; any service
// failed → bad; any dependency down → warn; otherwise → good. Two things
// deliberately do *not* factor in here, both normal operation rather than
// something to flag: a standing-by flow (its condition hasn't arrived yet)
// and a flow sitting at today's cap — the cap exists precisely so the
// pipeline stops there; reaching it isn't a problem, it's the cap doing its
// job. Today's caps get their own dedicated read in `CapsTile`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connection_state.dart';
import '../../core/dependency_models.dart';
import '../../core/library_models.dart';
import '../../core/nav_state.dart';
import '../../core/service_models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import '../../ui/status.dart';
import '../../ui/surfaces.dart';
import '../library/library_controller.dart';
import '../services/dependencies_controller.dart';
import '../services/services_controller.dart';
import 'curation_tile.dart';

class _Hero {
  const _Hero({required this.kind, required this.headline, this.detail});
  final StatusKind kind;
  final String headline;
  final String? detail;
}

_Hero _compute({
  required AgentConnection connection,
  required List<ServiceStatus> services,
  required DependencySnapshot dependencies,
}) {
  if (connection != AgentConnection.connected) {
    return const _Hero(kind: StatusKind.bad, headline: 'Agent disconnected', detail: 'Nothing is being monitored right now.');
  }

  final failed = services.where((s) => s.state == ServiceState.failed).toList();
  if (failed.isNotEmpty) {
    final headline = failed.length == 1 ? '${failed.first.label} has failed' : '${failed.length} services have failed';
    return _Hero(kind: StatusKind.bad, headline: headline, detail: failed.map((s) => s.label).join(' · '));
  }

  final down = dependencies.items.where((d) => d.level != DependencyLevel.ok).toList();
  final reasons = [for (final dep in down) '${dep.label} is ${dep.level.name}'];

  if (reasons.isEmpty) {
    return const _Hero(kind: StatusKind.good, headline: 'All five flows running normally');
  }

  final plural = reasons.length != 1;
  final headline = '${reasons.length} thing${plural ? 's' : ''} need${plural ? '' : 's'} attention';
  return _Hero(kind: StatusKind.warn, headline: headline, detail: reasons.take(3).join(' · '));
}

class HeroTile extends ConsumerWidget {
  const HeroTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    final connection = ref.watch(connectionProvider);
    final services = ref.watch(servicesControllerProvider).value ?? const [];
    final dependencies = ref.watch(dependenciesControllerProvider).value;
    final folders = ref.watch(libraryFoldersControllerProvider).value ?? const <LibraryFolderInfo>[];

    if (dependencies == null) {
      // Nothing to compute a real headline from yet — a plain loading tile
      // rather than a false "all normal" while data is still arriving.
      return const AppCard(child: SizedBox(height: 56, child: Center(child: CircularProgressIndicator(strokeWidth: 2))));
    }

    final hero = _compute(connection: connection, services: services, dependencies: dependencies);
    final waiting = curationFolders.fold<int>(
      0,
      (sum, folder) => sum + (folders.where((f) => f.name == folder).map((f) => f.total).firstOrNull ?? 0),
    );

    return AppCard(
      accentEdge: hero.kind,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(hero.headline, style: theme.textTheme.titleLarge),
                if (hero.detail != null) ...[
                  SizedBox(height: tokens.space.xs / 2),
                  Text(
                    hero.detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(color: tokens.content.secondary),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: tokens.space.lg),
          ButtonGroup(
            children: [
              if (waiting > 0)
                AppButton(
                  label: 'Review $waiting waiting',
                  tone: ButtonTone.primary,
                  onPressed: () {
                    ref.read(selectedFolderProvider.notifier).select(curationFolders.first);
                    ref.read(selectedEntityProvider.notifier).select(null);
                    ref.read(selectedNavIndexProvider.notifier).select(libraryIndex);
                  },
                ),
              AppButton(label: 'Go to Flows', onPressed: () => ref.read(selectedNavIndexProvider.notifier).select(flowsIndex)),
            ],
          ),
        ],
      ),
    );
  }
}
