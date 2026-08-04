import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../core/connection_state.dart';
import '../core/shortcuts_reference.dart';
import '../core/theme/tokens.dart';
import '../core/window_work_area.dart';
import '../features/notifications/notification_center.dart';

class TitleBar extends ConsumerWidget {
  const TitleBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionProvider);
    final theme = Theme.of(context);

    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(
                    Icons.hub_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Insta-Automate Control Center',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(width: 20),
                  _StatusChip(status: status),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Keyboard shortcuts  (?)',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.help_outline),
            onPressed: () => showShortcutsReference(context),
          ),
          const NotificationCenter(),
          const _WindowButtons(),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final AgentConnection status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final (Color color, String label) = switch (status) {
      AgentConnection.connected => (tokens.status.good.fg, 'Agent: connected'),
      AgentConnection.connecting => (tokens.status.info.fg, 'Agent: connecting'),
      AgentConnection.disconnected => (tokens.status.bad.fg, 'Agent: disconnected'),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
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
        _WindowButton(icon: Icons.remove, onPressed: windowManager.minimize),
        _WindowButton(
          icon: _maximized ? Icons.filter_none : Icons.crop_square,
          onPressed: _toggle,
        ),
        _WindowButton(icon: Icons.close, onPressed: windowManager.close),
      ],
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({required this.icon, required this.onPressed});

  final IconData icon;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(iconSize: 16, icon: Icon(icon), onPressed: onPressed),
    );
  }
}
