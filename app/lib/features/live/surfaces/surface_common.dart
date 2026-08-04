import 'package:flutter/material.dart';

import '../../../core/app_snack_bar.dart';
import '../../../core/file_opener.dart';
import '../../../core/instagram_url.dart';

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

/// The source entity a scrape/follow candidate was found under —
/// `scrape_queued/<root>/<user>.jpg` and `follow_queued/<root>/<user>.jpg`
/// both carry it as their parent directory, and every event on that image
/// (`scrape.started`/`.skipped`/`.done`, `follow.attempt`/`.result`) reports
/// that same relative path in its `image` field, so this works regardless of
/// which specific event is on hand. `null` for anything not shaped that way.
String? rootFromImage(String? image) {
  if (image == null) return null;
  final parts = image.split('/');
  return parts.length >= 3 ? parts[parts.length - 2] : null;
}

/// Wraps a result card with the two open-profile gestures every per-item
/// surface needs: left-click opens [subject]'s own Instagram profile;
/// right-click — this app's desktop equivalent of a mobile long-press, per
/// `library_tile.dart`'s existing precedent for the same mapping — opens
/// [root]'s profile. Either gesture is simply not attached when its target
/// is null, so a surface with no root concept (Scan/Classify/Ingest) or an
/// item still mid-flight with no subject yet gets no gesture and no visual
/// feedback for that action, rather than a click that silently does nothing.
class ResultCardActions extends StatelessWidget {
  const ResultCardActions({super.key, required this.child, this.subject, this.root});

  final Widget child;
  final String? subject;
  final String? root;

  void _open(BuildContext context, String idOrFilename) {
    final uri = instagramUrl(idOrFilename);
    if (!FileOpener.openUrl(uri.toString()) && context.mounted) {
      AppSnackBar.show(context, 'Could not open $uri', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: subject != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: subject == null ? null : () => _open(context, subject!),
        onSecondaryTap: root == null ? null : () => _open(context, root!),
        child: child,
      ),
    );
  }
}

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
