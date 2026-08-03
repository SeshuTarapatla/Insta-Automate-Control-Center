import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/scheduler_models.dart';
import '../core/service_models.dart';
import '../features/flows/flows_controller.dart';
import '../features/services/services_controller.dart';

/// The system tray icon (ARCHITECTURE §9, CP 7.3): quick service toggles and
/// a flow-phase glance without opening the window, a left-click show/hide,
/// and Quit — the only way to actually exit once the window's own close
/// button starts hiding to tray instead (see `window_lifecycle.dart`).
///
/// Threaded a `ProviderContainer` rather than reading providers through a
/// `BuildContext` — the tray icon and its native menu exist outside the
/// widget tree entirely, the same reason `main.dart` already needs raw
/// `windowManager` calls before `runApp`.
class AppTray with TrayListener {
  AppTray(this._container);

  final ProviderContainer _container;

  Future<void> init() async {
    trayManager.addListener(this);
    await trayManager.setIcon('assets/tray_icon.ico');
    await trayManager.setToolTip('Insta-Automate Control Center');
    await _rebuildMenu();
    _container.listen(flowsControllerProvider, (_, _) => _rebuildMenu());
    _container.listen(servicesControllerProvider, (_, _) => _rebuildMenu());
  }

  Future<void> _rebuildMenu() async {
    final flows = _container.read(flowsControllerProvider).value;
    final services = _container.read(servicesControllerProvider).value;

    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(label: 'Show Insta-Automate Control Center', onClick: (_) => _show()),
          MenuItem.separator(),
          if (flows != null && flows.flows.isNotEmpty) ...[
            for (final flow in flowOrder)
              if (flows.flows[flow] case final state?)
                MenuItem(
                  label: '${flowTitle[flow] ?? flow}: ${phaseLabel[state.phase] ?? state.phase}',
                  disabled: true,
                ),
            MenuItem.separator(),
          ],
          if (services != null && services.isNotEmpty) ...[
            for (final service in services) _serviceMenuItem(service),
            MenuItem.separator(),
          ],
          MenuItem(label: 'Quit', onClick: (_) => _quit()),
        ],
      ),
    );
  }

  MenuItem _serviceMenuItem(ServiceStatus service) {
    if (!service.isRunning) {
      return MenuItem(label: 'Start ${service.label}', onClick: (_) => _start(service));
    }
    if (service.canStop) {
      return MenuItem(label: 'Stop ${service.label}', onClick: (_) => _stop(service));
    }
    // Running but not ours to stop (external/adopted-without-takeover) — a
    // glance row, same as the flow phases above, not an action.
    return MenuItem(label: '${service.label}: running', disabled: true);
  }

  Future<void> _start(ServiceStatus service) =>
      _container.read(servicesControllerProvider.notifier).start(service.name);

  Future<void> _stop(ServiceStatus service) =>
      _container.read(servicesControllerProvider.notifier).stop(service.name);

  Future<void> _show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _toggleWindow() async {
    if (await windowManager.isVisible()) {
      await windowManager.hide();
    } else {
      await _show();
    }
  }

  Future<void> _quit() async {
    // `window_lifecycle.dart` sets this so the title bar's close button
    // hides to tray instead of exiting — Quit is the one path that means it
    // for real, so it has to undo that first.
    await windowManager.setPreventClose(false);
    await trayManager.destroy();
    await windowManager.close();
  }

  @override
  void onTrayIconMouseDown() => _toggleWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();
}
