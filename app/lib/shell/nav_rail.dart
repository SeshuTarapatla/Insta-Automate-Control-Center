// SCREENS.md §0 — the nav rail, rebuilt from a flat `NavigationRail` (seven
// items, no hierarchy — AUDIT's "shape of a demo app") into a grouped,
// badged, collapsible one. `NavigationRail`'s own API has no notion of
// grouping or a sub-item, so this is a hand-built replacement rather than a
// themed stock widget, the same call `AppTable`/the Ranking table made (D77).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/library_models.dart';
import '../core/nav_state.dart';
import '../core/service_models.dart';
import '../core/theme/tokens.dart';
import '../features/library/library_controller.dart';
import '../features/overview/curation_tile.dart';
import '../features/services/services_controller.dart';
import '../ui/icons.dart';
import '../ui/overlays.dart';
import '../ui/status.dart';

class _Destination {
  const _Destination(this.label, this.glyph);
  final String label;
  final PhosphorIconData Function(PhosphorIconsStyle) glyph;
}

// Index-aligned with `core/nav_state.dart`'s `overviewIndex..settingsIndex`
// constants (0..6) — deliberately, so `_destinations[i]` is always the right
// entry with no separate lookup table.
const _destinations = [
  _Destination('Overview', AppIcons.overview),
  _Destination('Flows', AppIcons.flow),
  _Destination('Live', AppIcons.sensor),
  _Destination('Services', AppIcons.service),
  _Destination('Library', AppIcons.library),
  _Destination('Insights', AppIcons.insight),
  _Destination('Settings', AppIcons.settings),
];

class _NavGroup {
  const _NavGroup(this.label, this.items);
  final String label;
  final List<int> items;
}

// `settingsIndex` is deliberately not here — SCREENS.md §0 pins it to the
// bottom, outside every group.
const _navGroups = [
  _NavGroup('MONITOR', [overviewIndex, flowsIndex, liveIndex]),
  _NavGroup('OPERATE', [servicesIndex, libraryIndex]),
  _NavGroup('ANALYZE', [insightsIndex]),
];

/// Grouped, badged and collapsible (`Ctrl+B`, `AppShell`'s own binding —
/// `navRailCollapsedProvider` is the persisted state this widget reads).
/// Badges come from data every other screen already has a provider for —
/// no new agent endpoint, per the v2 scope boundary.
class AppNavRail extends ConsumerWidget {
  const AppNavRail({super.key});

  static const _expandedWidth = 208.0;
  static const _collapsedWidth = 72.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).tokens;
    final selected = ref.watch(selectedNavIndexProvider);
    final collapsed = ref.watch(navRailCollapsedProvider);
    final selectedFolder = ref.watch(selectedFolderProvider);

    final services = ref.watch(servicesControllerProvider).value ?? const <ServiceStatus>[];
    final serviceIssueCount = services
        .where((s) => s.state == ServiceState.unhealthy || s.state == ServiceState.backoff || s.state == ServiceState.failed)
        .length;

    final folders = ref.watch(libraryFoldersControllerProvider).value ?? const <LibraryFolderInfo>[];
    final reviewCount = curationFolders.fold<int>(
      0,
      (sum, folder) => sum + (folders.where((f) => f.name == folder).map((f) => f.total).firstOrNull ?? 0),
    );

    // Flows deliberately has no badge here — a flow standing by on its
    // condition is normal pipeline rhythm, not something worth flagging at
    // a glance (the same reasoning that dropped it from the Overview hero
    // tile's "needs attention" bucket). Only genuinely actionable counts —
    // an unhealthy service, a real curation backlog — earn one.
    final badges = {servicesIndex: serviceIssueCount};

    void select(int index) => ref.read(selectedNavIndexProvider.notifier).select(index);
    void openReview() {
      ref.read(selectedFolderProvider.notifier).select(curationFolders.first);
      ref.read(selectedEntityProvider.notifier).select(null);
      select(libraryIndex);
    }

    return AnimatedContainer(
      duration: tokens.motion.reduced ? Duration.zero : tokens.motion.standard,
      curve: tokens.motion.enter,
      width: collapsed ? _collapsedWidth : _expandedWidth,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(vertical: tokens.space.sm),
              children: [
                for (final group in _navGroups) ...[
                  collapsed ? SizedBox(height: tokens.space.sm) : _GroupHeader(label: group.label),
                  for (final index in group.items) ...[
                    _NavTile(
                      icon: _destinations[index].glyph,
                      label: _destinations[index].label,
                      selected: selected == index,
                      collapsed: collapsed,
                      badgeCount: badges[index] ?? 0,
                      onTap: () => select(index),
                    ),
                    if (index == libraryIndex)
                      _NavTile(
                        icon: AppIcons.review,
                        label: 'Review',
                        selected: selected == libraryIndex && curationFolders.contains(selectedFolder),
                        collapsed: collapsed,
                        badgeCount: reviewCount,
                        indent: true,
                        onTap: openReview,
                      ),
                  ],
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          _NavTile(
            icon: _destinations[settingsIndex].glyph,
            label: _destinations[settingsIndex].label,
            selected: selected == settingsIndex,
            collapsed: collapsed,
            badgeCount: 0,
            onTap: () => select(settingsIndex),
          ),
          _CollapseToggle(collapsed: collapsed),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    return Padding(
      padding: EdgeInsets.fromLTRB(tokens.space.md, tokens.space.md, tokens.space.md, tokens.space.xs / 2),
      child: Text(label, style: theme.textTheme.labelSmall?.copyWith(color: tokens.content.tertiary, letterSpacing: 0.6)),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.collapsed,
    required this.badgeCount,
    required this.onTap,
    this.indent = false,
  });

  final PhosphorIconData Function(PhosphorIconsStyle) icon;
  final String label;
  final bool selected;
  final bool collapsed;
  final int badgeCount;
  final VoidCallback onTap;
  final bool indent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final fg = selected ? theme.colorScheme.primary : tokens.content.secondary;

    final row = Row(
      mainAxisSize: collapsed ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (indent && !collapsed) SizedBox(width: tokens.space.lg),
        AppIcon(icon, size: IconSize.md, color: fg),
        if (!collapsed) ...[
          SizedBox(width: tokens.space.sm),
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(color: fg)),
          ),
          if (badgeCount > 0) CountBadge(count: badgeCount, kind: StatusKind.warn),
        ] else if (badgeCount > 0)
          Padding(padding: const EdgeInsets.only(left: 3), child: CountBadge(count: badgeCount, dot: true, kind: StatusKind.warn)),
      ],
    );

    // A rail this roomy (V2.5's own `_expandedWidth`/`_collapsedWidth`) had
    // no business rendering `IconSize.sm` icons pinned 1px apart — bumped to
    // `lg` with real padding/margin around them, from your own live read of
    // the collapsed rail looking tiny and cramped against how much width was
    // actually sitting unused.
    final decorated = Container(
      margin: EdgeInsets.symmetric(horizontal: tokens.space.xs, vertical: tokens.space.xs / 2),
      padding: EdgeInsets.symmetric(horizontal: tokens.space.sm, vertical: tokens.space.sm),
      alignment: collapsed ? Alignment.center : null,
      decoration: BoxDecoration(
        color: selected ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.5) : null,
        borderRadius: BorderRadius.circular(tokens.geometry.radiusSm),
      ),
      child: row,
    );

    final tappable = InkWell(onTap: onTap, borderRadius: BorderRadius.circular(tokens.geometry.radiusSm), child: decorated);

    // Collapsed loses its visible label, so the tooltip is the a11y floor
    // (DESIGN_SYSTEM §6) an icon-only control needs — expanded already shows
    // the label inline, so a second tooltip saying the same thing would be
    // noise.
    return collapsed ? AppTooltip(message: label, child: tappable) : tappable;
  }
}

class _CollapseToggle extends ConsumerWidget {
  const _CollapseToggle({required this.collapsed});
  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: IconButton(
        tooltip: collapsed ? 'Expand navigation  (Ctrl+B)' : 'Collapse navigation  (Ctrl+B)',
        iconSize: 16,
        visualDensity: VisualDensity.compact,
        icon: AppIcon(collapsed ? AppIcons.chevronRight : AppIcons.sidebarCollapse, size: IconSize.sm),
        onPressed: () => ref.read(navRailCollapsedProvider.notifier).toggle(),
      ),
    );
  }
}
