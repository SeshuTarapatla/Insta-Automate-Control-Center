import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/flowrun_models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/fields.dart';
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

/// A message that looks like a JSON blob (an object or array literal) rather
/// than prose — SCREENS §3: a payload like this from the ingest flow used to
/// render in the body proportional font, which reads as broken. Goes through
/// `MonoText` instead, same as every other structured/code-shaped value in
/// this app.
bool _looksStructured(String message) {
  final trimmed = message.trimLeft();
  return trimmed.startsWith('{') || trimmed.startsWith('[');
}

/// The flow-run log stream: auto-follows the newest line, filters by level,
/// groups consecutive lines from the same task under one label, keeps a
/// sticky strip of warnings/errors visible regardless of scroll position,
/// and searches (V2.8/SCREENS §3) — highlighting every match and stepping
/// through the matching *lines* with `Enter`/`Shift+Enter` — exactly what a
/// run that can run hundreds of lines long otherwise has no way to do.
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

  String _query = '';
  int _activeMatch = 0;

  // Grown (never shrunk below what's been seen) rather than rebuilt fresh
  // every build — a `GlobalKey` has to stay the *same instance* across
  // builds for `Scrollable.ensureVisible` to find the already-mounted
  // element it's pointing at.
  final List<GlobalKey> _itemKeys = [];

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
    // A search in progress means the user is deliberately reviewing a
    // specific match, possibly well above the newest line — auto-follow
    // would yank them back to the bottom the moment a new line arrived.
    if (_query.isNotEmpty || !_atBottom || !_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  List<int> _matchIndices(List<FlowRunLogEntry> entries) {
    if (_query.isEmpty) return const [];
    final query = _query.toLowerCase();
    return [
      for (var i = 0; i < entries.length; i++)
        if (entries[i].message.toLowerCase().contains(query)) i,
    ];
  }

  /// Virtualized `ListView`s don't build items outside the viewport, so a
  /// jump to an arbitrary index needs a two-step approximation: land close
  /// by proportional scroll offset (log lines are roughly uniform height),
  /// then correct exactly once the target item is actually built and its
  /// `GlobalKey` has a real element to find.
  void _scrollToEntry(int entryIndex, int totalEntries) {
    if (!_scroll.hasClients || totalEntries <= 1) return;
    final estimate = _scroll.position.maxScrollExtent * (entryIndex / (totalEntries - 1));
    _scroll.jumpTo(estimate.clamp(0, _scroll.position.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (entryIndex >= _itemKeys.length) return;
      final context = _itemKeys[entryIndex].currentContext;
      if (context != null) Scrollable.ensureVisible(context, alignment: 0.3, duration: const Duration(milliseconds: 150));
    });
  }

  void _step(List<int> matches, int totalEntries, int delta) {
    if (matches.isEmpty) return;
    setState(() => _activeMatch = (_activeMatch + delta) % matches.length);
    _scrollToEntry(matches[_activeMatch], totalEntries);
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

        while (_itemKeys.length < entries.length) {
          _itemKeys.add(GlobalKey());
        }

        final matches = _matchIndices(entries);
        if (_activeMatch >= matches.length) _activeMatch = 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(tokens.space.sm, tokens.space.sm, tokens.space.sm, tokens.space.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _LevelFilterMenu(
                    enabled: _enabledLevels,
                    onToggle: (level) => setState(() {
                      _enabledLevels.contains(level) ? _enabledLevels.remove(level) : _enabledLevels.add(level);
                    }),
                  ),
                  SizedBox(width: tokens.space.sm),
                  Expanded(
                    child: _LogSearchBar(
                      matchCount: matches.length,
                      activeMatch: _activeMatch,
                      onChanged: (value) => setState(() {
                        _query = value;
                        _activeMatch = 0;
                      }),
                      onNext: () => _step(matches, entries.length, 1),
                      onPrevious: () => _step(matches, entries.length, -1),
                    ),
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
                            : _query.isEmpty
                            ? 'No log lines yet for this run.'
                            : 'No log lines match "$_query".',
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
                        final isActiveMatch = matches.isNotEmpty && matches[_activeMatch] == index;
                        return Column(
                          key: _itemKeys[index],
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
                            _LogLine(entry: entry, query: _query, isActiveMatch: isActiveMatch),
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

/// The five level `FilterChip`s collapsed into one control (SCREENS §3) —
/// not `ui/fields.dart`'s `AppSelect`, whose `T value` shape is single-select
/// only; this needs several levels on at once. A stock `MenuAnchor` +
/// `CheckboxMenuButton` (`closeOnActivate: false`, so toggling one level
/// doesn't close the menu on the next) gets the same collapsed-dropdown
/// affordance without widening a shared component's API for one call site.
class _LevelFilterMenu extends StatelessWidget {
  const _LevelFilterMenu({required this.enabled, required this.onToggle});

  final Set<String> enabled;
  final ValueChanged<String> onToggle;

  String get _label {
    if (enabled.length == _levels.length) return 'All levels';
    if (enabled.isEmpty) return 'No levels';
    return '${enabled.length} levels';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    return MenuAnchor(
      menuChildren: [
        for (final level in _levels)
          CheckboxMenuButton(
            value: enabled.contains(level),
            closeOnActivate: false,
            onChanged: (_) => onToggle(level),
            child: Text(level),
          ),
      ],
      builder: (context, controller, _) => OutlinedButton(
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.symmetric(horizontal: tokens.space.sm),
          visualDensity: VisualDensity.compact,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_label, style: theme.textTheme.labelMedium),
            SizedBox(width: tokens.space.xs),
            AppIcon(AppIcons.chevronDown, size: IconSize.sm),
          ],
        ),
      ),
    );
  }
}

/// A search box that also carries the "n of m" match count and step
/// controls in its own suffix — new in V2.8/SCREENS §3 (there was
/// previously no way to find anything in a run's log short of scrolling by
/// eye). `Enter`/`Shift+Enter` step without needing to reach for the mouse;
/// `Escape` clears, matching `SearchField`'s existing precedent
/// (`ui/fields.dart`) — not reused directly since that widget has no
/// `onSubmitted`/keyboard hook to step through matches with.
class _LogSearchBar extends StatefulWidget {
  const _LogSearchBar({
    required this.matchCount,
    required this.activeMatch,
    required this.onChanged,
    required this.onNext,
    required this.onPrevious,
  });

  final int matchCount;
  final int activeMatch;
  final ValueChanged<String> onChanged;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  @override
  State<_LogSearchBar> createState() => _LogSearchBarState();
}

class _LogSearchBarState extends State<_LogSearchBar> {
  final _controller = TextEditingController();
  Timer? _debounce;

  void _onChanged(String value) {
    setState(() {}); // repaint the clear/step suffix immediately
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => widget.onChanged(value));
  }

  void _clear() {
    _controller.clear();
    _debounce?.cancel();
    widget.onChanged('');
    setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    final hasQuery = _controller.text.isNotEmpty;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): widget.onNext,
        const SingleActivator(LogicalKeyboardKey.enter, shift: true): widget.onPrevious,
        const SingleActivator(LogicalKeyboardKey.escape): _clear,
      },
      child: AppTextField(
        controller: _controller,
        hint: 'Search this run\'s logs',
        prefixIcon: Icons.search,
        onChanged: _onChanged,
        suffixIcon: !hasQuery
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.matchCount == 0 ? '0 of 0' : '${widget.activeMatch + 1} of ${widget.matchCount}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: tokens.content.secondary),
                  ),
                  IconButton(
                    tooltip: 'Previous match (Shift+Enter)',
                    icon: AppIcon(AppIcons.chevronUp, size: IconSize.sm),
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.matchCount == 0 ? null : widget.onPrevious,
                  ),
                  IconButton(
                    tooltip: 'Next match (Enter)',
                    icon: AppIcon(AppIcons.chevronDown, size: IconSize.sm),
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.matchCount == 0 ? null : widget.onNext,
                  ),
                  IconButton(
                    tooltip: 'Clear search (Esc)',
                    icon: Icon(Icons.close, size: tokens.space.iconSm),
                    visualDensity: VisualDensity.compact,
                    onPressed: _clear,
                  ),
                ],
              ),
      ),
    );
  }
}

String _formatTime(double ts) {
  final time = DateTime.fromMillisecondsSinceEpoch((ts * 1000).round());
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(time.hour)}:${pad(time.minute)}:${pad(time.second)}';
}

/// Every occurrence of [query] in [text] as its own span, styled with
/// [markStyle] — the rest inherits whatever style the parent `TextSpan`
/// carries. Counts and steps by *line*, not by individual occurrence — a
/// line with three hits is still just one stop when stepping with
/// `Enter`/`Shift+Enter`, matching how a quick visual scan of a log
/// naturally works.
List<InlineSpan> _highlightSpans(String text, String query, TextStyle markStyle) {
  if (query.isEmpty) return [TextSpan(text: text)];
  final lower = text.toLowerCase();
  final needle = query.toLowerCase();
  final spans = <InlineSpan>[];
  var start = 0;
  while (true) {
    final index = lower.indexOf(needle, start);
    if (index < 0) {
      spans.add(TextSpan(text: text.substring(start)));
      break;
    }
    if (index > start) spans.add(TextSpan(text: text.substring(start, index)));
    spans.add(TextSpan(text: text.substring(index, index + query.length), style: markStyle));
    start = index + query.length;
  }
  return spans;
}

/// One row: time · a colored level pill · the message in a normal (not
/// monospace) readable font with real line height — the plain colored-text-
/// inline version this replaced packed everything into 1px of line spacing
/// and was, in your words, difficult to read. This is deliberately far
/// simpler than Prefect's own log view (no task-run links, no per-line
/// sidebar) — just enough visual structure to scan quickly. A structured
/// (JSON-shaped) message switches to the monospace face instead
/// (SCREENS §3); search matches highlight inline and the active match's
/// whole row gets a tinted background so stepping through with
/// `Enter`/`Shift+Enter` is easy to track.
class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry, this.query = '', this.isActiveMatch = false});

  final FlowRunLogEntry entry;
  final String query;
  final bool isActiveMatch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = theme.tokens;
    final scheduler = entry.source == 'scheduler';
    final levelColor = _levelColor(theme, entry.level);
    final structured = _looksStructured(entry.message);

    final messageStyle = theme.textTheme.bodyMedium?.copyWith(
      color: scheduler ? scheme.onSurfaceVariant : scheme.onSurface,
      height: 1.4,
      fontFamily: structured ? tokens.typography.mono : null,
    );
    final markStyle = TextStyle(
      backgroundColor: tokens.status.warn.container,
      color: tokens.status.warn.onContainer,
      fontWeight: FontWeight.w700,
    );

    return Container(
      margin: EdgeInsets.only(bottom: tokens.space.xs),
      padding: EdgeInsets.symmetric(horizontal: isActiveMatch ? tokens.space.xs : 0, vertical: isActiveMatch ? 2 : 0),
      decoration: isActiveMatch
          ? BoxDecoration(
              color: tokens.accent.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(tokens.geometry.radiusSm),
            )
          : null,
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
            child: Text.rich(TextSpan(style: messageStyle, children: _highlightSpans(entry.message, query, markStyle))),
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
