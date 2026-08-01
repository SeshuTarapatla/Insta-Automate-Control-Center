import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/scheduler_models.dart';
import '../flows/flows_controller.dart';
import 'live_controller.dart';
import 'log_console.dart';
import 'run_summary.dart';
import 'surfaces/classify_surface.dart';
import 'surfaces/follow_surface.dart';
import 'surfaces/ingest_surface.dart';
import 'surfaces/scan_surface.dart';
import 'surfaces/scrape_surface.dart';

/// The showpiece screen (CP 4.4): a log console that follows whichever run is
/// selected, a flow-specific visualization surface, and a run summary with
/// counters. Two columns, not three (D42's follow-up) — the visualization
/// surface is the whole point of this screen and images need real room, so
/// it gets everything to the right of a fixed-width left column; the summary
/// (a handful of rows plus the device pane) sizes to its own content at the
/// top of that column rather than stretching to fill it and leaving the rest
/// blank, and the log console takes whatever height is left below it.
class LivePage extends ConsumerStatefulWidget {
  const LivePage({super.key});

  @override
  ConsumerState<LivePage> createState() => _LivePageState();
}

class _LivePageState extends ConsumerState<LivePage> {
  bool _autoSelected = false;

  void _maybeAutoSelect(SchedulerSnapshot snapshot) {
    if (_autoSelected) return;
    for (final flow in flowOrder) {
      if (snapshot.flows[flow]?.phase == 'running') {
        _autoSelected = true;
        ref.read(selectedFlowProvider.notifier).select(flow);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<SchedulerSnapshot>>(flowsControllerProvider, (previous, next) {
      next.whenData(_maybeAutoSelect);
    });

    // `ref.listen` only fires on a *future* change - if the snapshot already
    // arrived before this page was built (likely, since Flows watches the
    // same provider), the auto-select needs a nudge from the value already
    // held. Deferred to after this frame since mutating another provider's
    // state synchronously mid-build isn't safe.
    final snapshot = ref.watch(flowsControllerProvider).value;
    if (snapshot != null && !_autoSelected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoSelect(snapshot));
    }

    final selectedFlow = ref.watch(selectedFlowProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Wrap(
            spacing: 8,
            children: [
              for (final flow in flowOrder)
                ChoiceChip(
                  label: Text(flowTitle[flow] ?? flow),
                  selected: selectedFlow == flow,
                  onSelected: (_) {
                    _autoSelected = true;
                    ref.read(selectedFlowProvider.notifier).select(flow);
                  },
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 420,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(margin: const EdgeInsets.fromLTRB(12, 12, 12, 6), child: const RunSummary()),
                    Expanded(
                      child: Card(margin: const EdgeInsets.fromLTRB(12, 6, 12, 12), child: const LogConsole()),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Card(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  child: const _VisualizationSurface(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VisualizationSurface extends ConsumerWidget {
  const _VisualizationSurface();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(liveControllerProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Could not load: $error')),
      data: (state) => switch (state.flow) {
        'entity-scan' => ScanSurface(events: state.events),
        'entity-classify' => ClassifySurface(events: state.events),
        'entity-scrape' => ScrapeSurface(events: state.events),
        'entity-follow' => FollowSurface(events: state.events),
        'entity-ingest' => IngestSurface(events: state.events),
        _ => Center(child: Text('No visualization for ${state.flow}')),
      },
    );
  }
}
