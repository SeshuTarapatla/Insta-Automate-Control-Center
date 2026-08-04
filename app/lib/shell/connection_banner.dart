import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/agent_launcher.dart';
import '../core/connection_state.dart';
import '../core/theme/tokens.dart';
import '../ui/icons.dart';

class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionProvider);
    if (status == AgentConnection.connected) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final tokens = theme.tokens;
    return Material(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: tokens.space.md, vertical: tokens.space.sm),
        child: Row(
          children: [
            AppIcon(AppIcons.offline, color: theme.colorScheme.onErrorContainer, size: IconSize.sm),
            SizedBox(width: tokens.space.xs),
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
            SizedBox(width: tokens.space.xs / 2),
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
