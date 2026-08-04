import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/feedback.dart';
import '../../core/scheduler_models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/icons.dart';
import '../../ui/page.dart';
import 'flow_card.dart';
import 'flows_controller.dart';

class FlowsPage extends ConsumerWidget {
  const FlowsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(flowsControllerProvider);

    return AppPage(
      title: 'Flows',
      body: async.stateView(
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
                      child: Wrap(
                        spacing: theme.tokens.space.lg,
                        runSpacing: theme.tokens.space.lg,
                        children: [
                          for (final flow in flowOrder)
                            if (snapshot.flows[flow] != null) FlowCard(state: snapshot.flows[flow]!),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final tokens = theme.tokens;
    return Material(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: tokens.space.lg, vertical: tokens.space.sm),
        child: Row(
          children: [
            AppIcon(AppIcons.offline, color: theme.colorScheme.onErrorContainer, size: IconSize.sm),
            SizedBox(width: tokens.space.xs),
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
