import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_snack_bar.dart';
import '../../ui/feedback.dart';
import '../../core/file_opener.dart';
import '../../ui/page.dart';
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
            child: AppPage(
              title: 'Settings',
              leading: ConfigFileBar(path: config.path),
              tabs: const [
                AppTab(label: 'Flows'),
                AppTab(label: 'Limits'),
                AppTab(label: 'Queue'),
                AppTab(label: 'Devices'),
                AppTab(label: 'Ops'),
              ],
              body: TabBarView(
                children: [
                  SwitchesTab(config: config),
                  LimitsTab(config: config),
                  const QueueTab(),
                  const DevicesTab(),
                  const OpsTab(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
