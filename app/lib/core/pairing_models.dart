/// `POST /api/pair/start`'s response — a fresh 6-digit code plus the LAN
/// host/port the phone needs, valid for `expiresAt` (ARCHITECTURE §7).
class PairingCode {
  const PairingCode({required this.code, required this.expiresAt, required this.host, required this.port});

  final String code;
  final DateTime expiresAt;
  final String host;
  final int port;

  /// `iacc://pair?h=<lan-ip>&p=8787&c=<code>` — the exact payload
  /// ARCHITECTURE §7 specifies, so CP 6.4's mobile scanner reads what this
  /// screen renders with no format guessing on either side.
  String get qrPayload => 'iacc://pair?h=$host&p=$port&c=$code';

  factory PairingCode.fromJson(Map<String, dynamic> json) => PairingCode(
    code: json['code'] as String,
    expiresAt: DateTime.fromMillisecondsSinceEpoch(((json['expires_at'] as num) * 1000).round()),
    host: json['host'] as String,
    port: json['port'] as int,
  );
}

/// One row of `GET /api/pair/devices` — never carries the device's token.
class PairedDevice {
  const PairedDevice({required this.id, required this.name, required this.createdAt, required this.lastSeen});

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime lastSeen;

  factory PairedDevice.fromJson(Map<String, dynamic> json) => PairedDevice(
    id: json['id'] as String,
    name: json['name'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(((json['created_at'] as num) * 1000).round()),
    lastSeen: DateTime.fromMillisecondsSinceEpoch(((json['last_seen'] as num) * 1000).round()),
  );
}
