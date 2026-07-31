import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent_client.dart';
import '../../core/agent_ws.dart';
import '../../core/config_models.dart';

/// Bumped whenever a config.changed event arrives that this client didn't
/// just cause itself — the page listens to this to show a toast without
/// coupling the toast to the config data flow.
class ExternalConfigChangeNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final externalConfigChangeProvider = NotifierProvider<ExternalConfigChangeNotifier, int>(
  ExternalConfigChangeNotifier.new,
);

class LimitsController extends AsyncNotifier<ConfigResponse> {
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

  /// Applies one limit key. Throws DioException on validation failure — the
  /// caller reverts its own local (slider/field) state on catch.
  Future<void> applyLimit(String key, int value) async {
    final dio = ref.read(agentClientProvider);
    final response = await dio.patch(
      '/api/config',
      data: {
        'limits': {key: value},
      },
    );
    final updated = ConfigResponse.fromJson(response.data as Map<String, dynamic>);
    _lastApplied = updated.values;
    state = AsyncValue.data(updated);
  }
}

final limitsControllerProvider = AsyncNotifierProvider<LimitsController, ConfigResponse>(
  LimitsController.new,
);
