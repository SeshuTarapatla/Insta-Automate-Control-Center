import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/flows/flows_controller.dart';
import '../features/settings/config_controller.dart';
import 'app_snack_bar.dart';
import 'scheduler_models.dart';

// entity-scan needs a real queued entity to supply as a parameter;
// entity-follow needs real files in follow_queued/ to iterate — force
// can't invent either, so a no_work gate on these two stays a genuine
// dead end even when forced (D29).
const _hardNoWorkFlows = {'entity-scan', 'entity-follow'};

/// Shared by `FlowCard` (Flows screen) and the Live screen's header — same
/// confirmation dialog, same command, same optimistic feedback, wherever a
/// manual trigger starts from. Labeled "Trigger now" in the UI — a manual
/// trigger only ever means "run it regardless of its condition," so this is
/// now the *only* manual-trigger action (the softer "Run now"/"Skip wait",
/// which only ended an in-progress wait early without bypassing the gate,
/// was removed per your own framing). The wire command is still `force_run`
/// (unchanged pipeline semantics — this function name stays too, since
/// renaming it would be pure churn for a UI-label change).
Future<void> forceRunFlow(BuildContext context, WidgetRef ref, FlowState state) async {
  final content = switch (state.gate) {
    FlowGate(ok: true) =>
      'Triggers ${flowTitle[state.flow]} immediately, ignoring its normal schedule, '
          'switch, and daily limits.',
    FlowGate(reason: 'no_work') when _hardNoWorkFlows.contains(state.flow) =>
      'Nothing is currently queued for ${flowTitle[state.flow]} — Trigger now bypasses timing '
          'and limits, but there\'s no queued entity to act on, so this will complete without '
          'doing anything.',
    FlowGate(:final detail, :final reason) => 'This triggers it despite: ${detail ?? reason}',
  };
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Trigger ${flowTitle[state.flow]} now?'),
      content: Text(content),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Trigger now')),
      ],
    ),
  );
  if (confirmed != true) return;
  await ref.read(flowsControllerProvider.notifier).sendCommand(state.flow, 'force_run');
  if (context.mounted) {
    AppSnackBar.show(context, '${flowTitle[state.flow]}: triggered');
  }
}

/// Follow-only manual override (D86): keeps entity-follow processing the
/// queue — real follows and skips (already requested, not found) alike —
/// until scraped+follow_queued drops to the backpressure reserve target
/// (FOLLOW × SCRAPE_RESERVE_FACTOR), not just FOLLOW_BATCH successful
/// follows. Bypasses the daily FOLLOW limit the same way Trigger now does,
/// since backpressure and the daily cap are most likely to be hit together —
/// your own call, confirmed before building this. Shared by `FlowCard` and
/// the Live screen's header, same as `forceRunFlow`.
Future<void> reduceReserveFlow(BuildContext context, WidgetRef ref, FlowState state) async {
  final limits = ref.read(configControllerProvider).value?.values.limits;
  final follow = limits?['FOLLOW'] ?? 60;
  final factor = limits?['SCRAPE_RESERVE_FACTOR'] ?? 3;
  final target = follow * factor;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Reduce reserve?'),
      content: Text(
        'Keeps Follow running — real follows and skips (already requested, not found) alike — '
        'until scraped+follow_queued drops to $target (FOLLOW × SCRAPE_RESERVE_FACTOR), instead '
        "of stopping at FOLLOW_BATCH successful follows. This bypasses today's daily follow "
        'limit if needed to get there, so it can perform more real follows than the normal '
        'daily cap in one run.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Reduce reserve'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await ref.read(flowsControllerProvider.notifier).sendCommand(state.flow, 'reduce_reserve');
  if (context.mounted) {
    AppSnackBar.show(context, '${flowTitle[state.flow]}: reduce reserve queued');
  }
}

/// Cancels a run genuinely in progress (D69) - added after a real incident
/// where a bad flow run had no way to be stopped from the control center at
/// all short of uninstalling the whole release. Only meaningful while
/// `state.phase == 'running'` and a real run id exists; callers should hide
/// the action entirely otherwise rather than show it disabled.
Future<void> stopFlowRun(BuildContext context, WidgetRef ref, FlowState state) async {
  final runId = state.lastRun?.id;
  if (runId == null) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Stop ${flowTitle[state.flow]}?'),
      content: const Text(
        'Cancels the run in progress. Prefect tears down its infrastructure shortly '
        'after — not instant.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton.tonal(onPressed: () => Navigator.of(context).pop(true), child: const Text('Stop')),
      ],
    ),
  );
  if (confirmed != true) return;
  await ref.read(flowsControllerProvider.notifier).cancelRun(runId);
  if (context.mounted) {
    AppSnackBar.show(context, '${flowTitle[state.flow]}: stop requested');
  }
}
