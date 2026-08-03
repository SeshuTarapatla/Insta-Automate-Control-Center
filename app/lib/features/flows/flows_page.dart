import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_state_view.dart';
import '../../core/scheduler_models.dart';
import 'flow_card.dart';
import 'flows_controller.dart';

class FlowsPage extends ConsumerWidget {
  const FlowsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(flowsControllerProvider);

    return async.stateView(
      describeError: describeFlowsError,
      onRetry: () => ref.read(flowsControllerProvider.notifier).refresh(),
      data: (snapshot) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!snapshot.online) _OfflineBanner(theme: theme),
          Expanded(
            child: snapshot.flows.isEmpty
                ? EmptyView(
                    icon: Icons.hourglass_empty,
                    title: snapshot.online ? 'Waiting for the first heartbeat' : 'No flow state yet',
                    body: snapshot.online
                        ? 'No flow state yet — waiting for the first heartbeat.'
                        : "The scheduler hasn't posted a heartbeat yet. Is the pipeline pod running?",
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (final flow in flowOrder)
                          if (snapshot.flows[flow] != null) FlowCard(state: snapshot.flows[flow]!),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.cloud_off, color: theme.colorScheme.onErrorContainer, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Scheduler hasn't been heard from — the pipeline pod may be down.",
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
