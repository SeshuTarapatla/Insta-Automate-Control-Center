import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:window_manager/window_manager.dart';

import '../core/connection_state.dart';
import '../core/dependency_models.dart';
import '../core/shortcuts_reference.dart';
import '../core/theme/tokens.dart';
import '../core/window_work_area.dart';
import '../features/notifications/notification_center.dart';
import '../features/services/dependencies_controller.dart';
import '../ui/icons.dart';
import '../ui/overlays.dart';
import '../ui/status.dart';

class TitleBar extends ConsumerWidget {
  const TitleBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Row(
                children: [
                  SizedBox(width: tokens.space.sm),
                  AppIcon(AppIcons.brand, size: IconSize.sm, color: theme.colorScheme.primary),
                  SizedBox(width: tokens.space.xs),
                  Text(
                    'Insta-Automate Control Center',
                    style: theme.textTheme.labelLarge,
                  ),
                  SizedBox(width: tokens.space.xl),
                  const _StatusCluster(),
                ],
              ),
            ),
          ),
          IconButton(
            // The command palette itself is V2.12's scope (SCREENS.md §8) —
            // this checkpoint only places the discoverable affordance
            // (SCREENS.md §0), disabled rather than wired to a dead action.
            tooltip: 'Command palette — coming soon',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: AppIcon(AppIcons.command, size: IconSize.sm),
            onPressed: null,
          ),
          IconButton(
            tooltip: 'Keyboard shortcuts  (?)',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: AppIcon(AppIcons.help, size: IconSize.sm),
            onPressed: () => showShortcutsReference(context),
          ),
          const NotificationCenter(),
          const _WindowButtons(),
        ],
      ),
    );
  }
}

/// SCREENS.md §0 — five `StatusDot`s replacing the old single text chip
/// (`'Agent: connected'`), each with a rich tooltip naming the component and
/// its latency. Reads exactly the two providers the plan calls out —
/// `connectionProvider` for the agent itself, `dependenciesControllerProvider`
/// for the other four — no new agent endpoint.
class _StatusCluster extends ConsumerWidget {
  const _StatusCluster();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).tokens;
    final connection = ref.watch(connectionProvider);
    final dependencies = ref.watch(dependenciesControllerProvider).value;

    Dependency? dep(String key) => dependencies?.items.where((d) => d.key == key).firstOrNull;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _agentDot(connection),
        SizedBox(width: tokens.space.sm),
        _depDot('k3s', dep('k3s')),
        SizedBox(width: tokens.space.sm),
        _depDot('Postgres', dep('postgres')),
        SizedBox(width: tokens.space.sm),
        _prefectDot(dep('prefect-server'), dep('prefect-pool')),
        SizedBox(width: tokens.space.sm),
        _depDot('Phone', dep('adb-device')),
      ],
    );
  }
}

StatusKind _kindOf(DependencyLevel level) => switch (level) {
  DependencyLevel.ok => StatusKind.good,
  DependencyLevel.warn => StatusKind.warn,
  DependencyLevel.fail => StatusKind.bad,
};

Widget _statusDot({required StatusKind kind, required String title, required String detail, bool pulsing = false}) {
  return AppTooltip(
    rich: true,
    title: title,
    message: detail,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: StatusDot(kind: kind, pulsing: pulsing, size: 9),
    ),
  );
}

Widget _agentDot(AgentConnection connection) {
  final (kind, detail) = switch (connection) {
    AgentConnection.connected => (StatusKind.good, 'Connected'),
    AgentConnection.connecting => (StatusKind.info, 'Connecting…'),
    AgentConnection.disconnected => (StatusKind.bad, 'Disconnected'),
  };
  return _statusDot(kind: kind, title: 'Agent', detail: detail, pulsing: connection == AgentConnection.connecting);
}

Widget _depDot(String title, Dependency? dep) {
  if (dep == null) return _statusDot(kind: StatusKind.neutral, title: title, detail: 'Checking…');
  return _statusDot(kind: _kindOf(dep.level), title: title, detail: '${dep.detail}\n${dep.latencyMs.round()}ms');
}

Widget _prefectDot(Dependency? server, Dependency? pool) {
  if (server == null && pool == null) return _statusDot(kind: StatusKind.neutral, title: 'Prefect', detail: 'Checking…');

  final levels = <DependencyLevel>[
    if (server != null) server.level,
    if (pool != null) pool.level,
  ];
  final worst = levels.contains(DependencyLevel.fail)
      ? DependencyLevel.fail
      : levels.contains(DependencyLevel.warn)
      ? DependencyLevel.warn
      : DependencyLevel.ok;

  final detail = [
    if (server != null) 'Server: ${server.detail}',
    if (pool != null) 'Work pool: ${pool.detail}',
  ].join('\n');

  return _statusDot(kind: _kindOf(worst), title: 'Prefect', detail: detail);
}

/// Maximize is faked via `setBounds` to the monitor's real work area instead
/// of `windowManager.maximize()`. The native Win32 maximize state visibly
/// glitches this app's custom title bar buttons — Windows redraws its own
/// caption chrome underneath/over the custom-drawn icons only in that state
/// (screenshot-confirmed: doubled icons, maximized only, restored is clean).
/// Staying in "restored" but sized to the work area sidesteps it entirely.
/// Known gap: OS-level maximize gestures that bypass this button (Win+Up,
/// dragging to the top edge, the taskbar's own right-click menu) still call
/// real maximize and can still glitch — there's no way to intercept those
/// from Dart without native platform-channel work.
class _WindowButtons extends StatefulWidget {
  const _WindowButtons();

  @override
  State<_WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<_WindowButtons> with WindowListener {
  bool _maximized = false;
  Rect? _restoredBounds;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  Future<void> _toggle() async {
    if (_maximized) {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else if (_restoredBounds != null) {
        await windowManager.setBounds(_restoredBounds);
      }
      setState(() => _maximized = false);
      return;
    }

    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final workArea = currentMonitorWorkArea(devicePixelRatio);
    if (workArea == null) {
      // Native lookup failed — real maximize is a worse-looking fallback
      // but a working one.
      await windowManager.maximize();
      return;
    }

    _restoredBounds = await windowManager.getBounds();
    await windowManager.setBounds(workArea);
    setState(() => _maximized = true);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _WindowButton(glyph: AppIcons.windowMinimize, onPressed: windowManager.minimize),
        _WindowButton(
          glyph: _maximized ? AppIcons.windowRestore : AppIcons.windowMaximize,
          onPressed: _toggle,
        ),
        _WindowButton(glyph: AppIcons.windowClose, onPressed: windowManager.close),
      ],
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({required this.glyph, required this.onPressed});

  final PhosphorIconData Function(PhosphorIconsStyle) glyph;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(iconSize: 16, icon: AppIcon(glyph, size: IconSize.sm), onPressed: onPressed),
    );
  }
}
