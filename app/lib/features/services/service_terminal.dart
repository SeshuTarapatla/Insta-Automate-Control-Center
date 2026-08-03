import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../core/agent_client.dart';
import '../../core/agent_ws.dart';
import '../../core/app_snack_bar.dart';
import '../../core/app_theme.dart';
import '../../core/async_state_view.dart';
import '../../core/service_models.dart';
import 'services_controller.dart';

/// Matches the agent's own ring: 5000 chunks / 512 KB of scrollback, which is
/// roughly this many rendered lines.
const _maxLines = 8000;

/// One resize per settle, not one per frame — dragging the window would
/// otherwise fire a POST for every pixel.
const _resizeDebounce = Duration(milliseconds: 250);

/// A highlight per match is a real cost; past a few hundred hits the query is
/// too broad to be navigating anyway.
const _maxSearchHits = 400;

/// The service's ConPTY stream, rendered by a real terminal emulator rather
/// than listed as strings (DECISIONS D15).
///
/// The agent keeps its output verbatim — colour, cursor moves, carriage
/// returns — so this replays the ring on mount, follows `services.logs.<name>`
/// live, and reports its own measured grid back with `POST /resize` so that
/// anything drawing to the full width wraps where it should.
///
/// Give it a `ValueKey(name)`: switching services must start a new emulator,
/// not append one service's output to another's.
class ServiceTerminal extends ConsumerStatefulWidget {
  const ServiceTerminal({super.key, required this.status});

  final ServiceStatus status;

  @override
  ConsumerState<ServiceTerminal> createState() => _ServiceTerminalState();
}

class _ServiceTerminalState extends ConsumerState<ServiceTerminal> {
  late final Terminal _terminal = Terminal(maxLines: _maxLines, onResize: _onResize);
  final _controller = TerminalController();
  final _scroll = ScrollController();
  final _searchFocus = FocusNode();
  final _searchField = TextEditingController();

  int _lastSeq = 0;
  bool _loading = true;
  bool _hasOutput = false;
  String? _loadError;

  /// Live chunks that arrive while the replay request is in flight are held
  /// back: writing them first would put the tail of the stream above its own
  /// history, and the sequence filter would then discard that history.
  bool _replaying = true;
  final List<LogChunk> _pending = [];

  Timer? _resizeTimer;
  int _rows = 0;
  int _cols = 0;

  bool _searchOpen = false;
  final List<_Match> _matches = [];
  int _matchIndex = 0;
  final List<TerminalHighlight> _highlights = [];

  @override
  void initState() {
    super.initState();
    _replay();
  }

  @override
  void dispose() {
    _resizeTimer?.cancel();
    _clearHighlights();
    _searchField.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ feed

  Future<void> _replay() async {
    setState(() {
      _replaying = true;
      _loadError = null;
    });
    try {
      final dio = ref.read(agentClientProvider);
      final response = await dio.get(
        '/api/services/${widget.status.name}/logs',
        queryParameters: _lastSeq > 0 ? {'since': _lastSeq} : null,
      );
      final chunks = (response.data['chunks'] as List)
          .map((chunk) => LogChunk.fromJson(chunk as Map<String, dynamic>))
          .toList();
      _write(chunks);
      _pending.sort((a, b) => a.seq.compareTo(b.seq));
      _write(_pending);
      _pending.clear();
      if (mounted) setState(() => _loading = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = describeAgentError(error);
        });
      }
    } finally {
      _replaying = false;
    }
  }

  void _write(List<LogChunk> chunks) {
    var wrote = false;
    for (final chunk in chunks) {
      if (chunk.seq <= _lastSeq) continue;
      _lastSeq = chunk.seq;
      _terminal.write(chunk.data);
      wrote = true;
    }
    if (wrote && !_hasOutput) {
      _hasOutput = true;
      if (mounted) setState(() {});
    }
  }

  void _onEvent(AgentEvent event) {
    if (event.channel != 'services.logs.${widget.status.name}') return;
    final chunks = (event.data as List)
        .map((chunk) => LogChunk.fromJson(chunk as Map<String, dynamic>))
        .toList();
    if (_replaying) {
      _pending.addAll(chunks);
      return;
    }
    _write(chunks);
  }

  // ---------------------------------------------------------------- resize

  /// The emulator measures its own grid from the pane; the process is then told
  /// to match. Without this the child wraps at its spawn width and the pane
  /// fills with broken lines.
  void _onResize(int cols, int rows, int pixelWidth, int pixelHeight) {
    if (cols == _cols && rows == _rows) return;
    _cols = cols;
    _rows = rows;
    _resizeTimer?.cancel();
    _resizeTimer = Timer(_resizeDebounce, _pushResize);
  }

  Future<void> _pushResize() async {
    // The agent's contract; a pane too narrow to be worth reporting is left at
    // whatever the process already has.
    if (_cols < 20 || _rows < 1) return;
    try {
      await ref.read(agentClientProvider).post(
        '/api/services/${widget.status.name}/resize',
        data: {'rows': _rows.clamp(1, 500), 'cols': _cols.clamp(20, 1000)},
      );
    } catch (_) {
      // Cosmetic: a service with no live process has nothing to resize, and a
      // dropped agent already shows in the connection banner.
    }
  }

  // ---------------------------------------------------------------- search

  void _clearHighlights() {
    for (final highlight in _highlights) {
      highlight.dispose();
    }
    _highlights.clear();
  }

  void _runSearch(String query) {
    _clearHighlights();
    _matches.clear();
    _matchIndex = 0;

    final needle = query.toLowerCase();
    if (needle.isNotEmpty) {
      final buffer = _terminal.buffer;
      for (var y = 0; y < buffer.height && _matches.length < _maxSearchHits; y++) {
        final line = buffer.lines[y].getText().toLowerCase();
        var from = line.indexOf(needle);
        while (from >= 0 && _matches.length < _maxSearchHits) {
          _matches.add(_Match(y, from, needle.length));
          from = line.indexOf(needle, from + needle.length);
        }
      }
      final highlightColor = Theme.of(context).palette.terminal.searchHitBackground.withValues(alpha: 0.4);
      for (final match in _matches) {
        _highlights.add(
          _controller.highlight(
            p1: _terminal.buffer.createAnchor(match.x, match.y),
            p2: _terminal.buffer.createAnchor(match.x + match.length, match.y),
            color: highlightColor,
          ),
        );
      }
    }

    setState(() {});
    if (_matches.isNotEmpty) _revealMatch();
  }

  void _step(int delta) {
    if (_matches.isEmpty) return;
    setState(() => _matchIndex = (_matchIndex + delta) % _matches.length);
    _revealMatch();
  }

  /// The scroll extent is `lines × cellHeight − viewport`, so the line height
  /// can be recovered exactly from the position rather than guessed from the
  /// font metrics.
  void _revealMatch() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final lines = _terminal.buffer.height;
    if (lines == 0) return;
    final cellHeight = (position.maxScrollExtent + position.viewportDimension) / lines;
    if (cellHeight <= 0) return;
    final target = _matches[_matchIndex].y * cellHeight - position.viewportDimension / 2;
    position.jumpTo(target.clamp(0.0, position.maxScrollExtent));
  }

  void _toggleSearch({bool? open}) {
    final next = open ?? !_searchOpen;
    setState(() => _searchOpen = next);
    if (next) {
      _searchFocus.requestFocus();
      if (_searchField.text.isNotEmpty) _runSearch(_searchField.text);
    } else {
      _clearHighlights();
      _matches.clear();
      setState(() {});
    }
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _terminal.buffer.getText()));
    if (mounted) AppSnackBar.show(context, 'Terminal contents copied');
  }

  // ------------------------------------------------------------------ view

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AgentEvent>>(agentEventsProvider, (previous, next) {
      next.whenData(_onEvent);
    });

    // A dropped WebSocket means missed chunks. Reconnecting asks for everything
    // after the last sequence rendered, so the gap closes instead of persisting
    // until the next restart.
    ref.listen<AsyncValue<void>>(agentWsProvider, (previous, next) {
      if (previous is AsyncLoading && next is AsyncData && !_replaying) _replay();
    });

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final terminalPalette = theme.palette.terminal;

    return Container(
      decoration: BoxDecoration(
        color: terminalPalette.panelBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _header(theme),
          if (_searchOpen) _searchBar(theme),
          if (_showsHistory) _historyNotice(theme),
          Expanded(child: _body(theme)),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme) {
    final scheme = theme.colorScheme;
    final live = widget.status.terminalAvailable;

    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: BoxDecoration(
        color: theme.palette.terminal.headerBackground,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.terminal,
            size: 16,
            color: live ? theme.palette.statusGood : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            live ? 'Terminal — live' : 'Terminal',
            style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (_cols > 0) ...[
            const SizedBox(width: 10),
            Text(
              '$_cols×$_rows',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'Consolas',
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
          const Spacer(),
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            tooltip: 'Find  (Ctrl+F)',
            onPressed: _showsTerminal ? () => _toggleSearch() : null,
            icon: const Icon(Icons.search),
          ),
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            tooltip: 'Copy everything',
            onPressed: _showsTerminal ? _copyAll : null,
            icon: const Icon(Icons.content_copy_outlined),
          ),
        ],
      ),
    );
  }

  Widget _searchBar(ThemeData theme) {
    final scheme = theme.colorScheme;
    final hits = _matches.isEmpty
        ? (_searchField.text.isEmpty ? '' : 'no matches')
        : '${_matchIndex + 1} of ${_matches.length}'
              '${_matches.length == _maxSearchHits ? '+' : ''}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.palette.terminal.headerBackground,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchField,
              focusNode: _searchFocus,
              style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'Consolas'),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Find in terminal',
              ),
              onChanged: _runSearch,
              onSubmitted: (_) => _step(1),
            ),
          ),
          Text(
            hits,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            tooltip: 'Previous',
            onPressed: _matches.isEmpty ? null : () => _step(-1),
            icon: const Icon(Icons.keyboard_arrow_up),
          ),
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            tooltip: 'Next  (Enter)',
            onPressed: _matches.isEmpty ? null : () => _step(1),
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            tooltip: 'Close  (Esc)',
            onPressed: () => _toggleSearch(open: false),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  /// A process the agent never had a console for has nothing in its ring but
  /// the agent's own notes about it — so the pane explains itself instead of
  /// rendering one dim line and calling that a terminal. Adopted no longer
  /// qualifies (CP 2.6): the service host survives the agent, so an adopted
  /// service's terminal history is recovered, not lost.
  bool get _detached => widget.status.origin == ServiceOrigin.external;

  /// A supervised service that has exited keeps its output. That is the point
  /// of self-heal being switchable off, so the pane says the output is history
  /// rather than pretending it is live.
  bool get _showsHistory => _showsTerminal && !widget.status.terminalAvailable;

  bool get _showsTerminal => _hasOutput && !_detached;

  Widget _historyNotice(ThemeData theme) {
    final scheme = theme.colorScheme;
    final message = widget.status.exitCode == null
        ? 'The process is not running. This is its final output, kept so you can read what happened.'
        : 'Exited with code ${widget.status.exitCode}. This is its final output, kept so you can '
              'read what happened.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: Row(
        children: [
          Icon(Icons.history_toggle_off, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading) {
      return const Center(child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_loadError != null) {
      return ErrorView(title: 'Could not load output', message: _loadError!);
    }
    if (_detached || !_hasOutput) return _emptyExplanation();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _toggleSearch(open: true),
        const SingleActivator(LogicalKeyboardKey.escape): () => _toggleSearch(open: false),
      },
      child: TerminalView(
        _terminal,
        controller: _controller,
        scrollController: _scroll,
        theme: _terminalTheme(theme),
        textStyle: const TerminalStyle(fontSize: 13, fontFamily: 'Consolas'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        // Nothing here is interactive: these panes replace terminal tabs the
        // user only ever read, and the agent exposes no write path to the pty.
        readOnly: true,
        backgroundOpacity: 0,
        shortcuts: {
          // Ctrl+C is free precisely because there is no process to interrupt,
          // and copy is what a Windows user will press for.
          const SingleActivator(LogicalKeyboardKey.keyC, control: true): CopySelectionTextIntent.copy,
          const SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true):
              CopySelectionTextIntent.copy,
          const SingleActivator(LogicalKeyboardKey.keyA, control: true):
              const SelectAllTextIntent(SelectionChangedCause.keyboard),
        },
      ),
    );
  }

  /// The pane never shows a blank box: when there is nothing to render it says
  /// which of the four reasons applies.
  Widget _emptyExplanation() {
    final status = widget.status;
    return switch (status.origin) {
      ServiceOrigin.adopted => EmptyView(
        icon: Icons.link,
        title: 'Adopted, not spawned',
        body:
            'This process was left running by an earlier agent run (pid ${status.pid}). Its console '
            'belonged to that run, so there is no output to stream. Restart it when convenient and '
            'the agent will own its terminal from then on.',
      ),
      ServiceOrigin.external => EmptyView(
        icon: Icons.open_in_new,
        title: 'Running outside the agent',
        body:
            'Port ${status.port} is held by ${status.portOwner?.display ?? 'another process'}, which the '
            'agent did not start — most likely the dev-startup shortcut. Take over to replace it with '
            'a supervised copy and stream its output here.',
      ),
      _ => const EmptyView(
        icon: Icons.terminal,
        title: 'Nothing to show yet',
        body: 'The agent captures a service\'s output from the moment it starts it. Start it and this '
            'pane fills in.',
      ),
    };
  }

  TerminalTheme _terminalTheme(ThemeData theme) => theme.palette.terminal.toXterm(
    cursor: theme.colorScheme.primary,
    selection: theme.colorScheme.primary.withValues(alpha: 0.35),
  );
}

class _Match {
  const _Match(this.y, this.x, this.length);
  final int y;
  final int x;
  final int length;
}
