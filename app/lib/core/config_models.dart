import 'package:flutter/foundation.dart';

/// Mirrors ia_agent.config.schema.ConfigKey.
class ConfigKeySchema {
  const ConfigKeySchema({
    required this.name,
    required this.group,
    required this.type,
    required this.defaultValue,
    required this.help,
    this.min,
    this.max,
  });

  final String name;
  final String group; // switch | scan | scrape | follow
  final String type; // int | bool01 | queue
  final dynamic defaultValue;
  final String help;
  final int? min;
  final int? max;

  factory ConfigKeySchema.fromJson(Map<String, dynamic> json) => ConfigKeySchema(
    name: json['name'] as String,
    group: json['group'] as String,
    type: json['type'] as String,
    defaultValue: json['default'],
    help: json['help'] as String,
    min: json['min'] as int?,
    max: json['max'] as int?,
  );
}

/// The effective config a client would read — mirrors the "values" object in
/// GET /api/config and the payload the config.changed WS channel publishes.
class ConfigValues {
  const ConfigValues({required this.switches, required this.entityQueue, required this.limits});

  final Map<String, bool> switches;
  final List<String> entityQueue;
  final Map<String, int> limits;

  factory ConfigValues.fromJson(Map<String, dynamic> json) => ConfigValues(
    switches: (json['switches'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as bool)),
    entityQueue: (json['entity_queue'] as List).cast<String>(),
    limits: (json['limits'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int)),
  );

  bool valueEquals(ConfigValues other) =>
      mapEquals(switches, other.switches) &&
      listEquals(entityQueue, other.entityQueue) &&
      mapEquals(limits, other.limits);
}

/// Mirrors the full body of GET /api/config and the response of PATCH /api/config.
class ConfigResponse {
  const ConfigResponse({
    required this.path,
    required this.values,
    required this.schema,
    required this.provenance,
  });

  /// Absolute path to config.env on this machine, as reported by the agent.
  final String path;
  final ConfigValues values;
  final List<ConfigKeySchema> schema;
  final Map<String, String> provenance;

  factory ConfigResponse.fromJson(Map<String, dynamic> json) => ConfigResponse(
    path: json['path'] as String,
    values: ConfigValues.fromJson(json['values'] as Map<String, dynamic>),
    schema: (json['schema'] as List)
        .map((e) => ConfigKeySchema.fromJson(e as Map<String, dynamic>))
        .toList(),
    provenance: (json['provenance'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as String)),
  );
}
