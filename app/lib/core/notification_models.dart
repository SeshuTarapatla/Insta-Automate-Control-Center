/// One entry from `NotificationStore` (CP 6.1, ARCHITECTURE §6) — either
/// replayed from `GET /api/notify` or delivered live on the `notifications`
/// WS channel, both the same shape.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.seq,
    required this.ts,
    required this.msg,
    required this.imageKey,
    required this.level,
    required this.tags,
    required this.dedupe,
    required this.transient,
    required this.read,
  });

  final String id;
  final int seq;
  final DateTime ts;
  final String msg;
  final String? imageKey;
  final String level;
  final List<String> tags;
  final String? dedupe;
  final bool transient;
  final bool read;

  AppNotification copyWith({bool? read}) => AppNotification(
    id: id,
    seq: seq,
    ts: ts,
    msg: msg,
    imageKey: imageKey,
    level: level,
    tags: tags,
    dedupe: dedupe,
    transient: transient,
    read: read ?? this.read,
  );

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
    id: json['id'] as String,
    seq: json['seq'] as int,
    ts: DateTime.fromMillisecondsSinceEpoch(((json['ts'] as num) * 1000).round()),
    msg: json['msg'] as String? ?? '',
    imageKey: json['image_key'] as String?,
    level: json['level'] as String? ?? 'info',
    tags: (json['tags'] as List<dynamic>? ?? const []).map((t) => t as String).toList(),
    dedupe: json['dedupe'] as String?,
    transient: json['transient'] as bool? ?? false,
    read: json['read'] as bool? ?? false,
  );
}
