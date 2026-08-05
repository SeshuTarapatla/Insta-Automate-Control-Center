import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// SCREENS.md §0 — icons-only nav rail, `Ctrl+B`, persisted the same way
/// `ThemeController`'s appearance settings are: a synchronous default so the
/// first frame never flashes the wrong width, the real persisted value
/// loading a moment later.
class NavRailCollapsedNotifier extends Notifier<bool> {
  static const _prefsKey = 'nav_rail_collapsed';

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_prefsKey);
    if (saved != null) state = saved;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, state);
  }
}

final navRailCollapsedProvider = NotifierProvider<NavRailCollapsedNotifier, bool>(NavRailCollapsedNotifier.new);
