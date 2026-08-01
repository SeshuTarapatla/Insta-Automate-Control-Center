import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/flow_event_models.dart';
import '../../core/scheduler_models.dart';
import '../flows/flows_controller.dart';
import 'device_pane.dart';
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

/// Counters for the run currently shown, plus the day's running totals and
/// the device pane (CP 4.5's `DevicePane`).
class RunSummary extends ConsumerWidget {
  const RunSummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final live = ref.watch(liveControllerProvider).value;
    final schedulerSnapshot = ref.watch(flowsControllerProvider).value;
    final flow = live?.flow;
    final flowState = flow == null ? null : schedulerSnapshot?.flows[flow];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Run summary', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          if (flowState == null)
            Text('No scheduler data yet.', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant))
          else ...[
            _SummaryRow(label: 'Phase', value: phaseLabel[flowState.phase] ?? flowState.phase),
            if (_todayLine(flowState) != null) _SummaryRow(label: 'Today', value: _todayLine(flowState)!),
            if (flowState.lastRun != null)
              _SummaryRow(
                label: 'Last run',
                value: '${flowState.lastRun!.state}'
                    '${flowState.lastRun!.durationS != null ? ' · ${flowState.lastRun!.durationS!.round()}s' : ''}',
              ),
            if (live?.runId != null) _SummaryRow(label: 'Run id', value: live!.runId!, mono: true),
          ],
          const SizedBox(height: 20),
          Text('Counters this run', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          _EventCounters(flow: flow),
          const SizedBox(height: 20),
          Text('Device', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          const DevicePane(),
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
    final events = ref.watch(liveControllerProvider).value?.events ?? const [];
    final counters = _liveCounters(flow, events);
    if (counters.isEmpty) {
      return Text(
        'No counters yet.',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in counters.entries)
          Chip(label: Text('${entry.key}: ${entry.value}'), visualDensity: VisualDensity.compact),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(
              value,
              style: mono ? theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace') : theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

