import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent_client.dart';
import '../../core/agent_ws.dart';
import '../../core/service_models.dart';

/// Actions kill or spawn process trees, and `stop` waits out a 5 s terminate
/// grace before it escalates — well past the client's 2 s default. A functional
/// test may do real work (a cold vl-server inference, an adb round trip), so it
/// gets a longer budget still.
const _actionTimeout = Duration(seconds: 20);
const _testTimeout = Duration(seconds: 60);

/// Which tile the detail pane is showing. Held outside the list so a status
/// broadcast never disturbs the selection.
class SelectedServiceNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String name) => state = name;

  /// Called once the list arrives, so the page opens on something rather than
  /// on an empty pane.
  void selectIfUnset(String name) => state ??= name;
}

final selectedServiceProvider = NotifierProvider<SelectedServiceNotifier, String?>(
  SelectedServiceNotifier.new,
);

/// The three supervised services. Loaded once over REST, then kept current by
/// `services.status` broadcasts — the agent publishes one service's status per
/// event whenever its signature changes, so this patches by name rather than
/// refetching the list.
class ServicesController extends AsyncNotifier<List<ServiceStatus>> {
  @override
  Future<List<ServiceStatus>> build() async {
    ref.listen<AsyncValue<AgentEvent>>(agentEventsProvider, (previous, next) {
      next.whenData(_handleEvent);
    });

    final services = await _fetch();
    if (services.isNotEmpty) {
      ref.read(selectedServiceProvider.notifier).selectIfUnset(services.first.name);
    }
    return services;
  }

  Future<List<ServiceStatus>> _fetch() async {
    final dio = ref.read(agentClientProvider);
    final response = await dio.get('/api/services');
    return (response.data as List)
        .map((item) => ServiceStatus.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  void _handleEvent(AgentEvent event) {
    if (event.channel != 'services.status') return;
    _apply(ServiceStatus.fromJson(event.data as Map<String, dynamic>));
  }

  void _apply(ServiceStatus status) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final service in current) service.name == status.name ? status : service,
    ]);
  }

  /// Every action answers with the service's fresh status, so the tile updates
  /// without waiting for the next probe tick to broadcast it.
  Future<void> _act(String name, String action) async {
    final dio = ref.read(agentClientProvider);
    final response = await dio.post(
      '/api/services/$name/$action',
      options: Options(receiveTimeout: _actionTimeout),
    );
    _apply(ServiceStatus.fromJson(response.data as Map<String, dynamic>));
  }

  Future<void> start(String name) => _act(name, 'start');
  Future<void> stop(String name) => _act(name, 'stop');
  Future<void> restart(String name) => _act(name, 'restart');
  Future<void> takeover(String name) => _act(name, 'takeover');

  /// Returns the outcome so the caller can narrate pass *or* fail — the agent
  /// answers 200 either way, because a failed test is a result and its metrics
  /// are the point.
  Future<TestOutcome> runTest(String name) async {
    final dio = ref.read(agentClientProvider);
    final response = await dio.post(
      '/api/services/$name/test',
      options: Options(receiveTimeout: _testTimeout),
    );
    final outcome = TestOutcome.fromJson(response.data as Map<String, dynamic>);
    await refresh();
    return outcome;
  }

  Future<void> setSelfHeal(String name, bool value) => _configure(name, {'self_heal': value});

  Future<void> setAutostart(String name, bool value) => _configure(name, {'autostart': value});

  Future<void> _configure(String name, Map<String, dynamic> body) async {
    final dio = ref.read(agentClientProvider);
    final response = await dio.patch('/api/services/$name', data: body);
    _apply(ServiceStatus.fromJson(response.data as Map<String, dynamic>));
  }

  Future<void> refresh() async {
    final services = await _fetch();
    state = AsyncValue.data(services);
  }
}

final servicesControllerProvider = AsyncNotifierProvider<ServicesController, List<ServiceStatus>>(
  ServicesController.new,
);

/// A status is only broadcast when its signature changes, so a service that
/// stays healthy for an hour sends nothing — this is what keeps the uptime on
/// screen advancing in between.
final uptimeTickProvider = StreamProvider.autoDispose<int>(
  (ref) => Stream<int>.periodic(const Duration(seconds: 1), (tick) => tick),
);

/// The agent's 409s carry a sentence worth showing ("port 5037 is held by an
/// external process (pid 20840); use takeover to replace it"); anything else
/// falls back to the transport error.
String describeAgentError(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) return data['detail'] as String;
    if (error.type == DioExceptionType.receiveTimeout) return 'the agent did not answer in time';
    return error.message ?? 'request failed';
  }
  return error.toString();
}
