import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent_client.dart';
import '../../core/agent_ws.dart';
import '../../core/scheduler_models.dart';

/// The whole scheduler snapshot, loaded once over REST then kept current by
/// `flows.state` broadcasts — the agent publishes the full picture on every
/// signature change (D27), so this replaces wholesale rather than patching by
/// flow the way `ServicesController` patches by service name.
class FlowsController extends AsyncNotifier<SchedulerSnapshot> {
  /// When each flow's `next_trigger_at` was first observed, keyed by flow.
  /// The state block only ever carries the deadline, not the span it was
  /// measured from, so the countdown ring's proportional fill needs this
  /// client-side to know what "full" means. Reset whenever the deadline
  /// string changes — including a mid-wait `FOLLOW_WAIT` edit or a
  /// `skip_wait`, which is exactly the "re-targets within one TICK" the
  /// manual test checks for.
  final Map<String, DateTime> _deadlineObservedAt = {};
  final Map<String, DateTime> _deadlineFor = {};

  @override
  Future<SchedulerSnapshot> build() async {
    ref.listen<AsyncValue<AgentEvent>>(agentEventsProvider, (previous, next) {
      next.whenData(_handleEvent);
    });

    final snapshot = await _fetch();
    _trackDeadlines(snapshot);
    return snapshot;
  }

  Future<SchedulerSnapshot> _fetch() async {
    final dio = ref.read(agentClientProvider);
    final response = await dio.get('/api/scheduler');
    return SchedulerSnapshot.fromJson(response.data as Map<String, dynamic>);
  }

  void _handleEvent(AgentEvent event) {
    if (event.channel != 'flows.state') return;
    final snapshot = SchedulerSnapshot.fromJson(event.data as Map<String, dynamic>);
    _trackDeadlines(snapshot);
    state = AsyncValue.data(snapshot);
    ref.read(pendingCommandProvider.notifier).reconcile(snapshot.flows);
  }

  void _trackDeadlines(SchedulerSnapshot snapshot) {
    for (final entry in snapshot.flows.entries) {
      final deadline = entry.value.nextTriggerAt;
      if (deadline == null) {
        _deadlineFor.remove(entry.key);
        continue;
      }
      if (_deadlineFor[entry.key] != deadline) {
        _deadlineFor[entry.key] = deadline;
        _deadlineObservedAt[entry.key] = DateTime.now();
      }
    }
  }

  /// The moment this deadline was first seen — the countdown ring's "started
  /// at", so `remaining / (nextTriggerAt - observedAt)` is the fill fraction.
  DateTime? observedAtFor(String flow) => _deadlineObservedAt[flow];

  Future<void> sendCommand(String flow, String command) async {
    ref.read(pendingCommandProvider.notifier).mark(flow, state.value?.flows[flow]);
    final dio = ref.read(agentClientProvider);
    await dio.post('/api/scheduler/$flow/command', data: {'command': command});
  }

  /// Stops a run genuinely in progress (D69) — not a scheduling command
  /// like [sendCommand] above, so it goes straight to the flow-runs REST
  /// surface instead of the scheduler's command queue.
  Future<void> cancelRun(String runId) async {
    final dio = ref.read(agentClientProvider);
    await dio.post('/api/flow-runs/$runId/cancel');
  }

  Future<void> refresh() async {
    final snapshot = await _fetch();
    _trackDeadlines(snapshot);
    state = AsyncValue.data(snapshot);
  }
}

final flowsControllerProvider = AsyncNotifierProvider<FlowsController, SchedulerSnapshot>(
  FlowsController.new,
);

class PendingCommand {
  const PendingCommand({required this.sentAt, required this.previousPhase, required this.previousGateReason});
  final DateTime sentAt;
  final String previousPhase;
  final String? previousGateReason;
}

/// Optimistic "a command is in flight" tracking, purely for UI feedback — the
/// agent's own queue/heartbeat round trip is fast, but the worker actually
/// picking up the flow run can lag a few seconds behind, long enough for an
/// impatient second click. A flow clears as soon as its phase or gate reason
/// visibly differs from what it was at send time (real confirmation), or
/// after a fixed timeout regardless, in case the agent/pod goes quiet
/// mid-flight — that check is time-based rather than event-driven so it
/// self-heals even if no further `flows.state` broadcast ever arrives.
class PendingCommandNotifier extends Notifier<Map<String, PendingCommand>> {
  static const _timeout = Duration(seconds: 8);

  @override
  Map<String, PendingCommand> build() => {};

  void mark(String flow, FlowState? current) {
    state = {
      ...state,
      flow: PendingCommand(
        sentAt: DateTime.now(),
        previousPhase: current?.phase ?? '',
        previousGateReason: current?.gate.reason,
      ),
    };
  }

  void reconcile(Map<String, FlowState> flows) {
    if (state.isEmpty) return;
    final next = Map<String, PendingCommand>.from(state);
    var changed = false;
    for (final entry in state.entries) {
      final pending = entry.value;
      final now = flows[entry.key];
      final confirmed =
          now != null &&
          (now.phase != pending.previousPhase || now.gate.reason != pending.previousGateReason);
      if (confirmed) {
        next.remove(entry.key);
        changed = true;
      }
    }
    if (changed) state = next;
  }

  bool isPending(String flow) {
    final pending = state[flow];
    if (pending == null) return false;
    return DateTime.now().difference(pending.sentAt) < _timeout;
  }
}

final pendingCommandProvider = NotifierProvider<PendingCommandNotifier, Map<String, PendingCommand>>(
  PendingCommandNotifier.new,
);

/// Drives the countdown ring/text redraw once a second — the deadline itself
/// only changes on a broadcast, but the remaining time has to keep ticking
/// down in between.
final flowsTickProvider = StreamProvider.autoDispose<int>(
  (ref) => Stream<int>.periodic(const Duration(seconds: 1), (tick) => tick),
);

String describeFlowsError(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) return data['detail'] as String;
    return error.message ?? 'request failed';
  }
  return error.toString();
}
