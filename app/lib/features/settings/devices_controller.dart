import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent_client.dart';
import '../../core/pairing_models.dart';

/// Paired-phone list backing the Settings > Devices tab (CP 6.3). No WS
/// channel exists for pairing (CP 6.1 never wired one — a claim happens on
/// the phone, so the desktop has nothing to subscribe to), so this is a
/// plain fetch, refreshed manually after every mutation and polled while a
/// QR code is on screen waiting to be claimed.
class DevicesController extends AsyncNotifier<List<PairedDevice>> {
  @override
  Future<List<PairedDevice>> build() => _fetch();

  Future<List<PairedDevice>> _fetch() async {
    final dio = ref.read(agentClientProvider);
    final response = await dio.get('/api/pair/devices');
    return (response.data as List<dynamic>)
        .map((d) => PairedDevice.fromJson(d as Map<String, dynamic>))
        .toList();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_fetch);
  }

  /// Mints a fresh code — replaces whatever code was pending agent-side, so
  /// only one QR is ever meaningful at once (`PairingStore.start`).
  Future<PairingCode> startPairing() async {
    final dio = ref.read(agentClientProvider);
    final response = await dio.post('/api/pair/start');
    return PairingCode.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> revoke(String deviceId) async {
    final dio = ref.read(agentClientProvider);
    await dio.delete('/api/pair/devices/$deviceId');
    await refresh();
  }
}

final devicesControllerProvider = AsyncNotifierProvider<DevicesController, List<PairedDevice>>(
  DevicesController.new,
);
