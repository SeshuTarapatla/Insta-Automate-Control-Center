import 'package:flutter/material.dart';

/// Mirrors `ia_agent.dependencies.Level`. A dependency that fails is an answer,
/// not an error — the agent always returns 200 and so every level renders.
enum DependencyLevel {
  ok,
  warn,
  fail;

  static DependencyLevel parse(String raw) =>
      DependencyLevel.values.firstWhere((l) => l.name == raw, orElse: () => DependencyLevel.fail);

  Color color(ColorScheme scheme) => switch (this) {
    DependencyLevel.ok => const Color(0xFF3DD68C),
    DependencyLevel.warn => const Color(0xFFFFB454),
    DependencyLevel.fail => scheme.error,
  };

  IconData get icon => switch (this) {
    DependencyLevel.ok => Icons.check_circle,
    DependencyLevel.warn => Icons.error_outline,
    DependencyLevel.fail => Icons.cancel,
  };
}

enum DependencyGroup {
  cluster,
  pipeline,
  host;

  static DependencyGroup parse(String raw) =>
      DependencyGroup.values.firstWhere((g) => g.name == raw, orElse: () => DependencyGroup.host);

  String get label => switch (this) {
    DependencyGroup.cluster => 'Cluster',
    DependencyGroup.pipeline => 'Pipeline',
    DependencyGroup.host => 'This machine',
  };

  String get blurb => switch (this) {
    DependencyGroup.cluster => 'k3s and the datastores the pods run against.',
    DependencyGroup.pipeline => 'Prefect and the two Insta-Automate deployments.',
    DependencyGroup.host => 'Everything the pipeline needs from this laptop.',
  };
}

class Dependency {
  const Dependency({
    required this.key,
    required this.label,
    required this.group,
    required this.level,
    required this.detail,
    required this.metrics,
    required this.latencyMs,
  });

  final String key;
  final String label;
  final DependencyGroup group;
  final DependencyLevel level;
  final String detail;
  final Map<String, dynamic> metrics;
  final double latencyMs;

  static Dependency fromJson(Map<String, dynamic> json) => Dependency(
    key: json['key'] as String,
    label: json['label'] as String,
    group: DependencyGroup.parse(json['group'] as String),
    level: DependencyLevel.parse(json['level'] as String),
    detail: json['detail'] as String,
    metrics: Map<String, dynamic>.from(json['metrics'] as Map? ?? const {}),
    latencyMs: (json['latency_ms'] as num?)?.toDouble() ?? 0,
  );
}

class DependencySnapshot {
  const DependencySnapshot({
    required this.items,
    required this.ok,
    required this.warn,
    required this.fail,
    required this.checkedAt,
  });

  final List<Dependency> items;
  final int ok;
  final int warn;
  final int fail;
  final DateTime checkedAt;

  DependencyLevel get worst {
    if (fail > 0) return DependencyLevel.fail;
    if (warn > 0) return DependencyLevel.warn;
    return DependencyLevel.ok;
  }

  List<Dependency> inGroup(DependencyGroup group) =>
      items.where((item) => item.group == group).toList();

  static DependencySnapshot fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] as Map<String, dynamic>? ?? const {};
    return DependencySnapshot(
      items: (json['dependencies'] as List)
          .map((item) => Dependency.fromJson(item as Map<String, dynamic>))
          .toList(),
      ok: summary['ok'] as int? ?? 0,
      warn: summary['warn'] as int? ?? 0,
      fail: summary['fail'] as int? ?? 0,
      checkedAt: DateTime.now(),
    );
  }
}
