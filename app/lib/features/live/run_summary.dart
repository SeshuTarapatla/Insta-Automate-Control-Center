import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/flow_event_models.dart';
import '../../core/scheduler_models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/icons.dart';
import '../../ui/overlays.dart';
import '../../ui/status.dart';
import '../../ui/text.dart';
import '../flows/flow_status.dart';
import '../flows/flows_controller.dart';
import 'live_controller.dart';
import 'surfaces/surface_common.dart';

/// A once-a-second rebuild trigger for the elapsed-run timer below — same
/// `StreamProvider.autoDispose` shape as `device_bar.dart`'s 5s device poll,
/// just faster, and only ever watched while a run is actually `running`
/// (`RunSummary.build`), so an idle/waiting flow costs nothing extra.
final _secondTickProvider = StreamProvider.autoDispose<int>(
  (ref) => Stream<int>.periodic(const Duration(seconds: 1), (tick) => tick),
);

String _tooltipMessage(FlowState flowState, LiveState? live) {
  final lines = <String>[];
  final today = flowTodayLine(flowState);
  if (today != null) lines.add('Today: $today');
  if (flowState.lastRun != null) {
    final lastRun = flowState.lastRun!;
    lines.add('Last run: ${lastRun.state}${lastRun.durationS != null ? ' · ${lastRun.durationS!.round()}s' : ''}');
  }
  if (live?.runId != null) lines.add('Run id: ${live!.runId}');
  return lines.isEmpty ? 'No further detail yet.' : lines.join('\n');
}

/// The Live screen's header ribbon strip (V2.8/SCREENS §3). What used to be
/// its own scrolling card of label/value rows (~180px, the first thing you'd
/// see on the app's showpiece screen, and visually inert) is now one line:
/// phase, an elapsed timer while actually running, and the live per-item
/// counters — still click-to-filter (D113), unchanged. Run id and last-run
/// detail move into an info tooltip, since they're reference info you check
/// once, not something you watch tick over. Device control stays separate
/// (`DeviceBar`, D46) — this widget only ever renders flow state.
class RunSummary extends ConsumerWidget {
  const RunSummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final live = ref.watch(liveControllerProvider).value;
    final schedulerSnapshot = ref.watch(flowsControllerProvider).value;
    final flow = live?.flow;
    final flowState = flow == null ? null : schedulerSnapshot?.flows[flow];

    if (flowState == null) {
      return Text(
        'No scheduler data yet.',
        style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
      );
    }

    final kind = flowStatusKindOf(flowState);
    final running = kind == FlowStatusKind.running;
    if (running) ref.watch(_secondTickProvider);
    final elapsed = running && live?.runStartedAt != null
        ? DateTime.now().toUtc().difference(live!.runStartedAt!.toUtc())
        : null;

    final counters = _liveCounters(flow, live?.events ?? const []);
    final canFilter = _filterableCounterFlows.contains(flow);
    final selectedVerdicts = live?.selectedVerdicts ?? const {};

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: tokens.space.sm,
      runSpacing: tokens.space.xs,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(flowStatusIcon(kind), size: IconSize.sm, color: flowAccent(kind).fg(tokens)),
            SizedBox(width: tokens.space.xs),
            Text(flowStatusLabel(kind, flowState), style: theme.textTheme.bodyMedium),
          ],
        ),
        if (elapsed != null)
          NumericText('${formatFlowCountdown(elapsed)} elapsed', role: TextRole.caption, color: tokens.content.secondary),
        for (final entry in counters.entries)
          if (canFilter && !_nonFilterableCounterKeys.contains(entry.key))
            _CounterChip(
              kind: _counterTone(flow, entry.key),
              label: entry.key,
              value: entry.value,
              selected: selectedVerdicts.contains(entry.key),
              onTap: () => ref.read(liveControllerProvider.notifier).toggleVerdict(entry.key),
            )
          else
            _CounterChip(kind: StatusKind.neutral, label: entry.key, value: entry.value),
        AppTooltip(
          rich: true,
          title: 'Run detail',
          message: _tooltipMessage(flowState, live),
          child: AppIcon(AppIcons.info, size: IconSize.sm, color: tokens.content.secondary),
        ),
      ],
    );
  }
}

/// Tallies the per-item events already streaming into the visualization
/// surface, live, one at a time — rather than waiting for `flow.completed`'s
/// single end-of-run summary (which does carry the same final numbers, but
/// only once the whole run is over). Deliberately per-flow: each flow's
/// per-item event carries different, flow-specific information (a scrape's
/// `posts`/`followers`/`following` are one profile's own stats, not a count
/// to tally at all), so there is no single generic "sum every counters map"
/// rule that stays meaningful across flows — see D40 for why that was wrong.
Map<String, int> _liveCounters(String? flow, List<FlowEvent> events) {
  switch (flow) {
    case 'entity-scan':
      // scan.item/scan.completed already carry the pipeline's own running
      // added/scanned tally on every event — just read the latest one.
      FlowEvent? latest;
      for (final event in events) {
        if (event.kind == 'scan.item' || event.kind == 'scan.completed') latest = event;
      }
      return latest == null ? const {} : latest.counters.map((key, value) => MapEntry(key, value as int));
    case 'entity-classify':
      final counts = <String, int>{};
      for (final event in events) {
        if ((event.kind == 'classify.access' || event.kind == 'classify.gender') && event.verdict != null) {
          counts[event.verdict!] = (counts[event.verdict!] ?? 0) + 1;
        }
      }
      return counts;
    case 'entity-scrape':
      final done = events.where((e) => e.kind == 'scrape.done').length;
      // Every skip reason (PUBLIC, NO_POSTS, FMIN/FMAX, not-found, ...)
      // folded into one "failed" bucket — your own call: a per-reason
      // breakdown would be a lot more chips for a distinction the filter
      // doesn't need.
      final skipped = events.where((e) => e.kind == 'scrape.skipped').length;
      return done + skipped == 0
          ? const {}
          : {'processed': done + skipped, 'scraped': done, 'failed': skipped};
    case 'entity-follow':
      final counts = <String, int>{};
      for (final event in events) {
        if (event.kind == 'follow.result' && event.verdict != null) {
          counts[event.verdict!] = (counts[event.verdict!] ?? 0) + 1;
        }
      }
      return counts;
    case 'entity-ingest':
      final added = events.where((e) => e.kind == 'entity.added').length;
      return added == 0 ? const {} : {'added': added};
    default:
      return const {};
  }
}

/// Flows whose counters double as a click-to-filter control on the adjacent
/// result-card list (Classify/Follow/Scrape — every one whose result cards
/// carry a matching per-item key). Scan/Ingest counters are running tallies
/// with no per-card field to filter by, so they stay plain display-only
/// chips.
const _filterableCounterFlows = {'entity-classify', 'entity-follow', 'entity-scrape'};

/// Scrape's "processed" is a superset (every attempted subject, success or
/// not) rather than its own category — nothing in the card list matches
/// "processed" specifically, so it's excluded from filtering even on a
/// flow that otherwise supports it.
const _nonFilterableCounterKeys = {'processed'};

StatusKind _counterTone(String? flow, String key) {
  if (flow == 'entity-scrape') {
    return switch (key) {
      'scraped' => StatusKind.good,
      'failed' => StatusKind.bad,
      _ => StatusKind.neutral,
    };
  }
  return toneFor(key);
}

/// `StatusChip`'s visual shape, with an [AnimatedCounter] in place of a
/// plain string value — the "implicit animation on counters" ARCHITECTURE §9
/// promised, applied to the one place in this app a number changes every
/// few seconds while you're watching it. Kept local rather than widening
/// `StatusChip` itself: every other call site wants a plain string label,
/// and `StatusChip` is shared app-wide (COMPONENTS.md §3).
class _CounterChip extends StatelessWidget {
  const _CounterChip({required this.kind, required this.label, required this.value, this.selected = false, this.onTap});

  final StatusKind kind;
  final String label;
  final int value;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    final fg = kind.onContainer(tokens);
    final radius = BorderRadius.circular(tokens.geometry.radiusSm);

    final chip = Container(
      padding: EdgeInsets.symmetric(horizontal: tokens.space.xs, vertical: 1),
      decoration: BoxDecoration(
        color: kind.container(tokens),
        borderRadius: radius,
        border: selected ? Border.all(color: tokens.accent.primary, width: 1.5) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg)),
          AnimatedCounter(value, role: TextRole.label, color: fg),
        ],
      ),
    );

    if (onTap == null) return chip;
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(onTap: onTap, borderRadius: radius, child: chip),
    );
  }
}
