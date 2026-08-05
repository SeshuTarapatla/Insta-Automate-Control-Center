// SCREENS.md §1 — bento mission control. Replaces the old vertical stack of
// five full FlowCards + two cards + five 340px burn-down charts + two more
// cards (AUDIT §12, ~two screens of scrolling, no headline) with a hero
// status sentence plus a grid of single-question tiles, all composed from
// the exact widgets/providers their own screens already use.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/nav_state.dart';
import '../../core/theme/tokens.dart';
import '../../ui/feedback.dart';
import '../../ui/layout.dart';
import '../../ui/page.dart';
import '../../ui/status.dart';
import '../../ui/surfaces.dart';
import '../flows/flows_controller.dart';
import '../insights/insights_controller.dart';
import '../library/library_controller.dart';
import '../live/device_bar.dart';
import '../services/dependencies_controller.dart';
import '../services/service_status_kind.dart';
import '../services/services_controller.dart';
import 'caps_tile.dart';
import 'curation_tile.dart';
import 'dependency_strip.dart';
import 'hero_tile.dart';
import 'pipeline_strip.dart';
import 'recent_notifications_card.dart';

/// DESIGN_SYSTEM §7's three named breakpoints — the real production window
/// (~1250 logical wide) lands in `medium`, which is the design target, not
/// `wide`; `compact` is the 1024px floor.
enum _Bento { compact, medium, wide }

_Bento _bentoFor(double width) {
  if (width < 1100) return _Bento.compact;
  if (width < 1500) return _Bento.medium;
  return _Bento.wide;
}

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Overview',
      scrollable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HeroTile(),
          const Gap.lg(),
          LayoutBuilder(builder: (context, constraints) => _BentoGrid(bento: _bentoFor(constraints.maxWidth))),
        ],
      ),
    );
  }
}

class _BentoGrid extends StatelessWidget {
  const _BentoGrid({required this.bento});

  final _Bento bento;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;

    if (bento == _Bento.compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PipelineTile(),
          Gap.lg(),
          const _ServicesTile(),
          Gap.lg(),
          const _DependenciesTile(),
          Gap.lg(),
          const _CapsTile(),
          Gap.lg(),
          const _CurationTile(),
          Gap.lg(),
          const _DeviceTile(),
          Gap.lg(),
          const _RecentTile(),
        ],
      );
    }

    if (bento == _Bento.wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(flex: 3, child: _PipelineTile()),
              SizedBox(width: tokens.space.lg),
              const Expanded(child: _ServicesTile()),
              SizedBox(width: tokens.space.lg),
              const Expanded(child: _DependenciesTile()),
              SizedBox(width: tokens.space.lg),
              const Expanded(child: _CurationTile()),
            ],
          ),
          Gap.lg(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(flex: 3, child: _CapsTile()),
              SizedBox(width: tokens.space.lg),
              const Expanded(child: _DeviceTile()),
              SizedBox(width: tokens.space.lg),
              const Expanded(flex: 2, child: _RecentTile()),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(flex: 2, child: _PipelineTile()),
            SizedBox(width: tokens.space.lg),
            const Expanded(child: _ServicesTile()),
            SizedBox(width: tokens.space.lg),
            const Expanded(child: _DependenciesTile()),
          ],
        ),
        Gap.lg(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(flex: 2, child: _CapsTile()),
            SizedBox(width: tokens.space.lg),
            const Expanded(child: _CurationTile()),
            SizedBox(width: tokens.space.lg),
            const Expanded(child: _DeviceTile()),
          ],
        ),
        Gap.lg(),
        const _RecentTile(),
      ],
    );
  }
}

/// The chrome every tile shares: a card, a `SectionHeader` keeping CP 7.3's
/// jump-to-the-full-screen behaviour, then whatever the tile actually shows.
class _Tile extends StatelessWidget {
  const _Tile({required this.title, this.navIndex, required this.child});

  final String title;
  final int? navIndex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [SectionHeader(title: title, navIndex: navIndex), SizedBox(height: tokens.space.sm), child],
      ),
    );
  }
}

class _PipelineTile extends ConsumerWidget {
  const _PipelineTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(flowsControllerProvider);
    return _Tile(
      title: 'Pipeline',
      navIndex: flowsIndex,
      child: async.stateView(
        describeError: describeFlowsError,
        data: (snapshot) => snapshot.flows.isEmpty
            ? const EmptyView(icon: Icons.hourglass_empty, title: 'Waiting for the first heartbeat')
            : PipelineStrip(snapshot: snapshot),
      ),
    );
  }
}

class _ServicesTile extends ConsumerWidget {
  const _ServicesTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final async = ref.watch(servicesControllerProvider);
    return _Tile(
      title: 'Services',
      navIndex: servicesIndex,
      child: async.stateView(
        describeError: describeAgentError,
        data: (services) {
          if (services.isEmpty) {
            return Text('No supervised services.', style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final service in services)
                Padding(
                  padding: EdgeInsets.only(bottom: tokens.space.xs),
                  child: Row(
                    children: [
                      StatusDot(kind: service.state.statusKind, pulsing: service.state.isTransient, size: 8),
                      SizedBox(width: tokens.space.xs),
                      Expanded(child: Text(service.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium)),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DependenciesTile extends ConsumerWidget {
  const _DependenciesTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dependenciesControllerProvider);
    return _Tile(
      title: 'Dependencies',
      navIndex: servicesIndex,
      child: async.stateView(describeError: describeAgentError, data: (snapshot) => DependencyStrip(snapshot: snapshot)),
    );
  }
}

class _CapsTile extends ConsumerWidget {
  const _CapsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(burndownProvider);
    return _Tile(
      title: "Today's caps",
      navIndex: insightsIndex,
      child: async.stateView(describeError: describeInsightsError, data: (burndown) => CapsTile(burndown: burndown)),
    );
  }
}

class _CurationTile extends ConsumerWidget {
  const _CurationTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(libraryFoldersControllerProvider);
    return _Tile(
      title: 'Curation',
      navIndex: libraryIndex,
      child: async.stateView(describeError: describeLibraryError, data: (folders) => CurationTile(folders: folders)),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile();

  @override
  Widget build(BuildContext context) => const _Tile(title: 'Device', navIndex: liveIndex, child: DeviceBar());
}

class _RecentTile extends StatelessWidget {
  const _RecentTile();

  @override
  Widget build(BuildContext context) => const _Tile(title: 'Recent', child: RecentNotificationsCard(maxShown: 2));
}
