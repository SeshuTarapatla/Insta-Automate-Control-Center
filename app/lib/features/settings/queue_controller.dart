import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent_client.dart';
import '../../core/queue_models.dart';
import 'config_controller.dart';

/// Watches the config controller so the queue re-reads whenever ENTITY_QUEUE
/// changes — whether this client reordered it or an external edit did.
final queueProvider = FutureProvider<QueueData>((ref) async {
  ref.watch(configControllerProvider);

  final dio = ref.read(agentClientProvider);
  final response = await dio.get('/api/queue');
  return QueueData.fromJson(response.data as Map<String, dynamic>);
});
