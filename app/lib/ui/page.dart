// COMPONENTS.md §5 — page structure. The fix for AUDIT §3 (six page
// paddings) and §4 (four header conventions): every screen wraps in exactly
// one `AppPage`, which owns the outer padding, the title row, the tab bar,
// and the max-width constraint, so all seven screens finally agree on where
// content starts and how a title looks.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/nav_state.dart';
import '../core/theme/tokens.dart';
import 'buttons.dart';

class AppTab {
  const AppTab({required this.label, this.icon});

  final String label;
  final IconData? icon;
}

/// Every screen's outer shell. `tabs` renders a themed `TabBar` reading the
/// ambient `DefaultTabController` — the caller wraps its page in
/// `DefaultTabController(length: tabs.length, child: AppPage(...))` and
/// passes the matching `TabBarView` as [body]; `AppPage` itself holds no tab
/// state, only the chrome.
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.leading,
    this.tabs,
    required this.body,
    this.scrollable = false,
    this.maxContentWidth,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// e.g. the Live screen's flow selector, sitting alongside the title.
  final Widget? leading;
  final List<AppTab>? tabs;
  final Widget body;
  final bool scrollable;

  /// Insights' hardcoded `900` becomes a token-driven default per screen
  /// instead of a literal at the call site.
  final double? maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;

    Widget content = body;
    if (maxContentWidth != null) {
      content = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxContentWidth!), child: content),
      );
    }
    if (scrollable) content = SingleChildScrollView(child: content);

    return Padding(
      padding: EdgeInsets.fromLTRB(tokens.space.pagePadding, tokens.space.lg, tokens.space.pagePadding, tokens.space.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(title: title, subtitle: subtitle, actions: actions, leading: leading),
          if (tabs != null) ...[
            SizedBox(height: tokens.space.sm),
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [for (final tab in tabs!) Tab(text: tab.label, icon: tab.icon == null ? null : Icon(tab.icon))],
            ),
          ],
          SizedBox(height: tokens.space.lg),
          Expanded(child: content),
        ],
      ),
    );
  }
}

/// Used internally by [AppPage]; exposed for the rare screen that needs the
/// title row without the rest of the page shell (e.g. inside a dialog).
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const [], this.leading});

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: theme.textTheme.headlineSmall),
        if (subtitle != null) ...[
          SizedBox(height: tokens.space.xs / 2),
          Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary)),
        ],
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        titleBlock,
        if (leading != null) ...[SizedBox(width: tokens.space.lg), Expanded(child: leading!)] else const Spacer(),
        if (actions.isNotEmpty) ...[SizedBox(width: tokens.space.md), ButtonGroup(children: actions)],
      ],
    );
  }
}

/// Generalises `overview_page.dart`'s private `_SectionHeader` — the chevron
/// + `navIndex` tap-to-navigate behaviour is good and becomes available
/// everywhere a section summarises a full screen.
class SectionHeader extends ConsumerWidget {
  const SectionHeader({super.key, required this.title, this.caption, this.navIndex, this.actions});

  final String title;
  final String? caption;
  final int? navIndex;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    final titleRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        if (navIndex != null) ...[
          SizedBox(width: tokens.space.xs),
          Icon(Icons.chevron_right, size: tokens.space.iconSm, color: tokens.content.secondary),
        ],
      ],
    );

    final tappable = navIndex == null
        ? titleRow
        : InkWell(
            onTap: () => ref.read(selectedNavIndexProvider.notifier).select(navIndex!),
            borderRadius: BorderRadius.circular(tokens.geometry.radiusSm),
            child: Padding(padding: EdgeInsets.symmetric(vertical: 2), child: titleRow),
          );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              tappable,
              if (caption != null) Text(caption!, style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary)),
            ],
          ),
        ),
        if (actions != null) ...actions!,
      ],
    );
  }
}

/// A leading/trailing action row that wraps instead of overflowing.
class Toolbar extends StatelessWidget {
  const Toolbar({super.key, this.leading = const [], this.trailing = const []});

  final List<Widget> leading;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      runSpacing: tokens.space.sm,
      children: [
        Wrap(spacing: tokens.space.sm, crossAxisAlignment: WrapCrossAlignment.center, children: leading),
        Wrap(spacing: tokens.space.sm, crossAxisAlignment: WrapCrossAlignment.center, children: trailing),
      ],
    );
  }
}
