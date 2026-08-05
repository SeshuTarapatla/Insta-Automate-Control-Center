// DESIGN_SYSTEM.md §8, THEMES.md §9 — the Appearance tab's four settings,
// persisted to `shared_preferences`. Mirrors `MutedTagsController`'s exact
// pattern (CP 6.3/CP 7.3's own precedent, `features/notifications/
// notification_controller.dart`) — there is no new persistence mechanism
// here, just a new set of keys.
import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'density.dart';
import 'registry.dart';
import 'tokens.dart';

/// THEMES.md §9 — "auto" reads the OS "Show animations" setting
/// (`ControlCenterApp`'s own `WidgetsBindingObserver`, since that's the
/// signal `MotionTokens.reduced` exists to honour); `always`/`never`
/// override it outright regardless of what Windows reports.
enum ReduceMotionSetting { auto, always, never }

/// THEMES.md §8 — Daylight/Swiss's light terminal, already cleared live
/// against a real streaming service (OBSERVED §6). `alwaysDark` is a real
/// supported preference some people just have (VS Code's own default for a
/// light-themed editor), not a correctness fallback for a legibility bug.
enum TerminalOverride { followTheme, alwaysDark }

@immutable
class ThemePrefs {
  const ThemePrefs({required this.themeId, required this.density, required this.reduceMotion, required this.terminalOverride});

  final ThemeId themeId;
  final Density density;
  final ReduceMotionSetting reduceMotion;
  final TerminalOverride terminalOverride;

  // Default on first launch stays Classic (THEMES.md §1, confirmed by the
  // user 2026-08-04) — an existing app is unchanged until someone actually
  // opens Appearance and picks something else.
  static const initial = ThemePrefs(
    themeId: ThemeId.classic,
    density: Density.comfortable,
    reduceMotion: ReduceMotionSetting.auto,
    terminalOverride: TerminalOverride.followTheme,
  );

  ThemePrefs copyWith({ThemeId? themeId, Density? density, ReduceMotionSetting? reduceMotion, TerminalOverride? terminalOverride}) => ThemePrefs(
    themeId: themeId ?? this.themeId,
    density: density ?? this.density,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    terminalOverride: terminalOverride ?? this.terminalOverride,
  );
}

class ThemeController extends Notifier<ThemePrefs> {
  static const _themeKey = 'appearance_theme_id';
  static const _densityKey = 'appearance_density';
  static const _reduceMotionKey = 'appearance_reduce_motion';
  static const _terminalOverrideKey = 'appearance_terminal_override';

  @override
  ThemePrefs build() {
    // A synchronous default so the very first frame never flashes an
    // arbitrary theme — `MutedTagsController`'s equivalent gap is a bare
    // notification list; a wrong theme for one frame is far more visible
    // than that. The real, persisted value loads a moment later.
    _load();
    return ThemePrefs.initial;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final loaded = ThemePrefs(
      themeId: _enumFromName(ThemeId.values, prefs.getString(_themeKey), ThemeId.classic),
      density: _enumFromName(Density.values, prefs.getString(_densityKey), Density.comfortable),
      reduceMotion: _enumFromName(ReduceMotionSetting.values, prefs.getString(_reduceMotionKey), ReduceMotionSetting.auto),
      terminalOverride: _enumFromName(TerminalOverride.values, prefs.getString(_terminalOverrideKey), TerminalOverride.followTheme),
    );
    state = loaded;
    await _applyNativeEffect(loaded.themeId);
  }

  Future<void> setTheme(ThemeId id) async {
    // Theme and density are two fully independent, independently-persisted
    // settings (D106 — Command Deck previously nudged density to `compact`
    // on selection, per THEMES.md §2's "ships compact by default"; removed
    // at the user's explicit request, since a manually-set density should
    // never move again until the user changes it themselves, regardless of
    // which theme they switch to).
    state = state.copyWith(themeId: id);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, id.name);
    await _applyNativeEffect(id);
  }

  Future<void> setDensity(Density density) async {
    state = state.copyWith(density: density);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_densityKey, density.name);
  }

  Future<void> setReduceMotion(ReduceMotionSetting setting) async {
    state = state.copyWith(reduceMotion: setting);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_reduceMotionKey, setting.name);
  }

  Future<void> setTerminalOverride(TerminalOverride override) async {
    state = state.copyWith(terminalOverride: override);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_terminalOverrideKey, override.name);
  }

  /// THEMES.md §4 — "switching to or from Mica calls native
  /// `Window.setEffect(...)`, which is a native window-level change and
  /// cannot animate." Every other theme is fully opaque (`surface.canvas`
  /// alpha 1.0, DESIGN_SYSTEM §7), so the compositor material itself only
  /// ever needs to be Mica — only the `dark` flag (which can't animate
  /// either) needs to track the active theme's brightness. Colors and
  /// geometry underneath keep sweeping via `AppTokens.lerp` regardless.
  Future<void> _applyNativeEffect(ThemeId id) async {
    final brightness = buildTokensFor(id).brightness;
    await Window.setEffect(effect: WindowEffect.mica, dark: brightness == Brightness.dark);
  }
}

T _enumFromName<T extends Enum>(List<T> values, String? name, T fallback) {
  if (name == null) return fallback;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

final themeControllerProvider = NotifierProvider<ThemeController, ThemePrefs>(ThemeController.new);
