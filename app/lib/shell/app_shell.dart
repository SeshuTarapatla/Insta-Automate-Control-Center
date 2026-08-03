import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/nav_state.dart';
import '../core/onboarding.dart';
import '../core/shortcuts_reference.dart';
import '../features/flows/flows_page.dart';
import '../features/insights/insights_page.dart';
import '../features/library/library_page.dart';
import '../features/live/live_page.dart';
import '../features/overview/overview_page.dart';
import '../features/services/services_page.dart';
import '../features/settings/settings_page.dart';
import 'connection_banner.dart';
import 'title_bar.dart';

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

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  // Guards against re-showing the welcome dialog on every rebuild once
  // `onboardingControllerProvider` resolves — same one-shot pattern
  // `live_page.dart`'s `_didInitialCatchUp` uses for the same reason (a
  // provider resolving is a rebuild trigger, not a one-time event on its
  // own).
  bool _checkedOnboarding = false;

  void _maybeShowOnboarding(bool hasSeen) {
    if (_checkedOnboarding || hasSeen) return;
    _checkedOnboarding = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showWelcomeDialog(context);
      ref.read(onboardingControllerProvider.notifier).markSeen();
    });
  }

  @override
  Widget build(BuildContext context) {
    // A provider, not local State (CP 7.3) — the Overview page's section
    // headers need to change the selected destination from outside this
    // widget, and the tray menu (also CP 7.3) needs to bring the window to
    // the front on whatever tab it was left on rather than resetting it.
    final selected = ref.watch(selectedNavIndexProvider);
    ref.watch(onboardingControllerProvider).whenData(_maybeShowOnboarding);

    return CallbackShortcuts(
      // The first app-wide binding (everything else is page-scoped) — still
      // reaches here from a focused text field the same way Ctrl+E does
      // (settings_page.dart's own comment on that), since shortcuts
      // propagate up the focus chain rather than being captured only at
      // the focused leaf.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.slash, shift: true): () => showShortcutsReference(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
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
                      selectedIndex: selected,
                      onDestinationSelected: (i) => ref.read(selectedNavIndexProvider.notifier).select(i),
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
                      // Rebuilt rather than kept alive: the agent's log ring is
                      // the source of truth for terminal output, so a pane that
                      // comes back replays from the server instead of holding
                      // state here.
                      child: switch (selected) {
                        flowsIndex => const FlowsPage(),
                        liveIndex => const LivePage(),
                        servicesIndex => const ServicesPage(),
                        libraryIndex => const LibraryPage(),
                        insightsIndex => const InsightsPage(),
                        settingsIndex => const SettingsPage(),
                        _ => const OverviewPage(),
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
