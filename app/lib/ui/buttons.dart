// COMPONENTS.md §4 — buttons and actions.
import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import 'status.dart';

enum ButtonTone { primary, neutral, danger }

enum ButtonSize { sm, md }

/// The one button widget. `filled` chooses a solid fill over an outline;
/// `busy` renders an inline spinner and disables the button — the pattern
/// `flow_card.dart`'s "Command sent — waiting…" state and `ops_tab.dart`
/// both hand-roll today.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.tone = ButtonTone.neutral,
    this.size = ButtonSize.md,
    this.filled = false,
    this.busy = false,
    this.tooltip,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final ButtonTone tone;
  final ButtonSize size;
  final bool filled;
  final bool busy;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final height = size == ButtonSize.sm ? tokens.space.controlHeight * 0.8 : tokens.space.controlHeight;

    final (bg, fg) = switch (tone) {
      ButtonTone.primary => (tokens.accent.primary, filled ? tokens.accent.onPrimary : tokens.accent.primary),
      ButtonTone.danger => (tokens.status.bad.fg, filled ? tokens.content.onAccent : tokens.status.bad.fg),
      ButtonTone.neutral => (tokens.surface.raised, tokens.content.primary),
    };

    final style = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => !filled ? null : (states.contains(WidgetState.disabled) ? tokens.surface.raised : bg),
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? tokens.content.tertiary : fg,
      ),
      side: WidgetStateProperty.resolveWith(
        (states) => filled
            ? BorderSide.none
            : BorderSide(
                color: states.contains(WidgetState.disabled)
                    ? tokens.surface.border
                    : (tone == ButtonTone.neutral ? tokens.surface.borderStrong : fg),
                width: tokens.geometry.borderWidth,
              ),
      ),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.geometry.radiusSm))),
      minimumSize: WidgetStatePropertyAll(Size(0, height)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: size == ButtonSize.sm ? tokens.space.md : tokens.space.lg)),
      mouseCursor: const WidgetStatePropertyAll(SystemMouseCursors.click),
      textStyle: WidgetStatePropertyAll(size == ButtonSize.sm ? theme.textTheme.labelMedium : theme.textTheme.labelLarge),
    );

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy) ...[
          SizedBox(
            width: tokens.space.iconSm,
            height: tokens.space.iconSm,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          ),
          SizedBox(width: tokens.space.sm),
        ] else if (icon != null) ...[
          Icon(icon, size: tokens.space.iconSm),
          SizedBox(width: tokens.space.sm),
        ],
        Text(busy ? 'Working…' : label),
      ],
    );

    final button = OutlinedButton(onPressed: busy ? null : onPressed, style: style, child: content);
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// An icon-only action. `tooltip` is **required** — a compile-time guarantee
/// rather than a convention — and doubles as the `Semantics` label, closing
/// the accessibility gap DESIGN_SYSTEM §6 flags (icon buttons with tooltips
/// today are inconsistent, not universal).
class IconAction extends StatelessWidget {
  const IconAction({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.size = ButtonSize.md,
    this.kind,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final ButtonSize size;

  /// Tints the icon toward a status color — e.g. the destructive red on a
  /// "Delete" action — without pulling in `AppButton`'s full ceremony.
  final StatusKind? kind;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    final color = kind?.fg(tokens);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: tooltip,
        button: true,
        child: IconButton(
          onPressed: onPressed,
          color: color,
          icon: Icon(icon, size: size == ButtonSize.sm ? tokens.space.iconSm : tokens.space.iconMd),
        ),
      ),
    );
  }
}

/// A row of buttons that wraps instead of overflowing — replaces the ad-hoc
/// `Wrap(spacing: 8, runSpacing: 8)` clusters `flow_card.dart`,
/// `library_toolbar.dart`, `service_detail.dart` and `ops_tab.dart` each
/// hand-tuned separately after real overflow reports (D87, D89, CP 5.3).
class ButtonGroup extends StatelessWidget {
  const ButtonGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final space = Theme.of(context).tokens.space;
    return Wrap(spacing: space.sm, runSpacing: space.sm, children: children);
  }
}
