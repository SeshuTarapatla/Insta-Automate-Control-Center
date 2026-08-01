/// Mirrors the flow-run log tailer's payloads (ARCHITECTURE.md §5.2, CP 4.1):
/// `GET /api/flow-runs[/{id}[/logs]]` and the `flowrun.logs` WS channel.
library;

class FlowRunSummary {
  const FlowRunSummary({
    required this.id,
    required this.flow,
    required this.state,
    required this.startTime,
    required this.endTime,
    required this.durationS,
    required this.active,
  });

  final String id;
  final String? flow;
  final String? state;
  final DateTime? startTime;
  final DateTime? endTime;
  final double? durationS;
  final bool active;

  static FlowRunSummary fromJson(Map<String, dynamic> json) => FlowRunSummary(
    id: json['id'] as String,
    flow: json['flow'] as String?,
    state: json['state'] as String?,
    startTime: json['start_time'] == null ? null : DateTime.tryParse(json['start_time'] as String),
    endTime: json['end_time'] == null ? null : DateTime.tryParse(json['end_time'] as String),
    durationS: (json['duration_s'] as num?)?.toDouble(),
    active: json['active'] as bool? ?? false,
  );
}

/// A single tailed line — either the flow's own Prefect execution log
/// (`source: "flow"`) or a scheduler-pod line merged in because it was
/// observed while this run was active (`source: "scheduler"`), D30.
class FlowRunLogEntry {
  const FlowRunLogEntry({
    required this.seq,
    required this.ts,
    required this.source,
    required this.level,
    required this.task,
    required this.message,
  });

  final int seq;
  final double ts;
  final String source;
  final String level;
  final String? task;
  final String message;

  static FlowRunLogEntry fromJson(Map<String, dynamic> json) => FlowRunLogEntry(
    seq: json['seq'] as int,
    ts: (json['ts'] as num).toDouble(),
    source: json['source'] as String? ?? 'flow',
    level: json['level'] as String? ?? 'INFO',
    task: json['task'] as String?,
    message: json['message'] as String? ?? '',
  );
}

class FlowRunLogsReplay {
  const FlowRunLogsReplay({required this.flowRunId, required this.flow, required this.live, required this.entries});

  final String flowRunId;
  final String? flow;
  final bool live;
  final List<FlowRunLogEntry> entries;

  static FlowRunLogsReplay fromJson(Map<String, dynamic> json) => FlowRunLogsReplay(
    flowRunId: json['flow_run_id'] as String,
    flow: json['flow'] as String?,
    live: json['live'] as bool? ?? false,
    entries: [
      for (final entry in (json['entries'] as List? ?? const []))
        FlowRunLogEntry.fromJson(entry as Map<String, dynamic>),
    ],
  );
}
