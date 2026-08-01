/// Mirrors the scheduler state block the pod posts to `/api/scheduler/heartbeat`
/// and the agent mirrors back on `GET /api/scheduler` / `flows.state`
/// (ARCHITECTURE.md §4.3).
library;

/// Why a flow is or isn't triggering right now. `detail` is the single most
/// valuable string this project produces (ARCHITECTURE §4.3) — it answers
/// "why isn't it running?" without reading code, so it's always shown when
/// present rather than just the `reason` code.
class FlowGate {
  const FlowGate({required this.ok, this.reason, this.detail});

  final bool ok;
  final String? reason;
  final String? detail;

  static FlowGate fromJson(Map<String, dynamic>? json) => json == null
      ? const FlowGate(ok: true)
      : FlowGate(
          ok: json['ok'] as bool? ?? true,
          reason: json['reason'] as String?,
          detail: json['detail'] as String?,
        );
}

class FlowLastRun {
  const FlowLastRun({required this.id, required this.state, this.durationS});

  final String id;
  final String state;
  final double? durationS;

  static FlowLastRun? fromJson(Map<String, dynamic>? json) => json == null
      ? null
      : FlowLastRun(
          id: json['id'] as String,
          state: json['state'] as String,
          durationS: (json['duration_s'] as num?)?.toDouble(),
        );
}

class FlowState {
  const FlowState({
    required this.flow,
    required this.switchOn,
    required this.phase,
    required this.nextTriggerAt,
    required this.gate,
    required this.today,
    required this.lastRun,
  });

  final String flow;
  final bool switchOn;
  final String phase;
  final DateTime? nextTriggerAt;
  final FlowGate gate;

  /// Shape varies by flow: scan carries three sub-counters, scrape/follow one
  /// each, ingest/classify none — left as a raw map and formatted per-flow by
  /// the card rather than modelled per-variant.
  final Map<String, dynamic>? today;
  final FlowLastRun? lastRun;

  static FlowState fromJson(String flow, Map<String, dynamic> json) => FlowState(
    flow: flow,
    switchOn: json['switch'] as bool? ?? false,
    phase: json['phase'] as String? ?? 'idle',
    nextTriggerAt: json['next_trigger_at'] == null
        ? null
        : DateTime.tryParse(json['next_trigger_at'] as String),
    gate: FlowGate.fromJson(json['gate'] as Map<String, dynamic>?),
    today: json['today'] == null ? null : Map<String, dynamic>.from(json['today'] as Map),
    lastRun: FlowLastRun.fromJson(json['last_run'] as Map<String, dynamic>?),
  );
}

class SchedulerSnapshot {
  const SchedulerSnapshot({required this.online, required this.lastHeartbeatAt, required this.flows});

  final bool online;
  final double? lastHeartbeatAt;
  final Map<String, FlowState> flows;

  static const empty = SchedulerSnapshot(online: false, lastHeartbeatAt: null, flows: {});

  static SchedulerSnapshot fromJson(Map<String, dynamic> json) => SchedulerSnapshot(
    online: json['online'] as bool? ?? false,
    lastHeartbeatAt: (json['last_heartbeat_at'] as num?)?.toDouble(),
    flows: {
      for (final entry in (json['flows'] as Map? ?? const {}).entries)
        entry.key as String: FlowState.fromJson(entry.key as String, entry.value as Map<String, dynamic>),
    },
  );
}

/// The pipeline order every flow list in this app follows.
const flowOrder = ['entity-ingest', 'entity-scan', 'entity-classify', 'entity-scrape', 'entity-follow'];

/// `entity-scan` -> `ENTITY_SCAN`, the config.env switch key for a flow name.
String flowSwitchKey(String flow) => flow.toUpperCase().replaceAll('-', '_');

/// Shared with the Live screen (CP 4.4) — one lookup table, not one per
/// feature, since both mean the same thing by "flow" and "phase".
const flowTitle = {
  'entity-ingest': 'Ingest',
  'entity-scan': 'Scan',
  'entity-classify': 'Classify',
  'entity-scrape': 'Scrape',
  'entity-follow': 'Follow',
};

const phaseLabel = {
  'idle': 'Idle',
  'running': 'Running',
  'waiting': 'Waiting',
  'day_paused': 'Paused for the day',
};
