import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent_client.dart';
import '../../core/agent_ws.dart';
import '../../core/app_snack_bar.dart';
import '../../ui/feedback.dart';
import '../../core/ops_confirm.dart';
import '../../core/ops_models.dart';
import '../../core/relative_time.dart';
import '../../core/theme/tokens.dart';
import '../services/services_controller.dart' show describeAgentError;
import 'ops_controller.dart';

/// CP 7.1 — build/deploy/backup/restore/helm/kubectl actions as real
/// subprocesses with streamed output, replacing the manual shell commands
/// DECISIONS.md's D38/D55/D59/D68 show have repeatedly gone wrong. A
/// Settings tab, not a new nav destination — same reasoning D54 already
/// applied to Devices/notifications.
class OpsTab extends ConsumerStatefulWidget {
  const OpsTab({super.key});

  @override
  ConsumerState<OpsTab> createState() => _OpsTabState();
}

class _OpsTabState extends ConsumerState<OpsTab> {
  String? _selectedJobId;

  Future<void> _run(OpsJobSpec spec) async {
    if (spec.confirm) {
      final confirmed = await confirmOpsAction(context, spec.label, spec.consequence ?? '');
      if (!confirmed) return;
    }
    if (!mounted) return;
    try {
      final job = await ref.read(opsJobsControllerProvider.notifier).start(spec.id);
      if (!mounted) return;
      setState(() => _selectedJobId = job.id);
    } on DioException catch (error) {
      if (!mounted) return;
      final message = error.response?.statusCode == 409
          ? 'A job is already running — wait for it to finish first.'
          : 'Failed to start ${spec.label}: ${describeAgentError(error)}';
      if (context.mounted) AppSnackBar.show(context, message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final specsAsync = ref.watch(opsSpecsProvider);
    final jobsAsync = ref.watch(opsJobsControllerProvider);
    final jobs = jobsAsync.value ?? const <OpsJob>[];

    String? runningId;
    for (final job in jobs) {
      if (job.status == OpsJobStatus.running) runningId = job.id;
    }
    // Nothing picked yet (first load) defaults to the most recent job, so
    // reopening this tab shows what last happened without an extra click —
    // a plain `??=`, not a postFrameCallback, so it can only ever fire once
    // and can't re-fire on an unrelated rebuild the way D69's bug did.
    if (_selectedJobId == null && jobs.isNotEmpty) _selectedJobId = jobs.first.id;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ops jobs', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Build, deploy, backup and restart actions run as real commands against the live '
            'cluster, with output streamed below.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          // Capped and independently scrollable rather than left to size
          // itself: the real registry is ten jobs, several rows of cards at
          // this tab's minimum width — letting the `Wrap` claim whatever
          // height it wants pushed the log panel below into a real overflow
          // at the app's 1024×700 floor (D19's precedent again, caught by
          // `ops_layout_test.dart`, not `flutter analyze`). Same pattern
          // D45/D46 already used on the Live screen for the same reason.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 190),
            child: SingleChildScrollView(
              child: specsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Text('Failed to load job list: $error'),
                data: (specs) => Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final spec in specs)
                      _JobButton(spec: spec, busy: runningId != null, onPressed: () => _run(spec)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _OpsLogPanel(jobId: _selectedJobId)),
                const SizedBox(width: 16),
                SizedBox(
                  width: 280,
                  child: _JobHistory(
                    jobs: jobs,
                    loading: jobsAsync.isLoading && jobs.isEmpty,
                    selectedId: _selectedJobId,
                    onSelect: (id) => setState(() => _selectedJobId = id),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JobButton extends StatelessWidget {
  const _JobButton({required this.spec, required this.busy, required this.onPressed});

  final OpsJobSpec spec;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SizedBox(
      width: 260,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: busy ? null : onPressed,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      spec.confirm ? Icons.warning_amber_rounded : Icons.play_arrow_rounded,
                      size: 18,
                      color: spec.confirm ? scheme.error : scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(spec.label, style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  spec.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JobHistory extends StatelessWidget {
  const _JobHistory({required this.jobs, required this.loading, required this.selectedId, required this.onSelect});

  final List<OpsJob> jobs;
  final bool loading;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Text('History', style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          const Divider(height: 1),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : jobs.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No jobs run yet.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: jobs.length,
                    itemBuilder: (context, index) {
                      final job = jobs[index];
                      return _JobHistoryTile(job: job, selected: job.id == selectedId, onTap: () => onSelect(job.id));
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _JobHistoryTile extends StatelessWidget {
  const _JobHistoryTile({required this.job, required this.selected, required this.onTap});

  final OpsJob job;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, color) = switch (job.status) {
      OpsJobStatus.running => (Icons.sync, scheme.primary),
      OpsJobStatus.succeeded => (Icons.check_circle_outline, Colors.green),
      OpsJobStatus.failed => (Icons.error_outline, scheme.error),
      OpsJobStatus.interrupted => (Icons.link_off, scheme.onSurfaceVariant),
    };

    return Material(
      color: selected ? scheme.primaryContainer.withValues(alpha: 0.4) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job.label, style: theme.textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
                    Text(
                      relativeTime(job.startedAt),
                      style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
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

/// Replay-then-subscribe (D18's established shape, adapted from
/// `ServiceTerminal`'s pattern minus the resize/search/xterm machinery a
/// one-shot job log has no use for): `GET /api/ops/jobs/{id}/logs?since=`
/// once per selected job, then `ops.logs.{id}` keeps it current, re-replaying
/// after a dropped WebSocket the same way the services terminal does.
class _OpsLogPanel extends ConsumerStatefulWidget {
  const _OpsLogPanel({required this.jobId});

  final String? jobId;

  @override
  ConsumerState<_OpsLogPanel> createState() => _OpsLogPanelState();
}

class _OpsLogPanelState extends ConsumerState<_OpsLogPanel> {
  final _scroll = ScrollController();
  final List<OpsLogEntry> _entries = [];
  final List<OpsLogEntry> _pending = [];
  int _lastSeq = 0;
  bool _loading = true;
  bool _replaying = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    if (widget.jobId != null) _replay();
  }

  @override
  void didUpdateWidget(covariant _OpsLogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.jobId == widget.jobId) return;
    _entries.clear();
    _pending.clear();
    _lastSeq = 0;
    _loadError = null;
    if (widget.jobId != null) {
      _replay();
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _replay() async {
    final jobId = widget.jobId;
    if (jobId == null) return;
    setState(() {
      _replaying = true;
      _loadError = null;
    });
    try {
      final dio = ref.read(agentClientProvider);
      final response = await dio.get(
        '/api/ops/jobs/$jobId/logs',
        queryParameters: _lastSeq > 0 ? {'since': _lastSeq} : null,
      );
      final incoming = (response.data['entries'] as List)
          .map((entry) => OpsLogEntry.fromJson(entry as Map<String, dynamic>))
          .toList();
      _write(incoming);
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

  void _write(List<OpsLogEntry> entries) {
    if (entries.isEmpty) return;
    var wrote = false;
    for (final entry in entries) {
      if (entry.seq <= _lastSeq) continue;
      _lastSeq = entry.seq;
      _entries.add(entry);
      wrote = true;
    }
    if (!wrote) return;
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _onEvent(AgentEvent event) {
    final jobId = widget.jobId;
    if (jobId == null || event.channel != 'ops.logs.$jobId') return;
    final incoming = (event.data as List)
        .map((entry) => OpsLogEntry.fromJson(entry as Map<String, dynamic>))
        .toList();
    if (_replaying) {
      _pending.addAll(incoming);
      return;
    }
    _write(incoming);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AgentEvent>>(agentEventsProvider, (previous, next) {
      next.whenData(_onEvent);
    });
    ref.listen<AsyncValue<void>>(agentWsProvider, (previous, next) {
      if (previous is AsyncLoading && next is AsyncData && !_replaying && widget.jobId != null) _replay();
    });

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _header(theme),
          const Divider(height: 1),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: 12, right: 6),
      child: Row(
        children: [
          Icon(Icons.terminal, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text('Output', style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          const Spacer(),
          IconButton(
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            tooltip: 'Copy log output',
            onPressed: _entries.isEmpty ? null : _copyAll,
            icon: const Icon(Icons.content_copy_outlined),
          ),
        ],
      ),
    );
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _entries.map((e) => e.text).join('\n')));
    if (mounted) AppSnackBar.show(context, 'Log output copied');
  }

  Widget _body() {
    if (widget.jobId == null) {
      return const EmptyView(
        icon: Icons.terminal,
        title: 'No job selected',
        body: 'Run a job above, or pick one from history, to see its output here.',
      );
    }
    if (_loading) return const LoadingView();
    if (_loadError != null) {
      return ErrorView(title: 'Could not load output', message: _loadError!);
    }
    if (_entries.isEmpty) {
      return const EmptyView(
        icon: Icons.hourglass_empty,
        title: 'No output yet',
        body: 'Waiting for the job to produce output.',
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      itemCount: _entries.length,
      itemBuilder: (context, index) => _OpsLogLine(entry: _entries[index]),
    );
  }
}

/// One line: a divider style for a new step's `$ ...` announcement, red for
/// a non-zero exit, plain otherwise — deliberately simpler than
/// `LogConsole`'s flow-run rendering (no level filter, no task grouping),
/// since a job log is a flat, linear command transcript, not a flow's
/// structured event stream.
class _OpsLogLine extends StatelessWidget {
  const _OpsLogLine({required this.entry});

  final OpsLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isStep = entry.kind == 'step';
    final isError = entry.kind == 'error';
    final color = isError ? scheme.error : (isStep ? scheme.primary : scheme.onSurface);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        entry.text,
        style: theme.textTheme.bodySmall?.copyWith(
          fontFamily: theme.tokens.type.mono,
          color: color,
          fontWeight: isStep ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }
}
