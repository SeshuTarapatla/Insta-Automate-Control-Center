import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/flowrun_models.dart';
import 'live_controller.dart';

const _levels = ['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL'];

Color _levelColor(ThemeData theme, String level) => switch (level) {
  'ERROR' || 'CRITICAL' => theme.colorScheme.error,
  'WARNING' => Colors.amber.shade700,
  'DEBUG' => theme.colorScheme.onSurfaceVariant,
  _ => theme.colorScheme.onSurface,
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

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Could not load logs: $error')),
      data: (state) {
        final entries = state.logs.where((e) => _enabledLevels.contains(e.level)).toList();
        final errors = state.logs.where((e) => e.level == 'ERROR' || e.level == 'CRITICAL').toList();
        _maybeFollow(entries.length);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
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
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                                padding: const EdgeInsets.only(top: 8, bottom: 2),
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
                padding: const EdgeInsets.all(8),
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _atBottom = true);
                    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
                  },
                  icon: const Icon(Icons.arrow_downward, size: 16),
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
    final scheduler = entry.source == 'scheduler';
    final levelColor = _levelColor(theme, entry.level);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: scheduler ? const EdgeInsets.only(left: 8) : EdgeInsets.zero,
      decoration: scheduler
          ? BoxDecoration(border: Border(left: BorderSide(color: scheme.outlineVariant, width: 2)))
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            child: Text(
              _formatTime(entry.ts),
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Container(
            width: 66,
            margin: const EdgeInsets.only(right: 10),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: levelColor.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(4)),
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
    return Material(
      color: scheme.errorContainer,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: scheme.onErrorContainer),
                  const SizedBox(width: 6),
                  Text(
                    '${widget.errors.length} error${widget.errors.length == 1 ? '' : 's'} this run',
                    style: widget.theme.textTheme.labelMedium?.copyWith(color: scheme.onErrorContainer),
                  ),
                  const Spacer(),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: scheme.onErrorContainer),
                ],
              ),
              if (_expanded)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final error in widget.errors)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            error.message,
                            style: widget.theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: scheme.onErrorContainer,
                            ),
                          ),
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
