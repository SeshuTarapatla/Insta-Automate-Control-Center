import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/agent_launcher.dart';
import '../core/connection_state.dart';

class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionProvider);
    if (status == AgentConnection.connected) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.cloud_off,
              color: theme.colorScheme.onErrorContainer,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                status == AgentConnection.connecting
                    ? 'Connecting to the agent…'
                    : 'Agent is not reachable at localhost:8787.',
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
            TextButton(
              onPressed: () => ref.read(connectionProvider.notifier).check(),
              child: const Text('Retry'),
            ),
            const SizedBox(width: 4),
            FilledButton.tonal(
              onPressed: () => AgentLauncher.start(),
              child: const Text('Start agent'),
            ),
          ],
        ),
      ),
    );
  }
}
