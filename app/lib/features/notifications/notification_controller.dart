import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/agent_client.dart';
import '../../core/agent_ws.dart';
import '../../core/notification_models.dart';

/// Replay-then-subscribe (D18's established shape): `GET /api/notify` once,
/// then the `notifications` WS channel keeps it current. Unlike CP 4.2's
/// events (memory-only, worthless after the run that produced them), this
/// history is exactly what `NotificationStore` persists to disk (CP 6.1) —
/// there is nothing here for a restart to have discarded, so there's no
/// `since=` cursor to track across a reload the way flow-run logs need one.
class NotificationController extends AsyncNotifier<List<AppNotification>> {
  @override
  Future<List<AppNotification>> build() async {
    ref.listen<AsyncValue<AgentEvent>>(agentEventsProvider, (previous, next) {
      next.whenData(_handleWsEvent);
    });
    return _fetch();
  }

  Future<List<AppNotification>> _fetch() async {
    final dio = ref.read(agentClientProvider);
    final response = await dio.get('/api/notify');
    return [
      for (final entry in response.data as List) AppNotification.fromJson(entry as Map<String, dynamic>),
    ];
  }

  void _handleWsEvent(AgentEvent wsEvent) {
    if (wsEvent.channel != 'notifications') return;
    final current = state.value;
    if (current == null) return;
    final incoming = AppNotification.fromJson(wsEvent.data as Map<String, dynamic>);
    if (current.any((n) => n.id == incoming.id)) return;
    state = AsyncValue.data([...current, incoming]);
  }

  Future<void> markRead(String id) async {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([for (final n in current) n.id == id ? n.copyWith(read: true) : n]);
    final dio = ref.read(agentClientProvider);
    await dio.post('/api/notify/$id/read');
  }

  Future<void> markAllRead() async {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([for (final n in current) n.copyWith(read: true)]);
    final dio = ref.read(agentClientProvider);
    await dio.post('/api/notify/read-all');
  }
}

final notificationControllerProvider = AsyncNotifierProvider<NotificationController, List<AppNotification>>(
  NotificationController.new,
);

/// Per-tag mute, persisted client-side (`shared_preferences`, the same store
/// `WindowGeometry` uses) — there is no server-side concept of "muted",
/// since `NOTIFY_POLICY` already governs desktop-vs-Telegram routing (§6)
/// and this is purely "don't show me this category in the center."
class MutedTagsController extends AsyncNotifier<Set<String>> {
  static const _prefsKey = 'muted_notification_tags';

  @override
  Future<Set<String>> build() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_prefsKey) ?? const []).toSet();
  }

  Future<void> toggle(String tag) async {
    final current = Set<String>.from(state.value ?? const <String>{});
    if (!current.remove(tag)) current.add(tag);
    state = AsyncValue.data(current);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, current.toList());
  }
}

final mutedTagsControllerProvider = AsyncNotifierProvider<MutedTagsController, Set<String>>(
  MutedTagsController.new,
);

/// Plain (never-loading) view onto the muted set — every read site just
/// wants "what's muted right now," defaulting to nothing muted before
/// prefs finish loading rather than threading a loading state everywhere.
final mutedTagsProvider = Provider<Set<String>>((ref) {
  return ref.watch(mutedTagsControllerProvider).value ?? const <String>{};
});

bool notificationIsMuted(AppNotification notification, Set<String> mutedTags) =>
    notification.tags.any(mutedTags.contains);

/// Unread count for the bell badge — excludes muted tags, since a muted
/// category shouldn't keep drawing attention to itself.
final unreadNotificationCountProvider = Provider<int>((ref) {
  final notifications = ref.watch(notificationControllerProvider).value ?? const <AppNotification>[];
  final muted = ref.watch(mutedTagsProvider);
  return notifications.where((n) => !n.read && !notificationIsMuted(n, muted)).length;
});
