import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_snack_bar.dart';
import '../../core/config_models.dart';
import '../../core/flow_switch_confirm.dart';
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

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Text('Flow triggers', style: theme.textTheme.titleLarge),
            const SizedBox(width: 12),
            Chip(
              label: Text('$enabledCount of ${_flowOrder.length} on'),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Switching a flow off stops it being triggered. Work already in progress finishes.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        for (final key in _flowOrder)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              margin: EdgeInsets.zero,
              child: SwitchListTile(
                value: config.values.switches[key] ?? false,
                onChanged: (value) => _toggle(context, ref, key, value),
                title: Text(key, style: theme.textTheme.titleMedium),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(byName[key]?.help ?? ''),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              ),
            ),
          ),
      ],
    );
  }
}
