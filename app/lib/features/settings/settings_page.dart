import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_snack_bar.dart';
import '../../core/async_state_view.dart';
import '../../core/file_opener.dart';
import 'config_controller.dart';
import 'config_file_bar.dart';
import 'devices_tab.dart';
import 'limits_tab.dart';
import 'ops_tab.dart';
import 'queue_tab.dart';
import 'switches_tab.dart';

/// Everything backed by config.env, in one place: the file itself, the five
/// flow switches, the daily limits, and the shared priority queue.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<int>(externalConfigChangeProvider, (previous, next) {
      if (previous == null || next == previous) return;
      AppSnackBar.show(context, 'config.env changed externally — values refreshed.');
    });

    final configAsync = ref.watch(configControllerProvider);

    return configAsync.stateView(
      describeError: (error) => 'Failed to load config: $error',
      onRetry: () => ref.invalidate(configControllerProvider),
      data: (config) => CallbackShortcuts(
        // At this level Ctrl+E still fires while a limit's text field holds
        // focus — shortcuts propagate up the focus chain.
        bindings: {ConfigFileBar.openIntentKey: () => FileOpener.openForEditing(config.path)},
        child: Focus(
          autofocus: true,
          child: DefaultTabController(
            length: 5,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: ConfigFileBar(path: config.path),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: TabBar(
                    tabs: [
                      Tab(text: 'Flows'),
                      Tab(text: 'Limits'),
                      Tab(text: 'Queue'),
                      Tab(text: 'Devices'),
                      Tab(text: 'Ops'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      SwitchesTab(config: config),
                      LimitsTab(config: config),
                      const QueueTab(),
                      const DevicesTab(),
                      const OpsTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
