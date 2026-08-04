import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_snack_bar.dart';
import '../../core/config_models.dart';
import '../../core/flow_switch_confirm.dart';
import '../../core/theme/tokens.dart';
import '../../ui/status.dart';
import '../../ui/surfaces.dart';
import 'config_controller.dart';

/// The order the pipeline actually runs in, so the switches read as a pipeline
/// rather than an alphabetical list.
const _flowOrder = [
  'ENTITY_INGEST',
  'ENTITY_SCAN',
  'ENTITY_CLASSIFY',
  'ENTITY_SCRAPE',
  'ENTITY_FOLLOW',
];

class SwitchesTab extends ConsumerWidget {
  const SwitchesTab({super.key, required this.config});

  final ConfigResponse config;

  Future<void> _toggle(BuildContext context, WidgetRef ref, String key, bool value) async {
    if (!await confirmFlowSwitch(context, key, value)) return;

    try {
      await ref.read(configControllerProvider.notifier).applySwitch(key, value);
      if (context.mounted) {
        AppSnackBar.show(context, '$key ${value ? 'enabled' : 'disabled'}');
      }
    } on DioException {
      if (context.mounted) {
        AppSnackBar.show(context, 'Could not update $key', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final byName = {for (final key in config.schema) key.name: key};
    final enabledCount = _flowOrder.where((k) => config.values.switches[k] ?? false).length;

    final tokens = theme.tokens;

    return ListView(
      padding: EdgeInsets.all(tokens.space.lg),
      children: [
        Row(
          children: [
            Text('Flow triggers', style: theme.textTheme.titleLarge),
            SizedBox(width: tokens.space.sm),
            StatusChip(kind: StatusKind.neutral, label: '$enabledCount of ${_flowOrder.length} on', dense: true),
          ],
        ),
        SizedBox(height: tokens.space.xs),
        Text(
          'Switching a flow off stops it being triggered. Work already in progress finishes.',
          style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
        ),
        SizedBox(height: tokens.space.lg),
        for (final key in _flowOrder)
          Padding(
            padding: EdgeInsets.only(bottom: tokens.space.md),
            child: AppCard(
              padding: EdgeInsets.symmetric(horizontal: tokens.space.lg, vertical: tokens.space.xs),
              child: SwitchListTile(
                value: config.values.switches[key] ?? false,
                onChanged: (value) => _toggle(context, ref, key, value),
                title: Text(key, style: theme.textTheme.titleMedium),
                subtitle: Padding(
                  padding: EdgeInsets.only(top: tokens.space.xs),
                  child: Text(byName[key]?.help ?? ''),
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
      ],
    );
  }
}
