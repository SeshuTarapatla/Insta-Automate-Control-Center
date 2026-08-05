// COMPONENTS.md §2 — text and numerals. `TextRole` is the nine-role scale
// DESIGN_SYSTEM §2 maps onto Material's `TextTheme` slots; `NumericText` is
// the AUDIT §8 fix — the only way a number gets rendered in v2, so nothing
// jitters as it updates.
import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';

/// DESIGN_SYSTEM §2's nine roles, in the same order as the doc's table.
enum TextRole { pageTitle, sectionTitle, cardTitle, subTitle, body, bodyStrong, caption, label, micro }

extension TextRoleX on TextRole {
  TextStyle? resolve(TextTheme t) => switch (this) {
    TextRole.pageTitle => t.headlineSmall,
    TextRole.sectionTitle => t.titleLarge,
    TextRole.cardTitle => t.titleMedium,
    TextRole.subTitle => t.titleSmall,
    TextRole.body => t.bodyMedium,
    TextRole.bodyStrong => t.bodyLarge,
    TextRole.caption => t.bodySmall,
    TextRole.label => t.labelMedium,
    TextRole.micro => t.labelSmall,
  };
}

/// The one way to render text in v2 — chooses its style from [role] rather
/// than a call site picking a Material `TextTheme` slot and a literal color
/// separately. `ellipsis` defaults **true**: every overflow fix in
/// D87/D89/D93 was hand-adding `maxLines: 1` + `TextOverflow.ellipsis`: this
/// makes the safe choice the default one, so the next long value never
/// regresses a layout test. Pass `maxLines`/`ellipsis: false` to opt into
/// wrapping paragraph text.
class AppText extends StatelessWidget {
  const AppText(
    this.text, {
    super.key,
    this.role = TextRole.body,
    this.color,
    this.maxLines,
    this.ellipsis = true,
    this.textAlign,
    this.fontWeight,
  });

  final String text;
  final TextRole role;
  final Color? color;
  final int? maxLines;
  final bool ellipsis;
  final TextAlign? textAlign;
  final FontWeight? fontWeight;

  @override
  Widget build(BuildContext context) {
    final style = role.resolve(Theme.of(context).textTheme)?.copyWith(color: color, fontWeight: fontWeight);
    return Text(
      text,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines ?? (ellipsis ? 1 : null),
      overflow: ellipsis ? TextOverflow.ellipsis : null,
    );
  }
}

/// [AppText] rendered in the theme's monospace face — IDs, paths, log lines,
/// terminal-adjacent labels. `tokens.typography.mono` is the *only* place a
/// monospace family name is spelled (DESIGN_SYSTEM §1.5).
class MonoText extends StatelessWidget {
  const MonoText(
    this.text, {
    super.key,
    this.role = TextRole.body,
    this.color,
    this.maxLines,
    this.ellipsis = true,
    this.textAlign,
  });

  final String text;
  final TextRole role;
  final Color? color;
  final int? maxLines;
  final bool ellipsis;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = role.resolve(theme.textTheme)?.copyWith(color: color, fontFamily: theme.tokens.typography.mono);
    return Text(
      text,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines ?? (ellipsis ? 1 : null),
      overflow: ellipsis ? TextOverflow.ellipsis : null,
    );
  }
}

/// The fix for AUDIT §8 — every number in v2 renders through this, which is
/// what makes tabular figures (no jitter on update) and the mono face
/// non-optional rather than something a call site has to remember. Accepts a
/// `num` or a pre-formatted `String` (e.g. `'170/300'`) so a ratio doesn't
/// need to be split into two `NumericText`s either.
class NumericText extends StatelessWidget {
  const NumericText(this.value, {super.key, this.role = TextRole.body, this.color, this.textAlign})
    : assert(value is num || value is String, 'NumericText takes a num or a String');

  final Object value;
  final TextRole role;
  final Color? color;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = role
        .resolve(theme.textTheme)
        ?.copyWith(color: color, fontFamily: theme.tokens.typography.mono, fontFeatures: const [FontFeature.tabularFigures()]);
    return Text('$value', style: style, textAlign: textAlign, maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}

/// A [NumericText] that tweens between values instead of snapping — the
/// "implicit animation on counters" ARCHITECTURE §9 promised and AUDIT §10
/// found missing. Collapses to an instant snap under `motion.reduced`.
class AnimatedCounter extends StatelessWidget {
  const AnimatedCounter(this.value, {super.key, this.duration, this.role = TextRole.body, this.color});

  final int value;
  final Duration? duration;
  final TextRole role;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    final effectiveDuration = tokens.motion.reduced ? Duration.zero : (duration ?? tokens.motion.quick);

    // `TweenAnimationBuilder` only ever animates *toward* `end` — its first
    // build never animates (begin == end), and every rebuild after that
    // retargets from whatever value is currently on screen, which is exactly
    // "tween on change" with no extra state to manage here.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: value.toDouble(), end: value.toDouble()),
      duration: effectiveDuration,
      curve: tokens.motion.enter,
      builder: (context, animated, _) => NumericText(animated.round(), role: role, color: color),
    );
  }
}
