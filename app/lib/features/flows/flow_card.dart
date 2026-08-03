import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_snack_bar.dart';
import '../../core/app_theme.dart';
import '../../core/file_opener.dart';
import '../../core/flow_switch_confirm.dart';
import '../../core/force_run.dart';
import '../../core/scheduler_models.dart';
import '../settings/config_controller.dart';
import 'flows_controller.dart';

/// Prefect's own UI already has the real logs for a run; CP 4.1's in-app log
/// viewer doesn't exist yet, so "jump to its logs" opens this instead.
String _prefectRunUrl(String runId) => 'http://localhost:4200/flow-runs/flow-run/$runId';

class FlowCard extends ConsumerWidget {
  const FlowCard({super.key, required this.state});

  final FlowState state;

  Color _statusColor(ThemeData theme) {
    final scheme = theme.colorScheme;
    final palette = theme.palette;
    if (!state.switchOn) return scheme.onSurfaceVariant;
    if (state.phase == 'running') return palette.statusGood;
    if (!state.gate.ok) return palette.statusWarn;
    return palette.statusInfo;
  }

  String? _todayLine() {
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

  Future<void> _toggleSwitch(BuildContext context, WidgetRef ref, bool value) async {
    final key = flowSwitchKey(state.flow);
    if (!await confirmFlowSwitch(context, key, value)) return;
    try {
      await ref.read(configControllerProvider.notifier).applySwitch(key, value);
    } on DioException {
      if (context.mounted) AppSnackBar.show(context, 'Could not update $key', isError: true);
    }
  }

  Future<void> _runNow(BuildContext context, WidgetRef ref) async {
    await ref.read(flowsControllerProvider.notifier).sendCommand(state.flow, 'skip_wait');
    if (context.mounted) {
      AppSnackBar.show(context, '${flowTitle[state.flow]}: ${_runNowLabel()} sent');
    }
  }

  String _runNowLabel() => state.phase == 'waiting' ? 'Skip wait' : 'Run now';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(flowsTickProvider);
    ref.watch(pendingCommandProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final observedAt = ref.watch(flowsControllerProvider.notifier).observedAtFor(state.flow);
    final gateText = state.gate.detail ?? (state.gate.ok ? null : state.gate.reason);
    final lastRun = state.lastRun;
    // Optimistic feedback only - the agent's queue/heartbeat round trip is
    // fast, but the worker actually picking up the run can lag a few
    // seconds, long enough for an impatient second click on Force run.
    final pending = ref.read(pendingCommandProvider.notifier).isPending(state.flow);

    return SizedBox(
      width: 360,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _CountdownRing(state: state, observedAt: observedAt, color: _statusColor(theme)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          flowTitle[state.flow] ?? state.flow,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          state.switchOn
                              ? (phaseLabel[state.phase] ?? state.phase)
                              : 'skipped: switch OFF',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: state.switchOn,
                    onChanged: (value) => _toggleSwitch(context, ref, value),
                  ),
                ],
              ),
              if (gateText != null) ...[
                const SizedBox(height: 10),
                Tooltip(
                  message: gateText,
                  child: Text(
                    gateText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: state.gate.ok ? scheme.onSurfaceVariant : scheme.error,
                    ),
                  ),
                ),
              ],
              if (_todayLine() != null) ...[
                const SizedBox(height: 8),
                Text(
                  _todayLine()!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                height: 36,
                child: pending
                    ? Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              'Command sent — waiting for it to take effect…',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () => _runNow(context, ref),
                            child: Text(_runNowLabel()),
                          ),
                          OutlinedButton(
                            onPressed: () => forceRunFlow(context, ref, state),
                            child: const Text('Force run'),
                          ),
                          if (state.phase == 'running' && state.lastRun != null)
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
                              onPressed: () => stopFlowRun(context, ref, state),
                              child: const Text('Stop'),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      lastRun == null
                          ? 'No run yet this session'
                          : 'Last run: ${lastRun.state}'
                                '${lastRun.durationS != null ? ' · ${lastRun.durationS!.round()}s' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (lastRun != null)
                    TextButton(
                      onPressed: () => FileOpener.openUrl(_prefectRunUrl(lastRun.id)),
                      child: const Text('View logs'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountdownRing extends StatelessWidget {
  const _CountdownRing({required this.state, required this.observedAt, required this.color});

  final FlowState state;
  final DateTime? observedAt;
  final Color color;

  static const _size = 56.0;

  /// mm:ss (or h:mm:ss past an hour) — denser and more immediately readable
  /// as a countdown than "20m15s", especially once a wait runs to minutes.
  String _format(Duration d) {
    final total = d.inSeconds.clamp(0, 1 << 30);
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    final secondsPart = seconds.toString().padLeft(2, '0');
    if (hours > 0) return '$hours:${minutes.toString().padLeft(2, '0')}:$secondsPart';
    return '$minutes:$secondsPart';
  }

  IconData get _phaseIcon => switch (state.phase) {
    'running' => Icons.play_arrow,
    'day_paused' => Icons.pause,
    _ => Icons.schedule,
  };

  @override
  Widget build(BuildContext context) {
    final deadline = state.nextTriggerAt;
    final showCountdown = state.phase == 'waiting' && deadline != null;
    final remaining = showCountdown ? deadline.difference(DateTime.now()) : null;

    if (!showCountdown || remaining == null || remaining.isNegative) {
      return SizedBox(
        width: _size,
        height: _size,
        child: Container(
          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.15)),
          child: Icon(_phaseIcon, color: color, size: 24),
        ),
      );
    }

    final total = observedAt == null ? remaining : deadline.difference(observedAt!);
    final fraction = total.inMilliseconds <= 0
        ? 0.0
        : (remaining.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Re-keyed on the deadline so a re-target (edited wait, skip_wait)
          // starts a fresh animation rather than tweening across a jump.
          // Rebuilding every second (FlowCard's tick) still looks like one
          // continuous sweep: `begin` is recomputed from the real clock each
          // time, so each second's animation just re-commits to the same
          // curve a true continuous one would already be on — no visible
          // step, and it self-corrects for any drift instead of accumulating
          // it the way a single long-lived animation would.
          TweenAnimationBuilder<double>(
            key: ValueKey(deadline),
            tween: Tween(begin: fraction, end: 0.0),
            duration: remaining,
            curve: Curves.linear,
            builder: (context, value, _) => CircularProgressIndicator(
              value: value.clamp(0.0, 1.0),
              strokeWidth: 4,
              strokeCap: StrokeCap.round,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
            ),
          ),
          Text(
            _format(remaining),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
