import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/flowrun_models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/feedback.dart';
import '../../ui/icons.dart';
import '../../ui/text.dart';
import 'live_controller.dart';

const _levels = ['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL'];

Color _levelColor(ThemeData theme, String level) => switch (level) {
  'ERROR' || 'CRITICAL' => theme.tokens.status.bad.fg,
  'WARNING' => theme.tokens.status.warn.fg,
  'DEBUG' => theme.tokens.content.tertiary,
  _ => theme.tokens.content.primary,
};

/// The flow-run log stream: auto-follows the newest line, filters by level,
/// groups consecutive lines from the same task under one label, and keeps a
/// sticky strip of warnings/errors visible regardless of scroll position —
/// exactly the lines you'd otherwise have to hunt for in a long scan.
class LogConsole extends ConsumerStatefulWidget {
  const LogConsole({super.key});

  @override
  ConsumerState<LogConsole> createState() => _LogConsoleState();
}

class _LogConsoleState extends ConsumerState<LogConsole> {
  final _scroll = ScrollController();
  final Set<String> _enabledLevels = {..._levels};
  bool _atBottom = true;
  int _lastLength = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final atBottom = !_scroll.hasClients || _scroll.position.pixels >= _scroll.position.maxScrollExtent - 24;
      if (atBottom != _atBottom) setState(() => _atBottom = atBottom);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeFollow(int newLength) {
    if (newLength == _lastLength) return;
    _lastLength = newLength;
    if (!_atBottom || !_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(liveControllerProvider);

    return async.stateView(
      describeError: (error) => 'Could not load logs: $error',
      onRetry: () => ref.invalidate(liveControllerProvider),
      data: (state) {
        final entries = state.logs.where((e) => _enabledLevels.contains(e.level)).toList();
        final errors = state.logs.where((e) => e.level == 'ERROR' || e.level == 'CRITICAL').toList();
        _maybeFollow(entries.length);
        final tokens = theme.tokens;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(tokens.space.sm, tokens.space.sm, tokens.space.sm, tokens.space.xs),
              child: Wrap(
                spacing: tokens.space.xs,
                runSpacing: tokens.space.xs,
                children: [
                  for (final level in _levels)
                    FilterChip(
                      label: Text(level, style: theme.textTheme.labelSmall),
                      visualDensity: VisualDensity.compact,
                      selected: _enabledLevels.contains(level),
                      onSelected: (on) => setState(() {
                        on ? _enabledLevels.add(level) : _enabledLevels.remove(level);
                      }),
                    ),
                ],
              ),
            ),
            if (errors.isNotEmpty) _StickyErrors(errors: errors, theme: theme),
            const Divider(height: 1),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        state.runId == null
                            ? 'No run to follow yet for ${state.flow} — waiting for it to trigger.'
                            : 'No log lines yet for this run.',
                        style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: EdgeInsets.symmetric(horizontal: tokens.space.sm, vertical: tokens.space.xs),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final previousTask = index == 0 ? null : entries[index - 1].task;
                        final showTaskLabel = entry.task != null && entry.task != previousTask;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showTaskLabel)
                              Padding(
                                padding: EdgeInsets.only(top: tokens.space.xs, bottom: tokens.space.xs / 2),
                                child: Text(
                                  entry.task!,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            _LogLine(entry: entry),
                          ],
                        );
                      },
                    ),
            ),
            if (!_atBottom)
              Padding(
                padding: EdgeInsets.all(tokens.space.xs),
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _atBottom = true);
                    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
                  },
                  icon: AppIcon(AppIcons.arrowDown, size: IconSize.sm),
                  label: const Text('Jump to latest'),
                ),
              ),
          ],
        );
      },
    );
  }
}

String _formatTime(double ts) {
  final time = DateTime.fromMillisecondsSinceEpoch((ts * 1000).round());
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(time.hour)}:${pad(time.minute)}:${pad(time.second)}';
}

/// One row: time · a colored level pill · the message in a normal (not
/// monospace) readable font with real line height — the plain colored-text-
/// inline version this replaced packed everything into 1px of line spacing
/// and was, in your words, difficult to read. This is deliberately far
/// simpler than Prefect's own log view (no task-run links, no per-line
/// sidebar) — just enough visual structure to scan quickly.
class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry});

  final FlowRunLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = theme.tokens;
    final scheduler = entry.source == 'scheduler';
    final levelColor = _levelColor(theme, entry.level);

    return Container(
      margin: EdgeInsets.only(bottom: tokens.space.xs),
      // Scheduler-merged lines (D30 — the scheduler pod's own trigger/gate
      // log, interleaved into the flow's ring) used to get a left border and
      // indent to mark them apart from the flow's own lines, which read as
      // inconsistent alignment rather than a useful distinction. The dimmer
      // text color below is enough of a source cue without disrupting the
      // left edge every line otherwise shares.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            child: NumericText(_formatTime(entry.ts), role: TextRole.caption, color: tokens.content.secondary),
          ),
          Container(
            width: 66,
            margin: EdgeInsets.only(right: tokens.space.sm),
            padding: EdgeInsets.symmetric(horizontal: tokens.space.xs, vertical: tokens.space.xs / 2),
            decoration: BoxDecoration(color: levelColor.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(tokens.geometry.radiusSm)),
            child: Text(
              entry.level,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(color: levelColor, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text(
              entry.message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheduler ? scheme.onSurfaceVariant : scheme.onSurface,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StickyErrors extends StatefulWidget {
  const _StickyErrors({required this.errors, required this.theme});

  final List<FlowRunLogEntry> errors;
  final ThemeData theme;

  @override
  State<_StickyErrors> createState() => _StickyErrorsState();
}

class _StickyErrorsState extends State<_StickyErrors> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = widget.theme.colorScheme;
    final tokens = widget.theme.tokens;
    return Material(
      color: scheme.errorContainer,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.space.sm, vertical: tokens.space.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppIcon(AppIcons.error, size: IconSize.sm, color: scheme.onErrorContainer),
                  SizedBox(width: tokens.space.xs),
                  Text(
                    '${widget.errors.length} error${widget.errors.length == 1 ? '' : 's'} this run',
                    style: widget.theme.textTheme.labelMedium?.copyWith(color: scheme.onErrorContainer),
                  ),
                  const Spacer(),
                  AppIcon(_expanded ? AppIcons.chevronUp : AppIcons.chevronDown, size: IconSize.sm, color: scheme.onErrorContainer),
                ],
              ),
              if (_expanded)
                Padding(
                  padding: EdgeInsets.only(top: tokens.space.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final error in widget.errors)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: tokens.space.xs / 2),
                          child: MonoText(error.message, role: TextRole.caption, color: scheme.onErrorContainer, ellipsis: false),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
