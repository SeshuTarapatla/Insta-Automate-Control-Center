import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent_client.dart';
import '../../core/agent_ws.dart';
import '../../core/flow_event_models.dart';
import '../../core/flowrun_models.dart';
import '../../core/scheduler_models.dart';
import '../flows/flows_controller.dart';

/// Which flow's activity the Live screen shows. Defaults to the pipeline's
/// first flow; `LivePage` auto-selects whichever flow is `running` the first
/// time real scheduler data arrives ("auto-follows the active run"), and a
/// manual tab click is authoritative after that.
class SelectedFlowNotifier extends Notifier<String> {
  @override
  String build() => flowOrder.first;

  void select(String flow) => state = flow;
}

final selectedFlowProvider = NotifierProvider<SelectedFlowNotifier, String>(SelectedFlowNotifier.new);

class LiveState {
  const LiveState({
    required this.flow,
    required this.runId,
    required this.logs,
    required this.events,
    this.selectedVerdicts = const {},
    this.runStartedAt,
  });

  final String flow;
  final String? runId;
  final List<FlowRunLogEntry> logs;
  final List<FlowEvent> events;

  /// The active click-to-filter selection on this run's result-card list —
  /// e.g. `{'MALE', 'FEMALE'}` on Classify, or `{'scraped'}` on Scrape.
  /// Multi-select (any card matching any selected key shows), empty means
  /// "show everything." Scoped to the currently displayed run: reset
  /// whenever the flow switches or a new run starts, same lifetime as
  /// [events] itself.
  final Set<String> selectedVerdicts;

  /// The run's real start time, from `GET /api/flow-runs/{id}` (Prefect's
  /// own record) — not a client-side "when did the app first notice this
  /// run" guess, which would drift from the actual trigger time by however
  /// long the next heartbeat/poll took to reach this screen. Powers the
  /// header ribbon's elapsed timer (V2.8/SCREENS §3); `null` before the
  /// fetch resolves or when there's no run to time.
  final DateTime? runStartedAt;

  LiveState copyWith({
    List<FlowRunLogEntry>? logs,
    List<FlowEvent>? events,
    Set<String>? selectedVerdicts,
    DateTime? runStartedAt,
  }) => LiveState(
    flow: flow,
    runId: runId,
    logs: logs ?? this.logs,
    events: events ?? this.events,
    selectedVerdicts: selectedVerdicts ?? this.selectedVerdicts,
    runStartedAt: runStartedAt ?? this.runStartedAt,
  );
}

/// Logs and events for whichever flow is selected, scoped to that flow's
/// current (or most recent) run. Replayed once over REST, then kept current
/// by the matching WS channels — the same replay-then-subscribe shape every
/// other channel in this app uses (D18).
class LiveController extends AsyncNotifier<LiveState> {
  String? _runId;

  @override
  Future<LiveState> build() async {
    final flow = ref.watch(selectedFlowProvider);

    // A real flow switch (not just new logs/events on the same flow) forces
    // a genuine loading state instead of leaving Riverpod's default
    // skip-loading-on-refresh behavior showing the *previous* flow's stale
    // LiveState until this rebuild resolves — otherwise the tab visibly
    // says e.g. "Scan" while the log console and visualization surface keep
    // showing Ingest's content underneath it for however long the fetch
    // below takes.
    if (state.value?.flow != flow) {
      state = const AsyncValue.loading();
    }

    ref.listen<AsyncValue<AgentEvent>>(agentEventsProvider, (previous, next) {
      next.whenData(_handleWsEvent);
    });
    ref.listen<AsyncValue<SchedulerSnapshot>>(flowsControllerProvider, (previous, next) {
      next.whenData(_handleSnapshot);
    });

    final snapshot = ref.read(flowsControllerProvider).value;
    final runId = snapshot?.flows[flow]?.lastRun?.id;
    _runId = runId;

    final logs = runId == null ? const <FlowRunLogEntry>[] : await _fetchLogs(runId);
    final events = await _fetchEvents(flow, runId);
    final startedAt = runId == null ? null : await _fetchRunStartedAt(runId);
    return LiveState(flow: flow, runId: runId, logs: logs, events: events, runStartedAt: startedAt);
  }

  Future<List<FlowRunLogEntry>> _fetchLogs(String runId) async {
    final dio = ref.read(agentClientProvider);
    final response = await dio.get('/api/flow-runs/$runId/logs');
    return FlowRunLogsReplay.fromJson(response.data as Map<String, dynamic>).entries;
  }

  Future<DateTime?> _fetchRunStartedAt(String runId) async {
    final dio = ref.read(agentClientProvider);
    final response = await dio.get('/api/flow-runs/$runId');
    return FlowRunSummary.fromJson(response.data as Map<String, dynamic>).startTime;
  }

  Future<List<FlowEvent>> _fetchEvents(String flow, String? runId) async {
    final dio = ref.read(agentClientProvider);
    final response = await dio.get('/api/events');
    final all = [
      for (final entry in response.data as List) FlowEvent.fromJson(entry as Map<String, dynamic>),
    ];
    return all.where((event) => event.flow == flow && event.flowRunId == runId).toList();
  }

  void _handleSnapshot(SchedulerSnapshot snapshot) {
    final current = state.value;
    if (current == null) return;
    final newRunId = snapshot.flows[current.flow]?.lastRun?.id;
    if (newRunId == _runId) return;
    _runId = newRunId;
    // A genuinely new run starting — clear any active counter filter along
    // with the stale event/log history it was scoped to.
    _reload(current.flow, newRunId, resetFilter: true);
  }

  Future<void> _reload(String flow, String? runId, {bool resetFilter = false}) async {
    final logs = runId == null ? const <FlowRunLogEntry>[] : await _fetchLogs(runId);
    final events = await _fetchEvents(flow, runId);
    final startedAt = runId == null ? null : await _fetchRunStartedAt(runId);
    final selectedVerdicts = resetFilter ? const <String>{} : state.value?.selectedVerdicts ?? const {};
    state = AsyncValue.data(
      LiveState(flow: flow, runId: runId, logs: logs, events: events, selectedVerdicts: selectedVerdicts, runStartedAt: startedAt),
    );
  }

  /// Toggles a counter's verdict/bucket key in or out of the active filter.
  void toggleVerdict(String key) {
    final current = state.value;
    if (current == null) return;
    final next = {...current.selectedVerdicts};
    if (!next.remove(key)) next.add(key);
    state = AsyncValue.data(current.copyWith(selectedVerdicts: next));
  }

  void _handleWsEvent(AgentEvent wsEvent) {
    final current = state.value;
    if (current == null) return;
    switch (wsEvent.channel) {
      case 'flowrun.logs':
        final data = wsEvent.data as Map<String, dynamic>;
        if (data['flow_run_id'] != current.runId) return;
        state = AsyncValue.data(current.copyWith(logs: [...current.logs, FlowRunLogEntry.fromJson(data)]));
      case 'flow.events':
        final event = FlowEvent.fromJson(wsEvent.data as Map<String, dynamic>);
        if (event.flow != current.flow || event.flowRunId != current.runId) return;
        state = AsyncValue.data(current.copyWith(events: [...current.events, event]));
    }
  }

  Future<void> refresh() async {
    final current = state.value;
    if (current == null) return;
    await _reload(current.flow, current.runId);
  }
}

final liveControllerProvider = AsyncNotifierProvider<LiveController, LiveState>(LiveController.new);
