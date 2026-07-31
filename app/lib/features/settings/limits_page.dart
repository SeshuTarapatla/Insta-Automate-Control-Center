import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_snack_bar.dart';
import '../../core/config_models.dart';
import '../../core/file_opener.dart';
import 'config_file_bar.dart';
import 'limits_controller.dart';
import 'limit_card.dart';

const _groupOrder = ['scan', 'scrape', 'follow'];
const _groupTitles = {'scan': 'Scan', 'scrape': 'Scrape', 'follow': 'Follow'};

class LimitsPage extends ConsumerWidget {
  const LimitsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<int>(externalConfigChangeProvider, (previous, next) {
      if (previous == null || next == previous) return;
      AppSnackBar.show(context, 'config.env changed externally — values refreshed.');
    });

    final configAsync = ref.watch(limitsControllerProvider);

    return configAsync.when(
      data: (config) => _LimitsBody(config: config),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Failed to load config: $error')),
    );
  }
}

class _LimitsBody extends StatelessWidget {
  const _LimitsBody({required this.config});

  final ConfigResponse config;

  @override
  Widget build(BuildContext context) {
    final byGroup = <String, List<ConfigKeySchema>>{};
    for (final key in config.schema) {
      if (key.type != 'int') continue;
      byGroup.putIfAbsent(key.group, () => []).add(key);
    }

    // Wrapping the whole body means Ctrl+E still fires while a limit's text
    // field holds focus — shortcuts propagate up the focus chain.
    return CallbackShortcuts(
      bindings: {ConfigFileBar.openIntentKey: () => FileOpener.openForEditing(config.path)},
      child: Focus(
        autofocus: true,
        child: _buildList(context, byGroup),
      ),
    );
  }

  Widget _buildList(BuildContext context, Map<String, List<ConfigKeySchema>> byGroup) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ConfigFileBar(path: config.path),
        const SizedBox(height: 28),
        for (final group in _groupOrder)
          if (byGroup[group] case final keys?) ...[
            Text(_groupTitles[group]!, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final schema in keys)
                  LimitCard(schema: schema, committedValue: config.values.limits[schema.name]!),
              ],
            ),
            const SizedBox(height: 32),
          ],
      ],
    );
  }
}
