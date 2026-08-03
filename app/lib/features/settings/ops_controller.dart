import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent_client.dart';
import '../../core/agent_ws.dart';
import '../../core/ops_models.dart';

/// The agent's real job registry — fetched once, not duplicated client-side,
/// so the button list can never list something the agent doesn't actually
/// know how to run.
final opsSpecsProvider = FutureProvider<List<OpsJobSpec>>((ref) async {
  final dio = ref.read(agentClientProvider);
  final response = await dio.get('/api/ops/specs');
  return [for (final spec in response.data as List) OpsJobSpec.fromJson(spec as Map<String, dynamic>)];
});

/// Job history, newest first — replay-then-subscribe (D18's established
/// shape, same as `NotificationController`): `GET /api/ops/jobs` once, then
/// `ops.jobs` status-transition broadcasts keep it current with no polling.
class OpsJobsController extends AsyncNotifier<List<OpsJob>> {
  @override
  Future<List<OpsJob>> build() async {
    ref.listen<AsyncValue<AgentEvent>>(agentEventsProvider, (previous, next) {
      next.whenData(_onEvent);
    });
    return _fetch();
  }

  Future<List<OpsJob>> _fetch() async {
    final dio = ref.read(agentClientProvider);
    final response = await dio.get('/api/ops/jobs');
    return [for (final job in response.data as List) OpsJob.fromJson(job as Map<String, dynamic>)];
  }

  void _onEvent(AgentEvent event) {
    if (event.channel != 'ops.jobs') return;
    final current = state.value;
    if (current == null) return;
    final updated = OpsJob.fromJson(event.data as Map<String, dynamic>);
    final rest = current.where((job) => job.id != updated.id).toList();
    state = AsyncValue.data([updated, ...rest]);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_fetch);
  }

  /// Starts a job and folds it into history immediately — the caller doesn't
  /// need to wait for the next `ops.jobs` broadcast just to see it appear.
  Future<OpsJob> start(String kind) async {
    final dio = ref.read(agentClientProvider);
    final response = await dio.post('/api/ops/jobs', data: {'kind': kind});
    final job = OpsJob.fromJson(response.data as Map<String, dynamic>);
    final current = state.value ?? const [];
    state = AsyncValue.data([job, ...current.where((existing) => existing.id != job.id)]);
    return job;
  }
}

final opsJobsControllerProvider = AsyncNotifierProvider<OpsJobsController, List<OpsJob>>(
  OpsJobsController.new,
);
