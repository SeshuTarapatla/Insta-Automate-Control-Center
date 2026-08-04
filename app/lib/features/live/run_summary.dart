import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/flow_event_models.dart';
import '../../core/scheduler_models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/layout.dart';
import '../../ui/status.dart';
import '../../ui/text.dart';
import '../flows/flows_controller.dart';
import 'live_controller.dart';

String? _todayLine(FlowState state) {
  final today = state.today;
  if (today == null) return null;
  return switch (state.flow) {
    'entity-scan' =>
      'profiles ${today['profiles']}/${today['profiles_limit']} · '
          'reels ${today['reels']}/${today['reels_limit']} · '
          'posts ${today['posts']}/${today['posts_limit']}',
    'entity-scrape' => 'scraped ${today['scraped']}/${today['limit']}',
    'entity-follow' => 'followed ${today['followed']}/${today['limit']}',
    _ => null,
  };
}

/// Counters for the run currently shown, plus the day's running totals.
/// Device control moved to a compact `DeviceBar` in the Live screen's header
/// (D46) — it no longer competes with the log console for space here.
class RunSummary extends ConsumerWidget {
  const RunSummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final live = ref.watch(liveControllerProvider).value;
    final schedulerSnapshot = ref.watch(flowsControllerProvider).value;
    final flow = live?.flow;
    final flowState = flow == null ? null : schedulerSnapshot?.flows[flow];

    final tokens = theme.tokens;

    return SingleChildScrollView(
      padding: EdgeInsets.all(tokens.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Run summary', style: theme.textTheme.titleMedium),
          SizedBox(height: tokens.space.md),
          if (flowState == null)
            Text('No scheduler data yet.', style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary))
          else
            KeyValueList(
              labelWidth: 76,
              rows: [
                MetricRow(label: 'Phase', value: Text(phaseLabel[flowState.phase] ?? flowState.phase, style: theme.textTheme.bodyMedium)),
                if (_todayLine(flowState) != null)
                  MetricRow(label: 'Today', value: NumericText(_todayLine(flowState)!, role: TextRole.body)),
                if (flowState.lastRun != null)
                  MetricRow(
                    label: 'Last run',
                    value: Text(
                      '${flowState.lastRun!.state}'
                      '${flowState.lastRun!.durationS != null ? ' · ${flowState.lastRun!.durationS!.round()}s' : ''}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                if (live?.runId != null) MetricRow(label: 'Run id', value: MonoText(live!.runId!, role: TextRole.caption)),
              ],
            ),
          SizedBox(height: tokens.space.xl),
          Text('Counters this run', style: theme.textTheme.titleSmall),
          SizedBox(height: tokens.space.sm),
          _EventCounters(flow: flow),
        ],
      ),
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
      final skipped = events.where((e) => e.kind == 'scrape.skipped').length;
      return done + skipped == 0 ? const {} : {'processed': done + skipped, 'scraped': done};
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

class _EventCounters extends ConsumerWidget {
  const _EventCounters({required this.flow});

  final String? flow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final events = ref.watch(liveControllerProvider).value?.events ?? const [];
    final counters = _liveCounters(flow, events);
    if (counters.isEmpty) {
      return Text(
        'No counters yet.',
        style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
      );
    }
    return Wrap(
      spacing: tokens.space.xs,
      runSpacing: tokens.space.xs,
      children: [
        for (final entry in counters.entries)
          StatusChip(kind: StatusKind.neutral, label: '${entry.key}: ${entry.value}', dense: true),
      ],
    );
  }
}

