import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_state_view.dart';
import '../../core/service_models.dart';
import 'dependencies_tab.dart';
import 'service_detail.dart';
import 'service_tile.dart';
import 'services_controller.dart';

/// Two questions about one machine, so one screen with two tabs: what the agent
/// runs (and can therefore start, stop and prove), and what it merely depends
/// on.
class ServicesPage extends ConsumerWidget {
  const ServicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: 'Supervised'),
                Tab(text: 'Dependencies'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [_SupervisedTab(), DependenciesTab()],
            ),
          ),
        ],
      ),
    );
  }
}

class _SupervisedTab extends ConsumerWidget {
  const _SupervisedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(servicesControllerProvider);

    return async.stateView(
      describeError: describeAgentError,
      onRetry: () => ref.read(servicesControllerProvider.notifier).refresh(),
      data: (services) {
        if (services.isEmpty) {
          return const EmptyView(icon: Icons.dns_outlined, title: 'The agent supervises no services.');
        }

        final selectedName = ref.watch(selectedServiceProvider);
        final selected = services.firstWhere(
          (service) => service.name == selectedName,
          orElse: () => services.first,
        );

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 300,
                child: _ServiceList(services: services, selected: selected, theme: theme),
              ),
              const SizedBox(width: 20),
              Expanded(child: ServiceDetail(status: selected)),
            ],
          ),
        );
      },
    );
  }
}

class _ServiceList extends ConsumerWidget {
  const _ServiceList({required this.services, required this.selected, required this.theme});

  final List<ServiceStatus> services;
  final ServiceStatus selected;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = theme.colorScheme;
    final healthy = services.where((s) => s.state == ServiceState.running).length;
    final external = services.where((s) => s.canTakeover).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Core services', style: theme.textTheme.titleMedium),
            const SizedBox(width: 10),
            Chip(
              label: Text('$healthy of ${services.length} up'),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          external > 0
              // The honest description of today's state: the startup shortcut
              // still launches these, and the agent is watching rather than
              // running them until CP 2.5.
              ? '$external still running outside the agent — take one over to have the agent '
                    'supervise it and stream its terminal here.'
              : 'Started, watched and restarted by the agent. Their output is streamed below.',
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView.separated(
            itemCount: services.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final service = services[index];
              return ServiceTile(
                status: service,
                selected: service.name == selected.name,
                onTap: () => ref.read(selectedServiceProvider.notifier).select(service.name),
              );
            },
          ),
        ),
      ],
    );
  }
}
