// COMPONENTS.md §3 — status. Collapses the three treatments AUDIT §5 found
// (Material `Chip`, `service_tile.dart`'s private `_Pill`, `OutcomeBadge`'s
// own hardcoded colors) onto `AppTokens.status` (DESIGN_SYSTEM §1.4).
import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';

/// The five states every status-bearing widget in v2 renders from. `neutral`
/// is the one kind with no `StatusTokens` entry — it reads plain content/
/// surface tokens instead, for "nothing to report" (stopped, idle, none).
enum StatusKind { good, info, warn, bad, neutral }

extension StatusKindX on StatusKind {
  /// The status's own foreground — a status chip's icon/text, a dot's fill.
  Color fg(AppTokens t) => switch (this) {
    StatusKind.good => t.status.good.fg,
    StatusKind.info => t.status.info.fg,
    StatusKind.warn => t.status.warn.fg,
    StatusKind.bad => t.status.bad.fg,
    StatusKind.neutral => t.content.secondary,
  };

  /// A low-emphasis fill — chip/badge backgrounds.
  Color container(AppTokens t) => switch (this) {
    StatusKind.good => t.status.good.container,
    StatusKind.info => t.status.info.container,
    StatusKind.warn => t.status.warn.container,
    StatusKind.bad => t.status.bad.container,
    StatusKind.neutral => t.surface.raised,
  };

  /// Text/icon color on top of [container].
  Color onContainer(AppTokens t) => switch (this) {
    StatusKind.good => t.status.good.onContainer,
    StatusKind.info => t.status.info.onContainer,
    StatusKind.warn => t.status.warn.onContainer,
    StatusKind.bad => t.status.bad.onContainer,
    StatusKind.neutral => t.content.secondary,
  };
}

/// A state as one glanceable mark. Moved verbatim from
/// `features/services/status_dot.dart` (CLAUDE.md's "do not undo" list —
/// AUDIT calls this out as the one piece of genuinely meaningful motion
/// already in the app) and generalised from `ServiceState` to `StatusKind` +
/// an explicit [pulsing] flag, so anything with a transient state — a flow
/// mid-trigger, an ops job running, not just a service — can use it. States
/// where something is expected to change on its own breathe, so "working" is
/// distinguishable from "settled" without reading a label.
class StatusDot extends StatefulWidget {
  const StatusDot({super.key, required this.kind, this.pulsing = false, this.size = 10});

  final StatusKind kind;

  /// True for states expected to change on their own (starting, backoff,
  /// running) — a static dot reads as stuck for those.
  final bool pulsing;
  final double size;

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pulsing != widget.pulsing) _sync();
  }

  void _sync() {
    if (widget.pulsing) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.kind.fg(Theme.of(context).tokens);

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final glow = 0.45 - 0.3 * _pulse.value;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: glow),
                blurRadius: widget.size * (1.0 + _pulse.value),
                spreadRadius: widget.size * 0.18,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A colored pill pairing status with a word or icon — never color alone
/// (DESIGN_SYSTEM §1.4/§6). Replaces the Material `Chip` uses AUDIT §5 found
/// at 7 call sites and `service_tile.dart`'s private `_Pill`.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.kind, required this.label, this.icon, this.dense = false});

  final StatusKind kind;
  final String label;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    final fg = kind.onContainer(tokens);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? tokens.space.xs : tokens.space.sm, vertical: dense ? 1 : 3),
      decoration: BoxDecoration(color: kind.container(tokens), borderRadius: BorderRadius.circular(tokens.geometry.radiusSm)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: tokens.space.iconSm, color: fg),
            SizedBox(width: tokens.space.xs),
          ],
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg)),
        ],
      ),
    );
  }
}

/// A count or an unread marker — nav rail badges, unread notification counts.
/// `dot: true` renders just a small mark with no number, for "something's
/// there" without a specific count.
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, this.kind = StatusKind.neutral, this.dot = false});

  final int count;
  final StatusKind kind;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    if (!dot && count <= 0) return const SizedBox.shrink();
    final tokens = Theme.of(context).tokens;
    final bg = kind == StatusKind.neutral ? tokens.accent.primary : kind.fg(tokens);
    final fg = kind == StatusKind.neutral ? tokens.accent.onPrimary : tokens.content.onAccent;

    if (dot) {
      return Container(width: 8, height: 8, decoration: BoxDecoration(color: bg, shape: BoxShape.circle));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(tokens.geometry.radiusFull)),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontFamily: tokens.typography.mono),
      ),
    );
  }
}

/// A verdict pill — `PRIVATE`/`FEMALE`/`FAILED`/etc — on the Live screen's
/// per-item result cards. All five call sites in
/// `features/live/surfaces/` were retargeted here in V2.3 (D101), replacing
/// the two hardcoded hex literals the original `surface_common.dart` version
/// carried — this is the real destination, built against tokens throughout.
class OutcomeBadge extends StatelessWidget {
  const OutcomeBadge({super.key, required this.label, required this.kind});

  final String label;
  final StatusKind kind;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: kind.container(tokens), borderRadius: BorderRadius.circular(tokens.geometry.radiusSm)),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: kind.onContainer(tokens), fontWeight: FontWeight.w600),
      ),
    );
  }
}
