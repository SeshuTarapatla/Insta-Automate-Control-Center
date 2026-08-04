// COMPONENTS.md §8 — feedback. Moved from `core/async_state_view.dart`
// (CLAUDE.md's "do not undo" list is explicit the shape is right) and
// widened with `emptyWhen`/`emptyView` and a skeleton loading mode.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/tokens.dart';

/// The loading spinner every page's `AsyncValue.when(...)` call site was
/// hand-rolling identically. Pass [skeleton] for surfaces with a known shape
/// before data arrives (the library grid, the ranking table, the flows
/// pipeline, the services list) — a skeleton reads as faster than a spinner
/// at identical latency, because it shows *what's coming*, not just *that
/// something is*.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.skeleton});

  final Widget? skeleton;

  @override
  Widget build(BuildContext context) {
    if (skeleton == null) return const Center(child: CircularProgressIndicator());
    final tokens = Theme.of(context).tokens;
    return _Shimmer(reduced: tokens.motion.reduced, child: skeleton!);
  }
}

/// A placeholder block for hand-building a skeleton layout — a row of these
/// shaped like the real content (a title-width bar, a few row-height bars)
/// reads as "this page's shape is loading" rather than a blank spinner.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 12, this.radius});

  final double? width;
  final double height;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: tokens.surface.raised, borderRadius: BorderRadius.circular(radius ?? tokens.geometry.radiusSm)),
    );
  }
}

/// A slow opacity breathe over [child] — the one piece of motion a skeleton
/// needs to read as "loading" rather than "this is the real, oddly blank
/// content." Collapses to static under `motion.reduced`.
class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.child, required this.reduced});

  final Widget child;
  final bool reduced;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reduced) return Opacity(opacity: 0.6, child: widget.child);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Opacity(opacity: 0.5 + 0.35 * _controller.value, child: widget.child),
    );
  }
}

/// Icon + title + message, centered and width-capped — the shape
/// `ops_tab.dart`'s private `_placeholder` already had (the richest of the
/// several near-identical copies found across the app), shared so every
/// page's error and empty states agree instead of each re-implementing it.
class _IconMessage extends StatelessWidget {
  const _IconMessage({required this.icon, required this.iconColor, required this.title, this.body, this.action});

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: EdgeInsets.all(tokens.space.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: tokens.space.iconLg, color: iconColor),
              SizedBox(height: tokens.space.md),
              Text(title, style: theme.textTheme.titleSmall, textAlign: TextAlign.center),
              if (body != null) ...[
                SizedBox(height: tokens.space.xs),
                Text(body!, textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary)),
              ],
              if (action != null) ...[SizedBox(height: tokens.space.lg), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// An error with an optional retry action — every `.when(error: ...)` branch
/// in the app either had this exact shape already or was missing the retry
/// button `settings_page.dart`'s config-load error turned out to lack.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry, this.title = 'Could not load this'});

  final String message;
  final String title;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _IconMessage(
      icon: Icons.error_outline,
      iconColor: scheme.error,
      title: title,
      body: message,
      action: onRetry == null ? null : OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
    );
  }
}

/// "Nothing here yet" — a real, expected state (an empty folder, a service
/// list before the first heartbeat), not a failure, so no error styling.
class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.title, this.body});

  final IconData icon;
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    return _IconMessage(icon: icon, iconColor: tokens.content.secondary, title: title, body: body);
  }
}

/// The common `AsyncValue.when(loading: spinner, error: message+retry, data: ...)`
/// shape as one call, so a page only ever writes its own `data` branch and
/// (when its error needs a friendlier sentence than `error.toString()`) a
/// `describeError` function — the same functions (`describeFlowsError`,
/// `describeAgentError`, `describeInsightsError`, ...) each page already had.
///
/// Widened over the `core/async_state_view.dart` original with [emptyWhen] +
/// [emptyView], so the very common
/// `data: (list) => list.isEmpty ? EmptyView(...) : ...` becomes part of the
/// call instead of boilerplate at each site, and [skeleton] for pages with a
/// known loading shape.
extension AsyncStateView<T> on AsyncValue<T> {
  Widget stateView({
    required Widget Function(T data) data,
    VoidCallback? onRetry,
    String Function(Object error)? describeError,
    bool Function(T data)? emptyWhen,
    Widget? emptyView,
    Widget? skeleton,
  }) {
    return when(
      loading: () => LoadingView(skeleton: skeleton),
      error: (error, _) =>
          ErrorView(message: describeError != null ? describeError(error) : '$error', onRetry: onRetry),
      data: (value) {
        if (emptyView != null && emptyWhen != null && emptyWhen(value)) return emptyView;
        return data(value);
      },
    );
  }
}
