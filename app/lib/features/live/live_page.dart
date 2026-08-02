import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/force_run.dart';
import '../../core/scheduler_models.dart';
import '../flows/flows_controller.dart';
import 'device_bar.dart';
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
/// counters. Two columns (D42/D44's follow-up) — the visualization surface is
/// a *fixed*-width right column, since its cards already wrap to use
/// whatever width they're given (D44) rather than needing to keep growing;
/// the extra room instead goes to the log console, which genuinely benefits
/// from more width per line. The left column stretches to fill the rest:
/// the summary (a handful of rows plus counters) sizes to its own content at
/// the top rather than stretching to fill it and leaving the rest blank, and
/// the log console takes whatever height is left below it. Device control
/// lives in the header row instead, as a compact `DeviceBar` (D46).
class LivePage extends ConsumerStatefulWidget {
  const LivePage({super.key});

  @override
  ConsumerState<LivePage> createState() => _LivePageState();
}

class _LivePageState extends ConsumerState<LivePage> {
  // Whether the initial catch-up (below) has already run once. Without this,
  // the postFrameCallback fired on *every* build - including one triggered
  // by a manual chip click itself (`selectedFlowProvider` changing is a
  // `ref.watch`ed dependency of this very widget) - which re-ran
  // `_maybeAutoSelect` against the still-unchanged snapshot and immediately
  // selected the still-running flow right back, undoing the click within
  // the same frame. A real click now only ever gets overridden by a real
  // subsequent `flows.state` broadcast (`ref.listen` below), never by its
  // own rebuild.
  bool _didInitialCatchUp = false;

  // Always follows whichever flow is running - a manual tab click only ever
  // shows something *until the next relevant snapshot*, it does not opt out
  // of auto-follow permanently (that was tried and explicitly rejected: it
  // made the view get stuck on whatever tab happened to be open, since any
  // earlier click - even an incidental one - silently disabled auto-follow
  // for the rest of the session).
  void _maybeAutoSelect(SchedulerSnapshot snapshot) {
    final current = ref.read(selectedFlowProvider);
    if (snapshot.flows[current]?.phase == 'running') return; // already following the active one
    for (final flow in flowOrder) {
      if (snapshot.flows[flow]?.phase == 'running') {
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
    // state synchronously mid-build isn't safe. Only ever done once — see
    // `_didInitialCatchUp`'s own comment for why re-running this on every
    // rebuild was a real bug, not just unnecessary.
    final snapshot = ref.watch(flowsControllerProvider).value;
    if (snapshot != null && !_didInitialCatchUp) {
      _didInitialCatchUp = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoSelect(snapshot));
    }

    final selectedFlow = ref.watch(selectedFlowProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final flow in flowOrder)
                      ChoiceChip(
                        label: Text(flowTitle[flow] ?? flow),
                        selected: selectedFlow == flow,
                        onSelected: (_) => ref.read(selectedFlowProvider.notifier).select(flow),
                      ),
                  ],
                ),
              ),
              // Force run / Stop the selected flow right from here — the
              // point of these living in the header (not just on the Flows
              // screen) is not having to switch tabs when the goal is
              // simply "trigger this and watch its logs," or "something's
              // wrong, stop it now" (D69 — added after a real incident with
              // no way to do the latter short of uninstalling the release).
              if (snapshot?.flows[selectedFlow] case final state?)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (state.phase == 'running' && state.lastRun != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                            onPressed: () => stopFlowRun(context, ref, state),
                            child: const Text('Stop'),
                          ),
                        ),
                      OutlinedButton(
                        onPressed: () => forceRunFlow(context, ref, state),
                        child: const Text('Force run'),
                      ),
                    ],
                  ),
                ),
              // Device control lives here, not in RunSummary's body (D46) —
              // this row already has the height to spare next to the flow
              // chips, and it frees the whole left column below for the log
              // console instead of competing with it for space.
              const DeviceBar(),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
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
              // Fixed, not Expanded, and tightly sized rather than round —
              // the visualization surface's cards already wrap to fill
              // whatever width they're given (D44), so any width beyond what
              // a card actually needs just becomes more of the same wasted
              // space D44 was fixing, not more information. 420 is scrape's
              // own card (D44's 380px `_ScrapeCard`) plus the surface's 16px
              // padding on each side plus a few px for the scrollbar gutter
              // — exactly one column, no leftover. Deliberately tuned to
              // scrape, the only flow tested so far (D45) — classify's cards
              // are narrower (fit fine) and follow's are wider (420, D44),
              // so this may need revisiting once follow/classify get a real
              // test; nothing here assumes scrape's number is universal.
              SizedBox(
                width: 420,
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
