import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent_client.dart';
import '../../core/insights_models.dart';

/// `GET /api/insights/funnel` — fetched once per screen visit, refreshed by
/// invalidating this provider, same pattern the Dependencies tab uses rather
/// than a poll: nothing about the underlying Postgres data changes fast
/// enough to justify a WS channel or a timer.
final funnelSummaryProvider = FutureProvider<FunnelSummary>((ref) async {
  final dio = ref.read(agentClientProvider);
  final response = await dio.get('/api/insights/funnel');
  return FunnelSummary.fromJson(response.data as Map<String, dynamic>);
});

/// `GET /api/insights/ranking` — one row per entity with real scan activity.
final entityRankingProvider = FutureProvider<List<EntityRanking>>((ref) async {
  final dio = ref.read(agentClientProvider);
  final response = await dio.get('/api/insights/ranking');
  return [for (final row in response.data as List) EntityRanking.fromJson(row as Map<String, dynamic>)];
});

/// How many days of history the burn-down charts show — a user choice, not
/// server state, so a plain `Notifier` rather than a family key the provider
/// itself would need to re-fetch through.
class BurndownDaysNotifier extends Notifier<int> {
  @override
  int build() => 30;

  void select(int days) => state = days;
}

final burndownDaysProvider = NotifierProvider<BurndownDaysNotifier, int>(BurndownDaysNotifier.new);

final burndownProvider = FutureProvider<Burndown>((ref) async {
  final days = ref.watch(burndownDaysProvider);
  final dio = ref.read(agentClientProvider);
  final response = await dio.get('/api/insights/burndown', queryParameters: {'days': days});
  return Burndown.fromJson(response.data as Map<String, dynamic>);
});

/// The agent's `detail` sentence when present, matching `describeAgentError`'s
/// convention in `services_controller.dart`.
String describeInsightsError(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) return data['detail'] as String;
    return error.message ?? 'request failed';
  }
  return error.toString();
}
