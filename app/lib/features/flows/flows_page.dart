// SCREENS.md §2 / V2.6 — a real pipeline: five nodes and four edges instead
// of five disconnected cards in a `Wrap` (AUDIT §13), with the edges
// carrying live backlog counts so the reserve gates (D86/D91) are visible,
// not just explained in a tooltip.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library_models.dart';
import '../../core/scheduler_models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/feedback.dart';
import '../../ui/icons.dart';
import '../../ui/page.dart';
import '../library/library_controller.dart';
import '../settings/config_controller.dart';
import 'flow_node.dart';
import 'flows_controller.dart';
import 'pipeline_edge.dart';

class FlowsPage extends ConsumerWidget {
  const FlowsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(flowsControllerProvider);
    final folders = ref.watch(libraryFoldersControllerProvider).value ?? const <LibraryFolderInfo>[];
    final limits = ref.watch(configControllerProvider).value?.values.limits;

    return AppPage(
      title: 'Flows',
      body: async.stateView(
        describeError: describeFlowsError,
        onRetry: () => ref.read(flowsControllerProvider.notifier).refresh(),
        data: (snapshot) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!snapshot.online) _OfflineBanner(theme: theme),
            Expanded(
              child: snapshot.flows.isEmpty
                  ? EmptyView(
                      icon: Icons.hourglass_empty,
                      title: snapshot.online ? 'Waiting for the first heartbeat' : 'No flow state yet',
                      body: snapshot.online
                          ? 'No flow state yet — waiting for the first heartbeat.'
                          : "The scheduler hasn't posted a heartbeat yet. Is the pipeline pod running?",
                    )
                  : SingleChildScrollView(
                      child: _Pipeline(snapshot: snapshot, folders: folders, limits: limits),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pipeline extends StatelessWidget {
  const _Pipeline({required this.snapshot, required this.folders, required this.limits});

  final SchedulerSnapshot snapshot;
  final List<LibraryFolderInfo> folders;
  final Map<String, int>? limits;

  int _count(String folder) => folders.where((f) => f.name == folder).map((f) => f.total).firstOrNull ?? 0;

  @override
  Widget build(BuildContext context) {
    // The same target `reduceReserveFlow` (`core/force_run.dart`) computes —
    // FOLLOW × SCRAPE_RESERVE_FACTOR — mirrored here so the edge into Follow
    // can show the reserve gate visually (SCREENS.md §2), not just explain it
    // in a tooltip.
    final follow = limits?['FOLLOW'] ?? 60;
    final factor = limits?['SCRAPE_RESERVE_FACTOR'] ?? 3;
    final reserveTarget = follow * factor;
    final scraped = _count('scraped');
    final followQueued = _count('follow_queued');
    final followEdgeWarn = (scraped + followQueued) > reserveTarget;

    final ingest = snapshot.flows['entity-ingest'];
    final scan = snapshot.flows['entity-scan'];
    final classify = snapshot.flows['entity-classify'];
    final scrape = snapshot.flows['entity-scrape'];
    final followFlow = snapshot.flows['entity-follow'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ingest != null) FlowNode(state: ingest),
        if (ingest != null && scan != null) PipelineEdge(label: 'entities/ queued', count: _count('entities')),
        if (scan != null) FlowNode(state: scan),
        if (scan != null && classify != null) PipelineEdge(label: 'scanned/', count: _count('scanned')),
        if (classify != null) FlowNode(state: classify),
        if (classify != null && scrape != null)
          PipelineEdge(label: 'gender_valid/', count: _count('gender_valid'), reviewFolder: 'gender_valid'),
        if (scrape != null) FlowNode(state: scrape),
        if (scrape != null && followFlow != null)
          PipelineEdge(label: 'scraped/', count: scraped, reviewFolder: 'scraped', warn: followEdgeWarn),
        if (followFlow != null) FlowNode(state: followFlow),
      ],
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final tokens = theme.tokens;
    return Material(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: tokens.space.lg, vertical: tokens.space.sm),
        child: Row(
          children: [
            AppIcon(AppIcons.offline, color: theme.colorScheme.onErrorContainer, size: IconSize.sm),
            SizedBox(width: tokens.space.xs),
            Expanded(
              child: Text(
                "Scheduler hasn't been heard from — the pipeline pod may be down.",
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
