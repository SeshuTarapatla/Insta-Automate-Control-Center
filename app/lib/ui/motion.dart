// COMPONENTS.md §11 — motion helpers. Built on `flutter_animate`, replacing
// hand-rolled `AnimationController`s for everything except `StatusDot`
// (`ui/status.dart`), which stays as-is per AUDIT's "do not undo" list.
// Everything here reads `tokens.motion` and collapses to zero duration under
// `motion.reduced` (DESIGN_SYSTEM §1.9's doctrine: motion may show
// causality, continuity or state — never decorate).
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/theme/tokens.dart';

/// A small fade + slide-in for list children — log lines, result cards,
/// notifications. [index] gives a short stagger, capped at the first 8 items
/// so a long list doesn't take seconds to finish appearing.
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0, this.axis = Axis.vertical});

  final Widget child;
  final int index;
  final Axis axis;

  static const _staggerCap = 8;
  static const _staggerStep = Duration(milliseconds: 30);

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    if (tokens.motion.reduced) return child;

    final delay = _staggerStep * index.clamp(0, _staggerCap);
    final offset = axis == Axis.vertical ? const Offset(0, 8) : const Offset(8, 0);

    return child
        .animate(delay: delay)
        .fadeIn(duration: tokens.motion.standard, curve: tokens.motion.enter)
        .move(begin: offset, end: Offset.zero, duration: tokens.motion.standard, curve: tokens.motion.enter);
  }
}

/// Cross-fades between whatever [child] currently is — hide/show via
/// [visible], or a genuine content swap (the scrape before→after morph,
/// ARCHITECTURE §9 — the in-progress strip card fading into the resolved
/// composite card) simply by [child] changing between builds.
class AnimatedReveal extends StatelessWidget {
  const AnimatedReveal({super.key, required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    final duration = tokens.motion.reduced ? Duration.zero : tokens.motion.standard;

    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: tokens.motion.enter,
      switchOutCurve: tokens.motion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: Tween<double>(begin: 0.98, end: 1.0).animate(animation), child: child),
      ),
      child: visible ? child : const SizedBox.shrink(),
    );
  }
}

/// Wraps a destination's content so switching to it — a nav rail selection,
/// a tab change — reads as a real transition (240ms fade + 8px slide) rather
/// than a hard cut. `AppShell` keys this by the active destination.
class PageTransition extends StatelessWidget {
  const PageTransition({super.key, required this.transitionKey, required this.child});

  final Object transitionKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    final duration = tokens.motion.reduced ? Duration.zero : tokens.motion.standard;

    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: tokens.motion.enter,
      switchOutCurve: tokens.motion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      layoutBuilder: (currentChild, previousChildren) =>
          Stack(alignment: Alignment.topLeft, children: [...previousChildren, ?currentChild]),
      child: KeyedSubtree(key: ValueKey(transitionKey), child: child),
    );
  }
}
