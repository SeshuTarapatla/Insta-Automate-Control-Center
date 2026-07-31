import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent_client.dart';
import '../../core/agent_ws.dart';
import '../../core/config_models.dart';

/// Bumped whenever a config.changed event arrives that this client didn't
/// just cause itself — the UI listens to this to show a toast without
/// coupling the toast to the config data flow.
class ExternalConfigChangeNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final externalConfigChangeProvider = NotifierProvider<ExternalConfigChangeNotifier, int>(
  ExternalConfigChangeNotifier.new,
);

/// Owns the whole of config.env: limits, the five flow switches, and the
/// ENTITY_QUEUE ordering. All three write through PATCH /api/config.
class ConfigController extends AsyncNotifier<ConfigResponse> {
  ConfigValues? _lastApplied;

  @override
  Future<ConfigResponse> build() async {
    ref.listen<AsyncValue<AgentEvent>>(agentEventsProvider, (previous, next) {
      next.whenData(_handleEvent);
    });

    final response = await _fetch();
    _lastApplied = response.values;
    return response;
  }

  Future<ConfigResponse> _fetch() async {
    final dio = ref.read(agentClientProvider);
    final response = await dio.get('/api/config');
    return ConfigResponse.fromJson(response.data as Map<String, dynamic>);
  }

  void _handleEvent(AgentEvent event) {
    if (event.channel != 'config.changed') return;

    final current = state.value;
    if (current == null) return;

    final incoming = ConfigValues.fromJson(event.data as Map<String, dynamic>);
    final isOwnEcho = _lastApplied != null && incoming.valueEquals(_lastApplied!);
    _lastApplied = incoming;
    state = AsyncValue.data(
      ConfigResponse(
        path: current.path,
        values: incoming,
        schema: current.schema,
        provenance: current.provenance,
      ),
    );

    if (!isOwnEcho) {
      ref.read(externalConfigChangeProvider.notifier).bump();
    }
  }

  /// All three throw DioException on validation failure — callers revert their
  /// own local (slider / field / switch) state on catch.
  Future<void> applyLimit(String key, int value) => _patch({
    'limits': {key: value},
  });

  Future<void> applySwitch(String key, bool value) => _patch({
    'switches': {key: value},
  });

  Future<void> applyQueue(List<String> names) => _patch({'entity_queue': names});

  Future<void> _patch(Map<String, dynamic> body) async {
    final dio = ref.read(agentClientProvider);
    final response = await dio.patch('/api/config', data: body);
    final updated = ConfigResponse.fromJson(response.data as Map<String, dynamic>);
    _lastApplied = updated.values;
    state = AsyncValue.data(updated);
  }
}

final configControllerProvider = AsyncNotifierProvider<ConfigController, ConfigResponse>(
  ConfigController.new,
);
