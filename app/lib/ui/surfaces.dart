// COMPONENTS.md §1 — surfaces. Replaces the three-way split AUDIT found:
// `Card(margin: EdgeInsets.zero)` (19 sites), `Material + InkWell + Container
// + Border` (`service_tile.dart:31-44`), and bare `Container + BoxDecoration`
// (`log_console.dart:192`, `library_tile.dart:89`, `insights_page.dart`).
//
// DESIGN_SYSTEM §4's rule lives here: depth is expressed once, by
// `EffectTokens.depth`, and feature code never sets `elevation` or draws its
// own `BoxShadow`/border again.
import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import 'status.dart';

/// One of `SurfaceTokens`' four content layers (`SurfaceTokens.canvas` is the
/// window background, never a panel itself).
enum SurfaceLevel { base, raised, sunken, overlay }

extension SurfaceLevelX on SurfaceLevel {
  Color color(AppTokens t) => switch (this) {
    SurfaceLevel.base => t.surface.base,
    SurfaceLevel.raised => t.surface.raised,
    SurfaceLevel.sunken => t.surface.sunken,
    SurfaceLevel.overlay => t.surface.overlay,
  };
}

/// The one panel widget. Every card, well and popover surface in v2 is one
/// of these at a different [level] — see [AppCard]/[AppWell]/[AppOverlay]
/// below for the named shortcuts.
class AppPanel extends StatefulWidget {
  const AppPanel({
    super.key,
    required this.child,
    this.padding,
    this.level = SurfaceLevel.base,
    this.interactive = false,
    this.onTap,
    this.onSecondaryTap,
    this.selected = false,
    this.accentEdge,
    this.borderRadius,
  });

  final Widget child;
  final EdgeInsets? padding;
  final SurfaceLevel level;

  /// Adds hover/focus/pressed treatment even with no [onTap] — e.g. a row
  /// that's clickable via a child button rather than the panel itself.
  final bool interactive;
  final VoidCallback? onTap;

  /// Desktop right-click — used by the library's per-tile context menu.
  final VoidCallback? onSecondaryTap;
  final bool selected;

  /// A 2px status-colored left edge — how a failed service, a blocked flow
  /// or an errored ops job announces itself without a differently-colored
  /// card background per theme.
  final StatusKind? accentEdge;
  final double? borderRadius;

  @override
  State<AppPanel> createState() => _AppPanelState();
}

class _AppPanelState extends State<AppPanel> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _clickable => widget.onTap != null || widget.onSecondaryTap != null;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    final radius = widget.borderRadius ?? tokens.geometry.radiusMd;
    final depth = tokens.effects.depth;
    final hasBorder = depth == DepthStrategy.border || depth == DepthStrategy.both;
    final hasShadow = depth == DepthStrategy.shadow || depth == DepthStrategy.both || depth == DepthStrategy.glow;
    final active = widget.interactive || _clickable;

    var background = widget.level.color(tokens);
    if (widget.selected) {
      background = Color.alphaBlend(tokens.accent.primary.withValues(alpha: tokens.effects.hoverTintAlpha * 1.5), background);
    } else if (_pressed && active) {
      background = Color.alphaBlend(tokens.accent.primary.withValues(alpha: tokens.effects.hoverTintAlpha * 1.6), background);
    } else if (_hovered && active) {
      background = Color.alphaBlend(tokens.accent.primary.withValues(alpha: tokens.effects.hoverTintAlpha), background);
    }

    final ringColor = widget.selected ? tokens.accent.primary : tokens.surface.border;
    final ringWidth = widget.selected ? tokens.geometry.borderWidthStrong : tokens.geometry.borderWidth;
    // Deliberately always uniform (never a mixed-color `Border` with
    // `accentEdge` folded into one side): a `Border` whose sides differ in
    // color *and* have non-zero width throws under `BorderRadius` for any
    // theme whose depth strategy actually paints a border (Command Deck,
    // Mica) — Classic's shadow-only strategy happened to dodge it by luck
    // (its "plain" sides are all `BorderSide.none`), which is exactly why
    // this went unnoticed until `accentEdge` got its first real call site
    // (`FlowNode`, V2.6) crashed every non-Classic theme. `accentEdge` is
    // painted as a separate clipped overlay bar below instead.
    final border = hasBorder ? Border.fromBorderSide(BorderSide(color: ringColor, width: ringWidth)) : null;

    final shadow = hasShadow && !widget.selected ? (_hovered && active && tokens.effects.hoverLift ? tokens.effects.shadowMd : tokens.effects.shadowSm) : const <BoxShadow>[];

    Widget panel = AnimatedContainer(
      duration: tokens.motion.instant,
      padding: widget.padding ?? EdgeInsets.all(tokens.space.cardPadding),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(radius), border: border, boxShadow: shadow),
      clipBehavior: Clip.antiAlias,
      child: widget.child,
    );

    if (widget.accentEdge != null) {
      panel = Stack(
        children: [
          panel,
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.only(topLeft: Radius.circular(radius), bottomLeft: Radius.circular(radius)),
              child: Container(width: 2.5, color: widget.accentEdge!.fg(tokens)),
            ),
          ),
        ],
      );
    }

    if (!_clickable && !widget.interactive) return panel;

    return MouseRegion(
      cursor: _clickable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTap: widget.onSecondaryTap,
        onTapDown: widget.onTap == null ? null : (_) => setState(() => _pressed = true),
        onTapUp: widget.onTap == null ? null : (_) => setState(() => _pressed = false),
        onTapCancel: widget.onTap == null ? null : () => setState(() => _pressed = false),
        child: panel,
      ),
    );
  }
}

/// `AppPanel(level: base)` with the theme's card padding — the everyday
/// panel: a service tile, a flow card, a dialog's content block.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.interactive = false,
    this.onTap,
    this.onSecondaryTap,
    this.selected = false,
    this.accentEdge,
  });

  final Widget child;
  final EdgeInsets? padding;
  final bool interactive;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
  final bool selected;
  final StatusKind? accentEdge;

  @override
  Widget build(BuildContext context) => AppPanel(
    padding: padding,
    interactive: interactive,
    onTap: onTap,
    onSecondaryTap: onSecondaryTap,
    selected: selected,
    accentEdge: accentEdge,
    child: child,
  );
}

/// `AppPanel(level: sunken)` — an inset well: terminal body, log console,
/// code blocks, text field interiors.
class AppWell extends StatelessWidget {
  const AppWell({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => AppPanel(level: SurfaceLevel.sunken, padding: padding, child: child);
}

/// `AppPanel(level: overlay)` — used internally by dialogs/menus/tooltips
/// (`ui/overlays.dart`); rarely reached for directly from feature code.
class AppOverlay extends StatelessWidget {
  const AppOverlay({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => AppPanel(level: SurfaceLevel.overlay, padding: padding, child: child);
}
