// COMPONENTS.md §9 — overlays.
import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import 'status.dart';

/// One shell for every dialog in the app — `entity_yield_dialog.dart`,
/// `shortcuts_reference.dart` and `onboarding.dart` each build their own
/// `showDialog`+`AlertDialog` today (AUDIT §15). Focus trapping and
/// Esc-to-close come free from `showDialog`'s own modal route; this just
/// makes every dialog agree on title/body/actions shape and width.
class AppDialog extends StatelessWidget {
  const AppDialog({super.key, required this.title, required this.body, this.actions = const [], this.width});

  final String title;
  final Widget body;
  final List<Widget> actions;
  final double? width;

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required Widget body,
    List<Widget> actions = const [],
    double? width,
  }) => showDialog<T>(context: context, builder: (context) => AppDialog(title: title, body: body, actions: actions, width: width));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: SizedBox(width: width ?? 420, child: body),
      actions: actions.isEmpty ? null : actions,
    );
  }
}

/// A default Material tooltip is a grey box with no structure. `rich: true`
/// gives it the theme's overlay surface (already set via `tooltipTheme`),
/// real padding, an optional title, and monospace for anything formula-
/// shaped — built for D93's flow mechanism/gate-detail tooltip, but generic.
class AppTooltip extends StatelessWidget {
  const AppTooltip({super.key, required this.message, required this.child, this.rich = false, this.title, this.monoBody = false});

  final String message;
  final Widget child;
  final bool rich;
  final String? title;
  final bool monoBody;

  @override
  Widget build(BuildContext context) {
    if (!rich) return Tooltip(message: message, child: child);

    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final bodyStyle = (monoBody ? theme.textTheme.bodySmall?.copyWith(fontFamily: tokens.typography.mono) : theme.textTheme.bodySmall)
        ?.copyWith(color: tokens.content.secondary);

    return Tooltip(
      richMessage: WidgetSpan(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Padding(
            padding: EdgeInsets.all(tokens.space.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null) ...[
                  Text(title!, style: theme.textTheme.labelMedium?.copyWith(color: tokens.content.primary)),
                  SizedBox(height: tokens.space.xs),
                ],
                Text(message, style: bodyStyle),
              ],
            ),
          ),
        ),
      ),
      child: child,
    );
  }
}

class AppMenuItem {
  const AppMenuItem({required this.label, this.icon, this.onTap, this.danger = false});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool danger;
}

enum AppMenuTrigger { tap, secondaryTap }

/// A themed context menu — `menuTheme` already carries the overlay surface,
/// so this only ever picks the item list and how it opens. `secondaryTap`
/// (right-click) is the default, matching `library_tile.dart`'s existing
/// desktop-right-click-as-context-menu precedent.
class AppMenu extends StatelessWidget {
  const AppMenu({super.key, required this.items, required this.child, this.trigger = AppMenuTrigger.secondaryTap});

  final List<AppMenuItem> items;
  final Widget child;
  final AppMenuTrigger trigger;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    return MenuAnchor(
      menuChildren: [
        for (final item in items)
          MenuItemButton(
            onPressed: item.onTap,
            leadingIcon: item.icon == null
                ? null
                : Icon(item.icon, size: tokens.space.iconSm, color: item.danger ? tokens.status.bad.fg : null),
            child: Text(item.label, style: item.danger ? TextStyle(color: tokens.status.bad.fg) : null),
          ),
      ],
      builder: (context, controller, _) => GestureDetector(
        onTap: trigger == AppMenuTrigger.tap ? () => (controller.isOpen ? controller.close() : controller.open()) : null,
        onSecondaryTapUp: trigger == AppMenuTrigger.secondaryTap ? (details) => controller.open(position: details.localPosition) : null,
        child: child,
      ),
    );
  }
}

/// Replaces `core/app_snack_bar.dart`, adding [StatusKind] (today it's a
/// boolean `isError`) and an optional action button.
class AppSnack {
  const AppSnack._();

  static const _duration = Duration(seconds: 3);
  static const _width = 460.0;

  static void show(BuildContext context, String message, {StatusKind kind = StatusKind.neutral, SnackBarAction? action}) {
    final tokens = Theme.of(context).tokens;
    final neutral = kind == StatusKind.neutral;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: neutral ? null : TextStyle(color: kind.onContainer(tokens))),
          action: action,
          duration: _duration,
          // SnackBar's constructor does `persist = persist ?? action != null`,
          // so *any* snackbar with an action opts out of its own dismiss timer
          // and hangs around forever. Undo is a 3-second offer, not a modal.
          persist: false,
          behavior: SnackBarBehavior.floating,
          width: _width,
          backgroundColor: neutral ? null : kind.container(tokens),
        ),
      );
  }
}
