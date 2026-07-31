import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'agent_config.dart';
import 'agent_token.dart';

class AgentEvent {
  const AgentEvent(this.channel, this.data);
  final String channel;
  final dynamic data;
}

/// Owns the single /ws connection (see ARCHITECTURE.md §3.2) and fans events
/// out to a broadcast stream. Auto-reconnects on drop with a fixed backoff —
/// the agent being briefly unreachable is the common case (restarts, sleep),
/// not something that needs exponential backoff tuning yet.
class AgentWsNotifier extends Notifier<AsyncValue<void>> {
  WebSocketChannel? _channel;
  StreamController<AgentEvent>? _eventsController;
  Timer? _reconnectTimer;

  StreamController<AgentEvent> get _events =>
      _eventsController ??= StreamController<AgentEvent>.broadcast();

  Stream<AgentEvent> get events => _events.stream;

  @override
  AsyncValue<void> build() {
    ref.onDispose(_disposeConnection);
    _connect();
    return const AsyncValue.loading();
  }

  Future<void> _connect() async {
    final token = await AgentToken.read();
    if (token == null) {
      _scheduleReconnect();
      return;
    }

    try {
      final uri = Uri.parse('ws://${AgentConfig.host}:${AgentConfig.port}/ws?token=$token');
      final channel = IOWebSocketChannel.connect(uri);
      _channel = channel;
      state = const AsyncValue.data(null);
      channel.stream.listen(
        (raw) {
          final json = jsonDecode(raw as String) as Map<String, dynamic>;
          _events.add(AgentEvent(json['channel'] as String, json['data']));
        },
        onError: (_) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _channel = null;
    state = const AsyncValue.loading();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), _connect);
  }

  void _disposeConnection() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _eventsController?.close();
  }
}

final agentWsProvider = NotifierProvider<AgentWsNotifier, AsyncValue<void>>(AgentWsNotifier.new);

/// Subscribing to this keeps the underlying connection alive for as long as a
/// listener cares about events.
final agentEventsProvider = StreamProvider<AgentEvent>((ref) {
  ref.watch(agentWsProvider);
  return ref.read(agentWsProvider.notifier).events;
});
