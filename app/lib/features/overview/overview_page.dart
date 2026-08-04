import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/feedback.dart';
import '../../core/insights_models.dart';
import '../../core/nav_state.dart';
import '../../core/scheduler_models.dart';
import '../flows/flow_card.dart';
import '../flows/flows_controller.dart';
import '../insights/burndown_chart.dart';
import '../insights/insights_controller.dart';
import '../live/device_bar.dart';
import '../services/dependencies_controller.dart';
import '../services/service_tile.dart';
import '../services/services_controller.dart';
import 'dependency_strip.dart';
import 'recent_notifications_card.dart';

/// Mission control (ARCHITECTURE §9): everything else already built —
/// flows, services, dependencies, daily burn-down, the device, recent
/// notifications — read at a glance on one screen, composed from the exact
/// widgets/providers their own screens already use rather than reinvented
/// (CP 7.3). Each section header jumps to the matching full destination.
class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: const [
        _SectionHeader(title: 'Flows', navIndex: flowsIndex),
        SizedBox(height: 12),
        _FlowsSection(),
        SizedBox(height: 28),
        _TwoColumn(left: _ServicesSection(), right: _DependenciesSection()),
        SizedBox(height: 28),
        _SectionHeader(title: 'Daily limits', navIndex: insightsIndex),
        SizedBox(height: 12),
        _BurndownSection(),
        SizedBox(height: 28),
        _TwoColumn(flexLeft: 2, left: _NotificationsSection(), right: _DeviceSection()),
      ],
    );
  }
}

class _TwoColumn extends StatelessWidget {
  const _TwoColumn({required this.left, required this.right, this.flexLeft = 1});

  final Widget left;
  final Widget right;
  final int flexLeft;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: flexLeft, child: left),
        const SizedBox(width: 20),
        Expanded(child: right),
      ],
    );
  }
}

class _SectionHeader extends ConsumerWidget {
  const _SectionHeader({required this.title, this.navIndex});

  final String title;
  final int? navIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final header = Row(
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        if (navIndex != null) ...[
          const SizedBox(width: 6),
          Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant),
        ],
      ],
    );
    if (navIndex == null) return header;
    return InkWell(
      onTap: () => ref.read(selectedNavIndexProvider.notifier).select(navIndex!),
      borderRadius: BorderRadius.circular(8),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: header),
    );
  }
}

class _FlowsSection extends ConsumerWidget {
  const _FlowsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(flowsControllerProvider);
    return async.stateView(
      describeError: describeFlowsError,
      data: (snapshot) {
        if (snapshot.flows.isEmpty) {
          return const EmptyView(icon: Icons.hourglass_empty, title: 'Waiting for the first heartbeat');
        }
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final flow in flowOrder)
              if (snapshot.flows[flow] != null) FlowCard(state: snapshot.flows[flow]!),
          ],
        );
      },
    );
  }
}

class _ServicesSection extends ConsumerWidget {
  const _ServicesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(servicesControllerProvider);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(title: 'Services', navIndex: servicesIndex),
            const SizedBox(height: 12),
            async.stateView(
              describeError: describeAgentError,
              data: (services) {
                if (services.isEmpty) {
                  return Text(
                    'The agent supervises no services.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  );
                }
                return Column(
                  children: [
                    for (final service in services)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ServiceTile(
                          status: service,
                          selected: false,
                          onTap: () => ref.read(selectedNavIndexProvider.notifier).select(servicesIndex),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DependenciesSection extends ConsumerWidget {
  const _DependenciesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dependenciesControllerProvider);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(title: 'Dependencies', navIndex: servicesIndex),
            const SizedBox(height: 12),
            async.stateView(describeError: describeAgentError, data: (snapshot) => DependencyStrip(snapshot: snapshot)),
          ],
        ),
      ),
    );
  }
}

class _BurndownSection extends ConsumerWidget {
  const _BurndownSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(burndownProvider);
    return async.stateView(
      describeError: describeInsightsError,
      data: (burndown) => Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          _burndownCard('Scan — profiles', burndown.scan, 'profiles', burndown.limits['profiles']),
          _burndownCard('Scan — reels', burndown.scan, 'reels', burndown.limits['reels']),
          _burndownCard('Scan — posts', burndown.scan, 'posts', burndown.limits['posts']),
          _burndownCard('Scrape', burndown.scrape, 'scraped', burndown.limits['scrape']),
          _burndownCard('Follow', burndown.follow, 'followed', burndown.limits['follow']),
        ],
      ),
    );
  }

  Widget _burndownCard(String title, List<BurndownDay> days, String field, int? cap) {
    return SizedBox(width: 340, child: BurndownCard(title: title, days: days, values: field, cap: cap));
  }
}

class _NotificationsSection extends StatelessWidget {
  const _NotificationsSection();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recent notifications', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const RecentNotificationsCard(),
          ],
        ),
      ),
    );
  }
}

class _DeviceSection extends StatelessWidget {
  const _DeviceSection();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Device', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            const DeviceBar(),
          ],
        ),
      ),
    );
  }
}
