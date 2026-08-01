import 'package:flutter/material.dart';

import '../../core/config_models.dart';
import 'limit_card.dart';

const _groupOrder = ['scan', 'scrape', 'follow', 'timing'];
const _groupTitles = {
  'scan': 'Scan',
  'scrape': 'Scrape',
  'follow': 'Follow',
  'timing': 'Timings (seconds) — how long each trigger waits',
};

class LimitsTab extends StatelessWidget {
  const LimitsTab({super.key, required this.config});

  final ConfigResponse config;

  @override
  Widget build(BuildContext context) {
    final byGroup = <String, List<ConfigKeySchema>>{};
    for (final key in config.schema) {
      if (key.type != 'int') continue;
      byGroup.putIfAbsent(key.group, () => []).add(key);
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
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
