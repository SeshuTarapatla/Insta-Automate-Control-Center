import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/feedback.dart';
import '../../core/force_run.dart';
import '../../core/scheduler_models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/icons.dart';
import '../../ui/layout.dart';
import '../../ui/page.dart';
import '../../ui/surfaces.dart';
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

/// The showpiece screen (CP 4.4, reworked V2.8/SCREENS §3): a log console
/// that follows whichever run is selected and a flow-specific visualization
/// surface, side by side in a `ResizableSplit` — no more hardcoded 420px
/// column tuned to one flow (D45's own comment flagged this). `RunSummary`
/// dissolved from its own card into a one-line header strip (phase, elapsed
/// timer, live counters); device control stays in the header row as a
/// compact `DeviceBar` (D46).
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

  // Which pane (if either) is maximised to fill the whole body — the
  // "just show me the images" / "just show me the logs" modes SCREENS §3
  // calls for, one click away in either direction via each pane's own
  // ⤢ button. `null` means the normal side-by-side split.
  String? _expandedPane;

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
    final tokens = Theme.of(context).tokens;

    return AppPage(
      title: 'Live',
      leading: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: tokens.space.xs,
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
          // Trigger now / Stop the selected flow right from here — the
          // point of these living in the header (not just on the Flows
          // screen) is not having to switch tabs when the goal is
          // simply "trigger this and watch its logs," or "something's
          // wrong, stop it now" (D69 — added after a real incident with
          // no way to do the latter short of uninstalling the release).
          if (snapshot?.flows[selectedFlow] case final state?)
            Padding(
              padding: EdgeInsets.only(right: tokens.space.md),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state.phase == 'running' && state.lastRun != null)
                    Padding(
                      padding: EdgeInsets.only(right: tokens.space.sm),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                        onPressed: () => stopFlowRun(context, ref, state),
                        child: const Text('Stop'),
                      ),
                    ),
                  OutlinedButton(
                    onPressed: () => forceRunFlow(context, ref, state),
                    child: const Text('Trigger now'),
                  ),
                  if (state.flow == 'entity-follow')
                    Padding(
                      padding: EdgeInsets.only(left: tokens.space.sm),
                      child: OutlinedButton(
                        onPressed: () => reduceReserveFlow(context, ref, state),
                        child: const Text('Reduce reserve'),
                      ),
                    ),
                ],
              ),
            )
          else
            // Before the first heartbeat arrives there's nothing to act
            // on yet — say so instead of just not rendering the controls,
            // which read as a layout glitch rather than "still loading."
            Padding(
              padding: EdgeInsets.only(right: tokens.space.md),
              child: Text(
                'Waiting for scheduler data…',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
              ),
            ),
          // Device control lives here, not in RunSummary's body (D46) —
          // this row already has the height to spare next to the flow
          // chips, and it frees the whole left column below for the log
          // console instead of competing with it for space.
          const DeviceBar(),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // `RunSummary` dissolved from its own card into this one-line
          // strip (V2.8/SCREENS §3) — what used to be ~180px of scrolling
          // label/value rows is now phase + elapsed + live counters.
          const RunSummary(),
          SizedBox(height: tokens.space.sm),
          Expanded(
            child: switch (_expandedPane) {
              'logs' => _Pane(
                title: 'Logs',
                expanded: true,
                onToggleExpand: () => setState(() => _expandedPane = null),
                child: const LogConsole(),
              ),
              'viz' => _Pane(
                title: 'Visualization',
                expanded: true,
                onToggleExpand: () => setState(() => _expandedPane = null),
                child: const _VisualizationSurface(),
              ),
              _ => ResizableSplit(
                persistKey: 'live.split',
                initialFirstSize: 480,
                minFirst: 320,
                minSecond: 360,
                first: _Pane(
                  title: 'Logs',
                  expanded: false,
                  onToggleExpand: () => setState(() => _expandedPane = 'logs'),
                  child: const LogConsole(),
                ),
                second: _Pane(
                  title: 'Visualization',
                  expanded: false,
                  onToggleExpand: () => setState(() => _expandedPane = 'viz'),
                  child: const _VisualizationSurface(),
                ),
              ),
            },
          ),
        ],
      ),
    );
  }
}

/// A pane's frame: a slim title bar (name + the ⤢ expand/restore toggle)
/// over its content, inside one `AppCard` — replaces the bare
/// `AppCard(child: LogConsole())` / fixed-420px visualization card the
/// two panes used to be wrapped in directly (V2.8/SCREENS §3).
class _Pane extends StatelessWidget {
  const _Pane({required this.title, required this.expanded, required this.onToggleExpand, required this.child});

  final String title;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.space.sm, vertical: tokens.space.xs),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: theme.textTheme.labelMedium?.copyWith(color: tokens.content.secondary, letterSpacing: 0.5),
                  ),
                ),
                IconButton(
                  tooltip: expanded ? 'Restore split' : 'Expand',
                  icon: AppIcon(expanded ? AppIcons.collapse : AppIcons.expand, size: IconSize.sm),
                  visualDensity: VisualDensity.compact,
                  onPressed: onToggleExpand,
                ),
              ],
            ),
          ),
          const AppDivider(),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _VisualizationSurface extends ConsumerWidget {
  const _VisualizationSurface();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(liveControllerProvider);
    return async.stateView(
      data: (state) => switch (state.flow) {
        'entity-scan' => ScanSurface(events: state.events),
        'entity-classify' => ClassifySurface(events: state.events, selectedVerdicts: state.selectedVerdicts),
        'entity-scrape' => ScrapeSurface(events: state.events, selectedVerdicts: state.selectedVerdicts),
        'entity-follow' => FollowSurface(events: state.events, selectedVerdicts: state.selectedVerdicts),
        'entity-ingest' => IngestSurface(events: state.events),
        _ => EmptyView(icon: Icons.visibility_off_outlined, title: 'No visualization for ${state.flow}'),
      },
    );
  }
}
