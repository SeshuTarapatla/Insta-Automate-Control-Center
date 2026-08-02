import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/flows/flows_controller.dart';
import 'app_snack_bar.dart';
import 'scheduler_models.dart';

// entity-scan needs a real queued entity to supply as a parameter;
// entity-follow needs real files in follow_queued/ to iterate — force
// can't invent either, so a no_work gate on these two stays a genuine
// dead end even when forced (D29).
const _hardNoWorkFlows = {'entity-scan', 'entity-follow'};

/// Shared by `FlowCard` (Flows screen) and the Live screen's header — same
/// confirmation dialog, same command, same optimistic feedback, wherever a
/// force-run action starts from.
Future<void> forceRunFlow(BuildContext context, WidgetRef ref, FlowState state) async {
  final content = switch (state.gate) {
    FlowGate(ok: true) =>
      'Triggers ${flowTitle[state.flow]} immediately, ignoring its normal schedule, '
          'switch, and daily limits.',
    FlowGate(reason: 'no_work') when _hardNoWorkFlows.contains(state.flow) =>
      'Nothing is currently queued for ${flowTitle[state.flow]} — Force run bypasses timing '
          'and limits, but there\'s no queued entity to act on, so this will complete without '
          'doing anything.',
    FlowGate(:final detail, :final reason) => 'This triggers it despite: ${detail ?? reason}',
  };
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Force run ${flowTitle[state.flow]}?'),
      content: Text(content),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Force run')),
      ],
    ),
  );
  if (confirmed != true) return;
  await ref.read(flowsControllerProvider.notifier).sendCommand(state.flow, 'force_run');
  if (context.mounted) {
    AppSnackBar.show(context, '${flowTitle[state.flow]}: force run queued');
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
