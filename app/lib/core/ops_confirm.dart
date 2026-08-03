import 'package:flutter/material.dart';

/// The Ops panel's (CP 7.1) equivalent of `flow_switch_confirm.dart`'s
/// `confirmFlowSwitch` — same `showDialog<bool>` + Cancel/`FilledButton`
/// shape, reused rather than a new generic dialog widget since that's the
/// established pattern for "confirm before a consequential action" in this
/// app (there is no single shared dialog builder to call instead — D69).
Future<bool> confirmOpsAction(BuildContext context, String label, String consequence) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('$label?'),
      content: Text(consequence),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(label)),
      ],
    ),
  );
  return confirmed == true;
}
