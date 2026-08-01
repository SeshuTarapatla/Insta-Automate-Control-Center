import 'package:flutter/material.dart';

import '../features/flows/flows_page.dart';
import '../features/placeholder_page.dart';
import '../features/services/services_page.dart';
import '../features/settings/settings_page.dart';
import 'connection_banner.dart';
import 'title_bar.dart';

const _flowsIndex = 1;
const _servicesIndex = 3;
const _settingsIndex = 6;

class _Destination {
  const _Destination(this.label, this.icon);
  final String label;
  final IconData icon;
}

const _destinations = [
  _Destination('Overview', Icons.dashboard_outlined),
  _Destination('Flows', Icons.account_tree_outlined),
  _Destination('Live', Icons.sensors_outlined),
  _Destination('Services', Icons.dns_outlined),
  _Destination('Library', Icons.photo_library_outlined),
  _Destination('Insights', Icons.insights_outlined),
  _Destination('Settings', Icons.settings_outlined),
];

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const TitleBar(),
          const Divider(height: 1),
          const ConnectionBanner(),
          Expanded(
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: _selected,
                  onDestinationSelected: (i) => setState(() => _selected = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        label: Text(d.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  // Rebuilt rather than kept alive: the agent's log ring is the
                  // source of truth for terminal output, so a pane that comes
                  // back replays from the server instead of holding state here.
                  child: switch (_selected) {
                    _flowsIndex => const FlowsPage(),
                    _servicesIndex => const ServicesPage(),
                    _settingsIndex => const SettingsPage(),
                    _ => PlaceholderPage(title: _destinations[_selected].label),
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
