// SCREENS.md §2 / V2.6 — one pipeline node: a horizontal strip carrying
// status, name, state, inline gate reason, today's counters and actions all
// in one row, replacing the old five-disconnected-cards `Wrap` (AUDIT §13).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_snack_bar.dart';
import '../../core/file_opener.dart';
import '../../core/flow_switch_confirm.dart';
import '../../core/force_run.dart';
import '../../core/nav_state.dart';
import '../../core/scheduler_models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import '../../ui/icons.dart';
import '../../ui/layout.dart';
import '../../ui/motion.dart';
import '../../ui/overlays.dart';
import '../../ui/status.dart';
import '../../ui/surfaces.dart';
import '../../ui/text.dart';
import '../live/live_controller.dart';
import '../settings/config_controller.dart';
import 'flow_status.dart';
import 'flows_controller.dart';

/// Prefect's own UI already has the real logs for a run; CP 4.1's in-app log
/// viewer doesn't exist yet, so "jump to its logs" opens this instead.
String _prefectRunUrl(String runId) => 'http://localhost:4200/flow-runs/flow-run/$runId';

/// Which node's accordion is open — at most one at a time (SCREENS.md §2:
/// "One node open at a time").
class ExpandedFlowNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void toggle(String flow) => state = state == flow ? null : flow;
}

final expandedFlowProvider = NotifierProvider<ExpandedFlowNotifier, String?>(ExpandedFlowNotifier.new);

class FlowNode extends ConsumerWidget {
  const FlowNode({super.key, required this.state});

  final FlowState state;

  Future<void> _toggleSwitch(BuildContext context, WidgetRef ref, bool value) async {
    final key = flowSwitchKey(state.flow);
    if (!await confirmFlowSwitch(context, key, value)) return;
    try {
      await ref.read(configControllerProvider.notifier).applySwitch(key, value);
    } on DioException {
      if (context.mounted) AppSnackBar.show(context, 'Could not update $key', isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(flowsTickProvider);
    ref.watch(pendingCommandProvider);
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final observedAt = ref.watch(flowsControllerProvider.notifier).observedAtFor(state.flow);
    final kind = flowStatusKindOf(state);
    final expanded = ref.watch(expandedFlowProvider) == state.flow;
    // Optimistic feedback only - the agent's queue/heartbeat round trip is
    // fast, but the worker actually picking up the run can lag a few
    // seconds, long enough for an impatient second click on Trigger now.
    final pending = ref.read(pendingCommandProvider.notifier).isPending(state.flow);

    final gateText = state.gate.detail ?? (state.gate.ok ? null : state.gate.reason);
    final mechanismLine = flowMechanismLine(ref, state.flow);
    final detailLine = flowDetailLine(ref, kind, state);

    final remaining = kind == FlowStatusKind.cooldown && state.nextTriggerAt != null
        ? state.nextTriggerAt!.difference(DateTime.now())
        : null;
    final label = remaining != null && !remaining.isNegative
        ? '${flowStatusLabel(kind, state)} ${formatFlowCountdown(remaining)}'
        : flowStatusLabel(kind, state);

    return Stack(
      children: [
        AppCard(
          accentEdge: flowAccent(kind),
          onTap: () => ref.read(expandedFlowProvider.notifier).toggle(state.flow),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _NodeIcon(kind: kind, color: _statusColor(tokens, state)),
                  SizedBox(width: tokens.space.sm),
                  SizedBox(
                    width: 96,
                    child: Text(
                      (flowTitle[state.flow] ?? state.flow).toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(letterSpacing: 0.6),
                    ),
                  ),
                  // `Expanded`, not `Flexible` — a `Flexible` label shrinks
                  // to its own text width, so everything after it (switch,
                  // info, overflow menu) shifts left/right with every row's
                  // label length instead of lining up in a straight column.
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: kind == FlowStatusKind.blocked ? tokens.status.warn.fg : tokens.content.secondary,
                      ),
                    ),
                  ),
                  SizedBox(width: tokens.space.sm),
                  Switch(value: state.switchOn, onChanged: (value) => _toggleSwitch(context, ref, value)),
                  SizedBox(width: tokens.space.xs),
                  // The same warn amber as the accent edge and the label
                  // above, not a harsher error red — "blocked on a false
                  // condition" is a normal operating state this pipeline
                  // sits in every day, not a failure.
                  gateText == null
                      ? AppTooltip(
                          rich: true,
                          message: mechanismLine,
                          child: AppIcon(AppIcons.info, size: IconSize.sm, color: tokens.content.secondary),
                        )
                      : AppTooltip(
                          rich: true,
                          title: mechanismLine,
                          message: gateText,
                          monoBody: true,
                          child: AppIcon(
                            AppIcons.info,
                            size: IconSize.sm,
                            color: !state.gate.ok ? tokens.status.warn.fg : tokens.content.secondary,
                          ),
                        ),
                  SizedBox(width: tokens.space.xs),
                  // Always reserved, even with nothing to show — an absent
                  // overflow menu on some rows (no `lastRun` yet) and not
                  // others is exactly what shifted the switch column
                  // left/right per row before this fix.
                  SizedBox(
                    width: 28,
                    child: state.lastRun == null ? null : _NodeOverflowMenu(runId: state.lastRun!.id),
                  ),
                ],
              ),
              SizedBox(height: tokens.space.xs),
              Padding(
                padding: EdgeInsets.only(left: flowNodeIconGutter + tokens.space.sm),
                child: Text(
                  detailLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: kind == FlowStatusKind.blocked ? tokens.status.warn.fg : tokens.content.secondary,
                  ),
                ),
              ),
              if (pending) ...[
                SizedBox(height: tokens.space.sm),
                Padding(
                  padding: EdgeInsets.only(left: flowNodeIconGutter + tokens.space.sm),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary),
                      ),
                      SizedBox(width: tokens.space.sm),
                      Flexible(
                        child: Text(
                          'Command sent — waiting for it to take effect…',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                SizedBox(height: tokens.space.sm),
                // Right-aligned, matching the switch column above it —
                // SCREENS.md §2's mockup sits the action row under the
                // status/switch side, not flush left under the icon gutter.
                // Bypasses `ButtonGroup` (no alignment param) for a bounded
                // `SizedBox` + `Wrap(alignment: end)` instead — a bare `Row`
                // here gives the Wrap unbounded width, so it never actually
                // wraps and overflows instead (caught by the entity-follow
                // three-button regression test at a narrow width).
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: tokens.space.sm,
                    runSpacing: tokens.space.sm,
                    children: _buttons(context, ref, state),
                  ),
                ),
              ],
              AnimatedReveal(
                visible: expanded,
                child: Padding(
                  padding: EdgeInsets.only(left: flowNodeIconGutter + tokens.space.sm, top: tokens.space.sm),
                  child: _FlowNodeExpansion(state: state, mechanismLine: mechanismLine, gateText: gateText),
                ),
              ),
            ],
          ),
        ),
        if (kind == FlowStatusKind.cooldown && state.nextTriggerAt != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _CooldownProgressLine(
              deadline: state.nextTriggerAt!,
              observedAt: observedAt,
              color: flowAccent(kind).fg(tokens),
              radius: tokens.geometry.radiusMd,
            ),
          ),
      ],
    );
  }

  static Color _statusColor(AppTokens tokens, FlowState state) {
    if (!state.switchOn) return tokens.content.secondary;
    if (state.phase == 'running') return tokens.status.good.fg;
    if (!state.gate.ok) return tokens.status.warn.fg;
    return tokens.status.info.fg;
  }

  // A manual trigger only ever means "run it now, regardless of its
  // condition" (D88) — "Trigger now" is always offered. "Reduce reserve" is
  // follow-only (D86); "Stop" only while a real run is in progress (D69).
  static List<Widget> _buttons(BuildContext context, WidgetRef ref, FlowState state) => [
    AppButton(label: 'Trigger now', onPressed: () => forceRunFlow(context, ref, state)),
    if (state.flow == 'entity-follow')
      AppButton(label: 'Reduce reserve', onPressed: () => reduceReserveFlow(context, ref, state)),
    if (state.phase == 'running' && state.lastRun != null)
      AppButton(label: 'Stop', tone: ButtonTone.danger, onPressed: () => stopFlowRun(context, ref, state)),
  ];
}

class _NodeIcon extends StatelessWidget {
  const _NodeIcon({required this.kind, required this.color});

  final FlowStatusKind kind;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const size = 32.0;
    return SizedBox(
      width: flowNodeIconGutter,
      height: size,
      child: Center(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.15)),
          child: AppIcon(flowStatusIcon(kind), color: color, size: IconSize.sm),
        ),
      ),
    );
  }
}

/// A thin determinate line along the node's bottom edge — the cooldown-only
/// countdown (D84's central point, carried into the node layout per
/// SCREENS.md §2): "the countdown ring only for cooldown," now a compact
/// inline `mm:ss` next to the status word (see `FlowNode.label` above) plus
/// this progress line, instead of a 56px ring. Re-keyed on the deadline so a
/// re-target (edited wait, skip_wait) starts a fresh animation rather than
/// tweening across a jump — same technique the old ring used.
class _CooldownProgressLine extends StatelessWidget {
  const _CooldownProgressLine({
    required this.deadline,
    required this.observedAt,
    required this.color,
    required this.radius,
  });

  final DateTime deadline;
  final DateTime? observedAt;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining.isNegative) return const SizedBox.shrink();

    final total = observedAt == null ? remaining : deadline.difference(observedAt!);
    final fraction = total.inMilliseconds <= 0
        ? 0.0
        : (remaining.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
      child: SizedBox(
        height: 3,
        child: TweenAnimationBuilder<double>(
          key: ValueKey(deadline),
          tween: Tween(begin: fraction, end: 0.0),
          duration: remaining,
          curve: Curves.linear,
          builder: (context, value, _) => LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            color: color,
            backgroundColor: color.withValues(alpha: 0.15),
          ),
        ),
      ),
    );
  }
}

/// "View logs" moves here from a permanent button (D93's card had one) to
/// free the row — SCREENS.md §2. Only rendered when a `lastRun` exists to
/// link to.
class _NodeOverflowMenu extends StatelessWidget {
  const _NodeOverflowMenu({required this.runId});

  final String runId;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    return AppMenu(
      trigger: AppMenuTrigger.tap,
      items: [
        AppMenuItem(
          label: 'View logs',
          icon: Icons.open_in_new,
          onTap: () => FileOpener.openUrl(_prefectRunUrl(runId)),
        ),
      ],
      child: Tooltip(
        message: 'More actions',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: AppIcon(AppIcons.moreVertical, size: IconSize.sm, color: tokens.content.secondary),
          ),
        ),
      ),
    );
  }
}

/// The accordion content (SCREENS.md §2 "Expansion"): last run state +
/// duration + run id, today's full counters, the raw gate string, View logs,
/// and Open in Live — the detail D93 had to hide behind a hover now lives
/// here, available on click.
class _FlowNodeExpansion extends ConsumerWidget {
  const _FlowNodeExpansion({required this.state, required this.mechanismLine, required this.gateText});

  final FlowState state;
  final String mechanismLine;
  final String? gateText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final lastRun = state.lastRun;
    final today = flowTodayLine(state);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppDivider(),
        SizedBox(height: tokens.space.sm),
        KeyValueList(
          rows: [
            MetricRow(
              label: 'Mechanism',
              value: Text(mechanismLine, style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary)),
            ),
            MetricRow(
              label: 'Last run',
              value: Text(
                lastRun == null
                    ? 'No run yet this session'
                    : '${lastRun.state}${lastRun.durationS != null ? ' · ${lastRun.durationS!.round()}s' : ''} · ${lastRun.id}',
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (today != null) MetricRow(label: 'Today', value: NumericText(today, role: TextRole.caption)),
            MetricRow(
              label: 'Gate',
              value: MonoText(gateText ?? 'ok — no blocking condition', role: TextRole.caption),
            ),
          ],
        ),
        SizedBox(height: tokens.space.sm),
        ButtonGroup(
          children: [
            if (lastRun != null)
              AppButton(label: 'View logs', onPressed: () => FileOpener.openUrl(_prefectRunUrl(lastRun.id))),
            AppButton(
              label: 'Open in Live',
              onPressed: () {
                ref.read(selectedFlowProvider.notifier).select(state.flow);
                ref.read(selectedNavIndexProvider.notifier).select(liveIndex);
              },
            ),
          ],
        ),
      ],
    );
  }
}
