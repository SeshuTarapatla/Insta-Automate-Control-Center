import 'package:flutter_riverpod/flutter_riverpod.dart';

// Shared with `overview_page.dart`'s section headers, which need to jump to
// a destination without importing `app_shell.dart` itself (that would be
// circular — `AppShell` is what builds `OverviewPage`).
const overviewIndex = 0;
const flowsIndex = 1;
const liveIndex = 2;
const servicesIndex = 3;
const libraryIndex = 4;
const insightsIndex = 5;
const settingsIndex = 6;

/// Which nav-rail destination `AppShell` shows — pulled out of its local
/// `State` (CP 7.3) so the new Overview page's section headers can jump to
/// the matching full screen without `AppShell` handing down a callback.
class SelectedNavIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

final selectedNavIndexProvider = NotifierProvider<SelectedNavIndexNotifier, int>(SelectedNavIndexNotifier.new);
