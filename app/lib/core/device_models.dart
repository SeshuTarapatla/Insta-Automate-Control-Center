/// Mirrors the agent's `GET /api/device` payload (CP 4.5).
library;

class DeviceStatus {
  const DeviceStatus({required this.serial, required this.model, required this.bridgeReachable, required this.mirroring});

  final String? serial;
  final String? model;
  final bool bridgeReachable;
  final bool mirroring;

  static DeviceStatus fromJson(Map<String, dynamic> json) => DeviceStatus(
    serial: json['serial'] as String?,
    model: json['model'] as String?,
    bridgeReachable: json['bridge_reachable'] as bool? ?? false,
    mirroring: json['mirroring'] as bool? ?? false,
  );
}
