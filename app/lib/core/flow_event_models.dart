/// Mirrors the flow-event payloads (ARCHITECTURE.md §5, CP 4.2/4.3):
/// `GET /api/events[?since=]` and the `flow.events` WS channel. `flow` and
/// `kind` are the only fields every event carries — everything else is
/// per-kind, so this stays a thin wrapper over the raw map rather than one
/// class per kind.
library;

class FlowEvent {
  const FlowEvent({
    required this.seq,
    required this.id,
    required this.ts,
    required this.flow,
    required this.flowRunId,
    required this.kind,
    required this.entity,
    required this.subject,
    required this.image,
    required this.imageKey,
    required this.verdict,
    required this.reason,
    required this.counters,
    required this.extra,
  });

  final int seq;
  final String id;
  final dynamic ts;
  final String? flow;
  final String? flowRunId;
  final String kind;
  final String? entity;
  final String? subject;
  final String? image;
  final String? imageKey;
  final String? verdict;
  final String? reason;
  final Map<String, dynamic> counters;
  final Map<String, dynamic> extra;

  static FlowEvent fromJson(Map<String, dynamic> json) => FlowEvent(
    seq: json['seq'] as int,
    id: json['id'] as String? ?? '',
    ts: json['ts'],
    flow: json['flow'] as String?,
    flowRunId: json['flow_run_id'] as String?,
    kind: json['kind'] as String? ?? '',
    entity: json['entity'] as String?,
    subject: json['subject'] as String?,
    image: json['image'] as String?,
    imageKey: json['image_key'] as String?,
    verdict: json['verdict'] as String?,
    reason: json['reason'] as String?,
    counters: json['counters'] == null ? const {} : Map<String, dynamic>.from(json['counters'] as Map),
    extra: json['extra'] == null ? const {} : Map<String, dynamic>.from(json['extra'] as Map),
  );
}
