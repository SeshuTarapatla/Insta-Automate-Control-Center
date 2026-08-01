import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/scheduler_models.dart';
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

/// Counters for the run currently shown, plus the day's running totals and a
/// device pane — the last of which stays a placeholder until CP 4.5 gives it
/// something real to show, explained rather than left blank (D17's rule
/// applied here too: a pane with nothing real to render says why).
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
          _DevicePanePlaceholder(theme: theme),
        ],
      ),
    );
  }
}

/// Sums every event's `counters` map for the run currently shown — the most
/// recent value per key wins for things like "scanned so far", and keys that
/// only ever appear once (a single `flow.completed` summary) just show that
/// value. Good enough without knowing per-kind semantics ahead of time.
class _EventCounters extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final events = ref.watch(liveControllerProvider).value?.events ?? const [];
    final counters = <String, dynamic>{};
    for (final event in events) {
      counters.addAll(event.counters);
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

class _DevicePanePlaceholder extends StatelessWidget {
  const _DevicePanePlaceholder({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.phone_android_outlined, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Device mirror isn't wired up yet — that's CP 4.5.",
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
