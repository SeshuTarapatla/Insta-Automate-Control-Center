import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'agent_client.dart';

enum AgentConnection { connecting, connected, disconnected }

class ConnectionNotifier extends Notifier<AgentConnection> {
  Timer? _timer;

  @override
  AgentConnection build() {
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => check());
    ref.onDispose(() => _timer?.cancel());
    check();
    return AgentConnection.connecting;
  }

  Future<void> check() async {
    final dio = ref.read(agentClientProvider);
    try {
      final response = await dio.get('/api/health');
      state = response.statusCode == 200
          ? AgentConnection.connected
          : AgentConnection.disconnected;
    } catch (_) {
      state = AgentConnection.disconnected;
    }
  }
}

final connectionProvider =
    NotifierProvider<ConnectionNotifier, AgentConnection>(ConnectionNotifier.new);
