import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../core/connection_state.dart';

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
    final (Color color, String label) = switch (status) {
      AgentConnection.connected => (Colors.green, 'Agent: connected'),
      AgentConnection.connecting => (Colors.orange, 'Agent: connecting'),
      AgentConnection.disconnected => (Colors.red, 'Agent: disconnected'),
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
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _WindowButtons extends StatelessWidget {
  const _WindowButtons();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _WindowButton(icon: Icons.remove, onPressed: windowManager.minimize),
        _WindowButton(
          icon: Icons.crop_square,
          onPressed: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
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
