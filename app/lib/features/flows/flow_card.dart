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

/// The gate's `reason`/`detail` (ARCHITECTURE §4.3) already says exactly why a
/// flow is or isn't triggering, but `phase`/`next_trigger_at` alone can't tell
/// two very different waits apart: a mandatory post-run cooldown (a real,
/// deterministic "eligible again at X") versus the recheck poll a false
/// condition just sits behind (rechecking is not triggering — the point this
/// whole card exists to stop conflating). `gate.reason == 'cooldown'`
/// (Insta-Automate's `entity_scan/scrape/follow_trigger`, added alongside this
/// card) is the one signal that distinguishes them; everything else here is
/// derived from fields the heartbeat already carried.
enum _StatusKind { off, running, dayPaused, cooldown, blocked, polling }

_StatusKind _kindOf(FlowState state) {
  if (!state.switchOn) return _StatusKind.off;
  if (state.phase == 'running') return _StatusKind.running;
  if (state.phase == 'day_paused') return _StatusKind.dayPaused;
  if (state.gate.ok && state.gate.reason == 'cooldown' && state.nextTriggerAt != null) {
    return _StatusKind.cooldown;
  }
  if (!state.gate.ok) return _StatusKind.blocked;
  return _StatusKind.polling;
}

String _subtitleFor(_StatusKind kind, FlowState state) => switch (kind) {
  _StatusKind.off => 'skipped: switch OFF',
  _StatusKind.running => switch (state.gate.reason) {
    'message' => 'Running · triggered by message',
    'forced' => 'Running · forced',
    _ => 'Running',
  },
  _StatusKind.dayPaused => 'Paused for the day',
  _StatusKind.cooldown => 'Cooling down',
  _StatusKind.blocked => 'Waiting on condition',
  _StatusKind.polling => 'Checking…',
};

/// Falls back to Insta-Automate's own `Config._DEFAULTS` (meta.py) whenever
/// live config hasn't loaded yet — e.g. this card renders before Settings has
/// ever fetched it, or in a widget test with no config fixture. These are
/// display-only explainer text, not the authoritative value (the cooldown
/// ring's own countdown always comes from the real `next_trigger_at`), so a
/// stale fallback here is a cosmetic gap at worst, never a wrong action.
const _defaultTimingSeconds = {
  'INGEST_POLL_WAIT': 600,
  'SCAN_POLL_WAIT': 10,
  'SCAN_WAIT': 0,
  'CLASSIFY_POLL_WAIT': 10,
  'SCRAPE_WAIT': 600,
  'SCRAPE_BUFFER': 10,
  'FOLLOW_WAIT': 1200,
  'FOLLOW_BUFFER': 10,
};

String _humanizeSeconds(int seconds) {
  if (seconds <= 0) return '0s';
  if (seconds % 3600 == 0) return '${seconds ~/ 3600}h';
  if (seconds % 60 == 0) return '${seconds ~/ 60}m';
  return '${seconds}s';
}

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

  int _secondsFor(WidgetRef ref, String key) =>
      ref.watch(configControllerProvider).value?.values.limits[key] ?? _defaultTimingSeconds[key]!;

  /// Always shown, regardless of current state — the plain-language answer to
  /// "what actually makes this run," so the poll cadence and any mandatory
  /// cooldown never have to be inferred from a single ambiguous countdown.
  String _mechanismLine(WidgetRef ref) => switch (state.flow) {
    'entity-ingest' =>
      'Instant on a new channel message · '
          '${_humanizeSeconds(_secondsFor(ref, 'INGEST_POLL_WAIT'))} poll as fallback',
    'entity-scan' =>
      'Runs when entities are queued · checked every '
          '${_humanizeSeconds(_secondsFor(ref, 'SCAN_POLL_WAIT'))}',
    'entity-classify' =>
      'Runs when files land in scanned/ · checked every '
          '${_humanizeSeconds(_secondsFor(ref, 'CLASSIFY_POLL_WAIT'))}',
    'entity-scrape' =>
      'Runs when scraped+follow_queued is below the reserve · checked every '
          '${_humanizeSeconds(_secondsFor(ref, 'SCRAPE_BUFFER'))} · min '
          '${_humanizeSeconds(_secondsFor(ref, 'SCRAPE_WAIT'))} between runs',
    'entity-follow' =>
      'Runs when follow_queued has files · checked every '
          '${_humanizeSeconds(_secondsFor(ref, 'FOLLOW_BUFFER'))} · min '
          '${_humanizeSeconds(_secondsFor(ref, 'FOLLOW_WAIT'))} between runs',
    _ => '',
  };

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
    final kind = _kindOf(state);
    final gateText = state.gate.detail ?? (state.gate.ok ? null : state.gate.reason);
    final mechanismLine = _mechanismLine(ref);
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
                  _FlowStatusIndicator(kind: kind, state: state, observedAt: observedAt, color: _statusColor(theme)),
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
                          _subtitleFor(kind, state),
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
              const SizedBox(height: 10),
              Tooltip(
                message: mechanismLine,
                child: Text(
                  mechanismLine,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
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

/// A countdown ring only for [_StatusKind.cooldown] — the one wait that's a
/// real, deterministic "eligible again at X." Every other state (blocked on a
/// false condition, mid-poll, off, day-paused) renders a static icon instead,
/// so a number ticking to zero never implies a trigger that isn't actually
/// coming (the illusion the old single-ring design gave every flow).
class _FlowStatusIndicator extends StatelessWidget {
  const _FlowStatusIndicator({
    required this.kind,
    required this.state,
    required this.observedAt,
    required this.color,
  });

  final _StatusKind kind;
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

  IconData get _icon => switch (kind) {
    _StatusKind.running => Icons.play_arrow,
    _StatusKind.dayPaused => Icons.pause,
    _StatusKind.blocked => Icons.hourglass_empty,
    _StatusKind.polling => Icons.autorenew,
    _StatusKind.off || _StatusKind.cooldown => Icons.schedule,
  };

  Widget _iconBadge() => SizedBox(
    width: _size,
    height: _size,
    child: Container(
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.15)),
      child: Icon(_icon, color: color, size: 24),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (kind != _StatusKind.cooldown) return _iconBadge();

    final deadline = state.nextTriggerAt!;
    final remaining = deadline.difference(DateTime.now());
    if (remaining.isNegative) return _iconBadge();

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
