/// One entry of `GET /api/ops/specs` — the agent's real job registry
/// (`ia_agent.ops.jobs.JOB_SPECS`), fetched rather than duplicated client-side
/// so the button list can never drift from what the agent will actually run.
class OpsJobSpec {
  const OpsJobSpec({
    required this.id,
    required this.label,
    required this.description,
    required this.confirm,
    required this.consequence,
  });

  final String id;
  final String label;
  final String description;
  final bool confirm;
  final String? consequence;

  factory OpsJobSpec.fromJson(Map<String, dynamic> json) => OpsJobSpec(
    id: json['id'] as String,
    label: json['label'] as String,
    description: json['description'] as String,
    confirm: json['confirm'] as bool,
    consequence: json['consequence'] as String?,
  );
}

enum OpsJobStatus { running, succeeded, failed, interrupted }

OpsJobStatus _parseStatus(String raw) => switch (raw) {
  'running' => OpsJobStatus.running,
  'succeeded' => OpsJobStatus.succeeded,
  'failed' => OpsJobStatus.failed,
  _ => OpsJobStatus.interrupted, // includes "interrupted" — an agent restart mid-job
};

/// One run — `POST /api/ops/jobs`' response, `GET /api/ops/jobs[/{id}]`'s
/// rows, and the `ops.jobs` WS channel's payload all share this shape.
class OpsJob {
  const OpsJob({
    required this.id,
    required this.kind,
    required this.label,
    required this.status,
    required this.startedAt,
    required this.endedAt,
    required this.exitCode,
    required this.currentStep,
    required this.steps,
  });

  final String id;
  final String kind;
  final String label;
  final OpsJobStatus status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? exitCode;
  final int currentStep;
  final List<String> steps;

  factory OpsJob.fromJson(Map<String, dynamic> json) => OpsJob(
    id: json['id'] as String,
    kind: json['kind'] as String,
    label: json['label'] as String,
    status: _parseStatus(json['status'] as String),
    startedAt: DateTime.fromMillisecondsSinceEpoch(((json['started_at'] as num) * 1000).round()),
    endedAt: json['ended_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(((json['ended_at'] as num) * 1000).round()),
    exitCode: json['exit_code'] as int?,
    currentStep: json['current_step'] as int,
    steps: (json['steps'] as List).cast<String>(),
  );
}

/// One line of `GET /api/ops/jobs/{id}/logs`' `entries` / an `ops.logs.{id}`
/// WS frame — `kind` is `"line"` (real subprocess output), `"step"` (the `$
/// ...` divider a new step starts with) or `"error"` (a step's non-zero exit).
class OpsLogEntry {
  const OpsLogEntry({required this.seq, required this.ts, required this.kind, required this.text});

  final int seq;
  final double ts;
  final String kind;
  final String text;

  factory OpsLogEntry.fromJson(Map<String, dynamic> json) => OpsLogEntry(
    seq: json['seq'] as int,
    ts: (json['ts'] as num).toDouble(),
    kind: json['kind'] as String,
    text: json['text'] as String,
  );
}
