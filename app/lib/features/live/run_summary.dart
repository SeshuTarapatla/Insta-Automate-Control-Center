import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          _EventCounters(),
          const SizedBox(height: 20),
          Text('Device', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          const DevicePane(),
        ],
      ),
    );
  }
}

/// Shows `flow.completed`'s own counters — the one event kind every flow
/// emits exactly once, at the very end of a run, specifically to carry a
/// whole-run summary (CP 4.3). Per-item events (`scrape.done`, `classify.
/// gender`, ...) carry `counters` too, but those describe one entity each
/// (e.g. `scrape.done`'s `posts`/`followers`/`following` are one profile's
/// stats) — meaningless once merged across a run of many different entities,
/// so they're deliberately excluded here even though they're real data
/// (they're already shown per-card in the visualization surface instead).
class _EventCounters extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final events = ref.watch(liveControllerProvider).value?.events ?? const [];
    final counters = <String, dynamic>{};
    for (final event in events) {
      if (event.kind == 'flow.completed') counters.addAll(event.counters);
    }
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

