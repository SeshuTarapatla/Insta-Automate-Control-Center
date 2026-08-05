// THEMES.md §9 — the Appearance tab: a live-miniature theme grid plus the
// three settings that ride alongside it (density, reduce motion, terminal
// palette override). All four persist via `theme_controller.dart`, mirroring
// `MutedTagsController`'s existing pattern.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/build_theme.dart';
import '../../core/theme/density.dart';
import '../../core/theme/registry.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/theme/tokens.dart';
import '../../ui/icons.dart';
import '../../ui/status.dart';
import '../../ui/surfaces.dart';
import '../../ui/text.dart';

class AppearanceTab extends ConsumerWidget {
  const AppearanceTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final prefs = ref.watch(themeControllerProvider);
    final controller = ref.read(themeControllerProvider.notifier);

    return ListView(
      padding: EdgeInsets.all(tokens.space.lg),
      children: [
        AppText('Theme', role: TextRole.sectionTitle),
        SizedBox(height: tokens.space.xs),
        AppText(
          'A theme changes color, type, geometry and depth together — pick the one that reads '
          'right for the room you use this in, not just the colors.',
          role: TextRole.caption,
          color: tokens.content.secondary,
          ellipsis: false,
        ),
        SizedBox(height: tokens.space.md),
        Wrap(
          spacing: tokens.space.md,
          runSpacing: tokens.space.md,
          children: [
            for (final entry in themeRegistry.entries)
              _ThemeCard(id: entry.key, tokens: entry.value(), selected: entry.key == prefs.themeId, onTap: () => controller.setTheme(entry.key)),
          ],
        ),
        SizedBox(height: tokens.space.xxl),

        AppText('Density', role: TextRole.sectionTitle),
        SizedBox(height: tokens.space.xs),
        AppText(
          'Compact tightens spacing and text size app-wide; Spacious loosens it. Same layouts, '
          'either packed closer or given more room to breathe.',
          role: TextRole.caption,
          color: tokens.content.secondary,
          ellipsis: false,
        ),
        SizedBox(height: tokens.space.sm),
        SegmentedButton<Density>(
          segments: const [
            ButtonSegment(value: Density.compact, label: Text('Compact')),
            ButtonSegment(value: Density.comfortable, label: Text('Comfortable')),
            ButtonSegment(value: Density.spacious, label: Text('Spacious')),
          ],
          selected: {prefs.density},
          onSelectionChanged: (selection) => controller.setDensity(selection.first),
        ),
        SizedBox(height: tokens.space.xxl),

        AppText('Reduce motion', role: TextRole.sectionTitle),
        SizedBox(height: tokens.space.xs),
        AppText(
          '"Auto" follows Windows\' own "Show animations" setting. "Always" and "Never" override it.',
          role: TextRole.caption,
          color: tokens.content.secondary,
          ellipsis: false,
        ),
        SizedBox(height: tokens.space.sm),
        SegmentedButton<ReduceMotionSetting>(
          segments: const [
            ButtonSegment(value: ReduceMotionSetting.auto, label: Text('Auto')),
            ButtonSegment(value: ReduceMotionSetting.always, label: Text('Always')),
            ButtonSegment(value: ReduceMotionSetting.never, label: Text('Never')),
          ],
          selected: {prefs.reduceMotion},
          onSelectionChanged: (selection) => controller.setReduceMotion(selection.first),
        ),
        SizedBox(height: tokens.space.xxl),

        AppText('Terminal palette', role: TextRole.sectionTitle),
        SizedBox(height: tokens.space.xs),
        AppText(
          'Daylight and Swiss ship a light terminal palette by default. "Always dark" keeps the '
          'Services terminal dark regardless of theme — a real preference, not a fallback.',
          role: TextRole.caption,
          color: tokens.content.secondary,
          ellipsis: false,
        ),
        SizedBox(height: tokens.space.sm),
        SegmentedButton<TerminalOverride>(
          segments: const [
            ButtonSegment(value: TerminalOverride.followTheme, label: Text('Follow theme')),
            ButtonSegment(value: TerminalOverride.alwaysDark, label: Text('Always dark')),
          ],
          selected: {prefs.terminalOverride},
          onSelectionChanged: (selection) => controller.setTerminalOverride(selection.first),
        ),
      ],
    );
  }
}

/// THEMES.md §9 — "each card renders a live miniature of the real app
/// chrome... not a color swatch." Wraps the miniature's own subtree in a
/// fresh `Theme(data: buildTheme(tokens))`, so every color, radius, font and
/// icon weight below is the theme's real, built output — never a
/// hand-approximated preview that could drift from what selecting it
/// actually produces.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.id, required this.tokens, required this.selected, required this.onTap});

  final ThemeId id;
  final AppTokens tokens;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final outer = Theme.of(context).tokens;
    final ringColor = selected ? outer.accent.primary : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Semantics(
          button: true,
          selected: selected,
          label: '${tokens.name} theme',
          child: AnimatedContainer(
            duration: outer.motion.instant,
            width: 248,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(outer.geometry.radiusMd + 4),
              border: Border.all(color: ringColor, width: outer.geometry.borderWidthStrong),
            ),
            padding: const EdgeInsets.all(4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(outer.geometry.radiusMd), child: _ThemeMiniature(tokens: tokens)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: outer.space.xs, vertical: outer.space.xs),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppText(tokens.name, role: TextRole.subTitle),
                            AppText(tokens.tagline, role: TextRole.caption, color: outer.content.secondary, maxLines: 2, ellipsis: true),
                          ],
                        ),
                      ),
                      if (selected) ...[
                        SizedBox(width: outer.space.xs),
                        Icon(Icons.check_circle, size: outer.space.iconSm, color: outer.accent.primary),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeMiniature extends StatelessWidget {
  const _ThemeMiniature({required this.tokens});

  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: 150,
      child: Theme(
        data: buildTheme(tokens),
        child: Builder(
          builder: (context) {
            final t = Theme.of(context).tokens;
            return DecoratedBox(
              decoration: BoxDecoration(color: t.surface.base),
              child: Column(
                children: [
                  // Title bar strip.
                  Container(
                    height: 22,
                    color: t.surface.raised,
                    padding: EdgeInsets.symmetric(horizontal: t.space.sm),
                    child: Row(
                      children: [
                        for (final dotColor in [t.status.bad.fg, t.status.warn.fg, t.status.good.fg]) ...[
                          Container(width: 6, height: 6, margin: EdgeInsets.only(right: 3), decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                        ],
                        const Spacer(),
                        AppText(t.name, role: TextRole.micro, color: t.content.secondary),
                      ],
                    ),
                  ),
                  Divider(height: t.geometry.hairline, thickness: t.geometry.hairline, color: t.surface.border),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Nav rail — three destinations.
                        Container(
                          width: 30,
                          padding: EdgeInsets.symmetric(vertical: t.space.xs),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              AppIcon(AppIcons.overview, size: IconSize.sm, color: t.accent.primary),
                              AppIcon(AppIcons.flow, size: IconSize.sm, color: t.content.tertiary),
                              AppIcon(AppIcons.service, size: IconSize.sm, color: t.content.tertiary),
                            ],
                          ),
                        ),
                        VerticalDivider(width: t.geometry.hairline, thickness: t.geometry.hairline, color: t.surface.border),
                        // A small card: status dot, hairline, numeric.
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.all(t.space.xs),
                            child: AppCard(
                              padding: EdgeInsets.all(t.space.sm),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const StatusDot(kind: StatusKind.good, pulsing: true, size: 7),
                                      SizedBox(width: t.space.xs),
                                      AppText('Running', role: TextRole.caption),
                                    ],
                                  ),
                                  SizedBox(height: t.space.xs),
                                  Divider(height: t.geometry.hairline, thickness: t.geometry.hairline, color: t.surface.borderSubtle),
                                  SizedBox(height: t.space.xs),
                                  const NumericText('182/300', role: TextRole.cardTitle),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
