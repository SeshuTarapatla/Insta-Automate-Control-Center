// SCREENS.md §1's "PIPELINE 2×2" tile — the same five-stage pipeline V2.6
// built for the Flows screen, compacted to a glance: five `FlowCardCompact`s
// with the live backlog count between each, reusing the exact folder keys
// `flows/pipeline_edge.dart` reads (`GET /api/library/folders`, no agent
// work needed). No controls, no gate detail — Flows is where that lives.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library_models.dart';
import '../../core/scheduler_models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/icons.dart';
import '../../ui/text.dart';
import '../library/library_controller.dart';
import 'flow_card_compact.dart';

class PipelineStrip extends ConsumerWidget {
  const PipelineStrip({super.key, required this.snapshot});

  final SchedulerSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).tokens;
    final folders = ref.watch(libraryFoldersControllerProvider).value ?? const <LibraryFolderInfo>[];
    int count(String folder) => folders.where((f) => f.name == folder).map((f) => f.total).firstOrNull ?? 0;

    const edgeFolders = ['entities', 'scanned', 'gender_valid', 'scraped'];

    final children = <Widget>[];
    for (var i = 0; i < flowOrder.length; i++) {
      final state = snapshot.flows[flowOrder[i]];
      if (state == null) continue;
      if (children.isNotEmpty) children.add(_EdgeCount(count: count(edgeFolders[i - 1])));
      children.add(FlowCardCompact(state: state));
    }

    return Wrap(spacing: tokens.space.xs, runSpacing: tokens.space.sm, crossAxisAlignment: WrapCrossAlignment.center, children: children);
  }
}

class _EdgeCount extends StatelessWidget {
  const _EdgeCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(AppIcons.chevronRight, size: IconSize.sm, color: tokens.content.tertiary),
        NumericText(count, role: TextRole.micro, color: tokens.content.secondary),
      ],
    );
  }
}
