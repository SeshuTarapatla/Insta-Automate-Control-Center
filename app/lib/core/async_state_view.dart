import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The loading spinner every page's `AsyncValue.when(...)` call site was
/// hand-rolling identically.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

/// Icon + title + message, centered and width-capped — the shape
/// `ops_tab.dart`'s private `_placeholder` already had (the richest of the
/// several near-identical copies found across the app), pulled out so every
/// page's error and empty states share it instead of re-implementing it.
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
    final scheme = theme.colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: iconColor),
              const SizedBox(height: 12),
              Text(title, style: theme.textTheme.titleSmall, textAlign: TextAlign.center),
              if (body != null) ...[
                const SizedBox(height: 6),
                Text(
                  body!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              if (action != null) ...[const SizedBox(height: 16), action!],
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
    final scheme = Theme.of(context).colorScheme;
    return _IconMessage(icon: icon, iconColor: scheme.onSurfaceVariant, title: title, body: body);
  }
}

/// The common `AsyncValue.when(loading: spinner, error: message+retry, data: ...)`
/// shape as one call, so a page only ever writes its own `data` branch and
/// (when its error needs a friendlier sentence than `error.toString()`) a
/// `describeError` function — the same functions (`describeFlowsError`,
/// `describeAgentError`, `describeInsightsError`, ...) each page already had.
extension AsyncStateView<T> on AsyncValue<T> {
  Widget stateView({
    required Widget Function(T data) data,
    VoidCallback? onRetry,
    String Function(Object error)? describeError,
  }) {
    return when(
      loading: () => const LoadingView(),
      error: (error, _) =>
          ErrorView(message: describeError != null ? describeError(error) : '$error', onRetry: onRetry),
      data: data,
    );
  }
}
