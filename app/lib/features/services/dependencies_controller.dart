import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent_client.dart';
import '../../core/dependency_models.dart';

/// Ten checks, each individually timed out at 10 s at the agent, so the whole
/// snapshot can take a while when something is genuinely down.
const _timeout = Duration(seconds: 30);

/// Everything the pipeline needs that the agent does *not* supervise. Read-only
/// by design (CP 2.3): the agent has no business restarting k3s or Syncthing,
/// so this answers "is it there" and stops.
class DependenciesController extends AsyncNotifier<DependencySnapshot> {
  @override
  Future<DependencySnapshot> build() => _fetch(refresh: false);

  Future<DependencySnapshot> _fetch({required bool refresh}) async {
    final dio = ref.read(agentClientProvider);
    final response = await dio.get(
      '/api/dependencies',
      queryParameters: refresh ? {'refresh': true} : null,
      options: Options(receiveTimeout: _timeout),
    );
    return DependencySnapshot.fromJson(response.data as Map<String, dynamic>);
  }

  /// Bypasses the agent's 5 s cache. The state is only replaced once the new
  /// snapshot is in hand — the caller shows its own spinner, because a panel
  /// that blanks itself while re-checking is worse than one that is briefly
  /// stale.
  Future<void> refresh() async {
    state = await AsyncValue.guard(() => _fetch(refresh: true));
  }
}

final dependenciesControllerProvider =
    AsyncNotifierProvider<DependenciesController, DependencySnapshot>(DependenciesController.new);
