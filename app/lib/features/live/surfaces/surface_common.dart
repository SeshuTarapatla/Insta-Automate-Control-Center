import 'package:flutter/material.dart';

/// Shared by all five per-flow surfaces (CP 4.4) — a colored outcome pill.
/// Kept to one shared widget rather than one per surface, since every surface
/// needs exactly this and nothing fancier.
class OutcomeBadge extends StatelessWidget {
  const OutcomeBadge({super.key, required this.label, required this.tone});

  final String label;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      BadgeTone.good => (const Color(0xFF1F4D34), const Color(0xFF6EE7A8)),
      BadgeTone.bad => (scheme.errorContainer, scheme.onErrorContainer),
      BadgeTone.neutral => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: foreground, fontWeight: FontWeight.w600),
      ),
    );
  }
}

enum BadgeTone { good, bad, neutral }

BadgeTone toneFor(String? verdict) => switch (verdict) {
  'PRIVATE' || 'FEMALE' || 'FOLLOWED' || 'REQUESTED' || 'FOLLOWING' => BadgeTone.good,
  'PUBLIC' || 'MALE' || 'FAILED' => BadgeTone.bad,
  _ => BadgeTone.neutral,
};

/// A blank-state message, styled like every other empty pane in this app
/// (D17) — say why nothing is showing instead of an empty box.
class SurfaceEmpty extends StatelessWidget {
  const SurfaceEmpty({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
