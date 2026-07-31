import 'package:flutter/material.dart';

/// Mirrors `ia_agent.services.spec.ServiceState`.
enum ServiceState {
  stopped,
  starting,
  running,
  unhealthy,
  backoff,
  failed;

  static ServiceState parse(String raw) =>
      ServiceState.values.firstWhere((s) => s.name == raw, orElse: () => ServiceState.stopped);

  String get label => switch (this) {
    ServiceState.stopped => 'Stopped',
    ServiceState.starting => 'Starting',
    ServiceState.running => 'Running',
    ServiceState.unhealthy => 'Unhealthy',
    ServiceState.backoff => 'Restarting',
    ServiceState.failed => 'Failed',
  };

  /// The status palette is deliberately not the seed scheme: green/amber/red
  /// read as health at a glance, and the scheme's primary does not.
  Color color(ColorScheme scheme) => switch (this) {
    ServiceState.running => const Color(0xFF3DD68C),
    ServiceState.starting => const Color(0xFF6EA8FE),
    ServiceState.backoff => const Color(0xFFFFB454),
    ServiceState.unhealthy => const Color(0xFFFFB454),
    ServiceState.failed => scheme.error,
    ServiceState.stopped => scheme.onSurfaceVariant,
  };

  /// States where something is expected to change on its own, so the tile
  /// animates rather than sitting still and looking wedged.
  bool get isTransient => this == ServiceState.starting || this == ServiceState.backoff;
}

/// Mirrors `ia_agent.services.spec.ServiceOrigin` — who owns the process, which
/// is what decides whether there is a terminal to show at all.
enum ServiceOrigin {
  none,
  supervised,
  adopted,
  external;

  static ServiceOrigin parse(String raw) =>
      ServiceOrigin.values.firstWhere((o) => o.name == raw, orElse: () => ServiceOrigin.none);

  String get label => switch (this) {
    ServiceOrigin.none => 'not running',
    ServiceOrigin.supervised => 'supervised',
    ServiceOrigin.adopted => 'adopted',
    ServiceOrigin.external => 'external',
  };
}

class ProbeResult {
  const ProbeResult({
    required this.ok,
    required this.latencyMs,
    required this.detail,
    required this.at,
  });

  final bool ok;
  final double latencyMs;
  final String detail;
  final double at;

  static ProbeResult fromJson(Map<String, dynamic> json) => ProbeResult(
    ok: json['ok'] as bool,
    latencyMs: (json['latency_ms'] as num).toDouble(),
    detail: json['detail'] as String,
    at: (json['at'] as num).toDouble(),
  );
}

/// The result of the on-demand functional test. `metrics` is the part that
/// matters — "the port is open" and "classification runs at 150 ms/image" are
/// different answers.
class TestOutcome {
  const TestOutcome({
    required this.ok,
    required this.summary,
    required this.metrics,
    required this.durationMs,
    required this.at,
  });

  final bool ok;
  final String summary;
  final Map<String, dynamic> metrics;
  final double durationMs;
  final double at;

  static TestOutcome fromJson(Map<String, dynamic> json) => TestOutcome(
    ok: json['ok'] as bool,
    summary: json['summary'] as String,
    metrics: Map<String, dynamic>.from(json['metrics'] as Map? ?? const {}),
    durationMs: (json['duration_ms'] as num).toDouble(),
    at: (json['at'] as num).toDouble(),
  );
}

class ProcessRef {
  const ProcessRef({required this.pid, this.name, this.cmdline});

  final int pid;
  final String? name;
  final String? cmdline;

  String get display => cmdline ?? name ?? 'pid $pid';

  static ProcessRef? fromJson(Map<String, dynamic>? json) => json == null
      ? null
      : ProcessRef(
          pid: json['pid'] as int,
          name: json['name'] as String?,
          cmdline: json['cmdline'] as String?,
        );
}

class ServiceStatus {
  const ServiceStatus({
    required this.name,
    required this.label,
    required this.description,
    required this.state,
    required this.origin,
    required this.pid,
    required this.uptimeS,
    required this.restartCount,
    required this.exitCode,
    required this.error,
    required this.probe,
    required this.hasTest,
    required this.lastTest,
    required this.selfHeal,
    required this.autostart,
    required this.terminalAvailable,
    required this.canTakeover,
    required this.external,
    required this.portOwner,
    required this.cmd,
    required this.port,
    required this.logSeq,
    required this.receivedAt,
  });

  final String name;
  final String label;
  final String description;
  final ServiceState state;
  final ServiceOrigin origin;
  final int? pid;
  final double? uptimeS;
  final int restartCount;
  final int? exitCode;
  final String? error;
  final ProbeResult? probe;
  final bool hasTest;
  final TestOutcome? lastTest;
  final bool selfHeal;
  final bool autostart;

  /// False for adopted and external processes: they were spawned without the
  /// agent's pseudo-console, so there is nothing live to render. The pane says
  /// so rather than showing an empty box.
  final bool terminalAvailable;
  final bool canTakeover;

  /// What a takeover would kill, versus what actually holds the socket — the
  /// two are often different processes (DECISIONS D11).
  final ProcessRef? external;
  final ProcessRef? portOwner;
  final List<String> cmd;
  final int port;
  final int logSeq;

  /// When this snapshot reached the client. `uptime_s` is measured at the
  /// agent and a status is only broadcast when something about it changes, so
  /// without this the uptime on a healthy tile would sit frozen for hours.
  final DateTime receivedAt;

  double? get liveUptimeS => uptimeS == null
      ? null
      : uptimeS! + DateTime.now().difference(receivedAt).inMilliseconds / 1000;

  bool get isRunning =>
      origin == ServiceOrigin.supervised ||
      origin == ServiceOrigin.adopted ||
      origin == ServiceOrigin.external;

  /// Stop is only ours to offer for a process the agent controls; an external
  /// one is taken over, not stopped.
  bool get canStop =>
      origin == ServiceOrigin.supervised || origin == ServiceOrigin.adopted;

  static ServiceStatus fromJson(Map<String, dynamic> json) => ServiceStatus(
    name: json['name'] as String,
    label: json['label'] as String,
    description: json['description'] as String? ?? '',
    state: ServiceState.parse(json['state'] as String),
    origin: ServiceOrigin.parse(json['origin'] as String),
    pid: json['pid'] as int?,
    uptimeS: (json['uptime_s'] as num?)?.toDouble(),
    restartCount: json['restart_count'] as int? ?? 0,
    exitCode: json['exit_code'] as int?,
    error: json['error'] as String?,
    probe: json['probe'] == null
        ? null
        : ProbeResult.fromJson(json['probe'] as Map<String, dynamic>),
    hasTest: json['has_test'] as bool? ?? false,
    lastTest: json['last_test'] == null
        ? null
        : TestOutcome.fromJson(json['last_test'] as Map<String, dynamic>),
    selfHeal: json['self_heal'] as bool? ?? false,
    autostart: json['autostart'] as bool? ?? false,
    terminalAvailable: json['terminal_available'] as bool? ?? false,
    canTakeover: json['can_takeover'] as bool? ?? false,
    external: ProcessRef.fromJson(json['external'] as Map<String, dynamic>?),
    portOwner: ProcessRef.fromJson(json['port_owner'] as Map<String, dynamic>?),
    cmd: (json['cmd'] as List? ?? const []).cast<String>(),
    port: json['port'] as int? ?? 0,
    logSeq: json['log_seq'] as int? ?? 0,
    receivedAt: DateTime.now(),
  );
}

/// One verbatim slice of a service's ConPTY stream. `seq` is monotonic and
/// never reused, which is what lets a reconnecting terminal ask for everything
/// it missed instead of replaying the whole ring.
class LogChunk {
  const LogChunk({required this.seq, required this.data});

  final int seq;
  final String data;

  static LogChunk fromJson(Map<String, dynamic> json) =>
      LogChunk(seq: json['seq'] as int, data: json['data'] as String);
}

String formatUptime(double seconds) {
  final total = seconds.round();
  final days = total ~/ 86400;
  final hours = (total % 86400) ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  if (days > 0) return '${days}d ${hours}h';
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m ${total % 60}s';
  return '${total}s';
}
