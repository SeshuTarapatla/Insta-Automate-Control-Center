import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent_client.dart';
import '../../core/app_snack_bar.dart';
import '../../core/device_models.dart';

/// `GET /api/device` is the only state source (CP 4.5) — no WS channel for
/// this yet, so a light periodic poll keeps it current while this pane is on
/// screen. `autoDispose` means the poll stops the moment the Live screen
/// isn't visible.
final _deviceTickProvider = StreamProvider.autoDispose<int>(
  (ref) => Stream<int>.periodic(const Duration(seconds: 5), (tick) => tick),
);

class DeviceController extends AsyncNotifier<DeviceStatus> {
  @override
  Future<DeviceStatus> build() => _fetch();

  Future<DeviceStatus> _fetch() async {
    final dio = ref.read(agentClientProvider);
    final response = await dio.get('/api/device');
    return DeviceStatus.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_fetch);
  }

  /// The native scrcpy window is a completely separate OS window, not
  /// something Flutter renders — this only starts/stops it and repositions
  /// it (agent-side), same reasoning `snap_window`'s docstring gives.
  Future<void> toggleMirror() async {
    final dio = ref.read(agentClientProvider);
    final mirroring = state.value?.mirroring ?? false;
    await dio.post('/api/device/scrcpy/${mirroring ? 'stop' : 'start'}');
    await refresh();
  }
}

final deviceControllerProvider = AsyncNotifierProvider<DeviceController, DeviceStatus>(DeviceController.new);

/// Primary device view (CP 4.5, ARCHITECTURE Q6): control for the native
/// scrcpy window wsl-bridge already owns. The video itself shows in its own
/// window on the desktop, not embedded here — this pane just starts, stops
/// and reports on it. The secondary opt-in low-fps phone stream is deferred
/// to Phase 6, which is the first thing that could actually consume it.
class DevicePane extends ConsumerWidget {
  const DevicePane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(_deviceTickProvider);
    ref.listen<AsyncValue<int>>(_deviceTickProvider, (previous, next) {
      next.whenData((_) => ref.read(deviceControllerProvider.notifier).refresh());
    });

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final async = ref.watch(deviceControllerProvider);

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (error, _) => _Frame(
        theme: theme,
        icon: Icons.error_outline,
        message: 'Could not reach the agent for device status.',
      ),
      data: (status) {
        if (!status.bridgeReachable) {
          return _Frame(
            theme: theme,
            icon: Icons.link_off,
            message: "wsl-bridge isn't reachable — check the Services screen.",
          );
        }
        if (status.serial == null) {
          return _Frame(
            theme: theme,
            icon: Icons.phone_android_outlined,
            message: 'ANDROID_SERIAL is not set — no phone configured.',
          );
        }
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.phone_android_outlined, size: 20, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      status.serial!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Icon(
                    status.mirroring ? Icons.cast_connected : Icons.cast,
                    size: 16,
                    color: status.mirroring ? const Color(0xFF3DD68C) : scheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        try {
                          await ref.read(deviceControllerProvider.notifier).toggleMirror();
                        } on DioException {
                          if (context.mounted) {
                            AppSnackBar.show(context, 'Could not reach the device mirror', isError: true);
                          }
                        }
                      },
                      child: Text(status.mirroring ? 'Stop mirror' : 'Start mirror'),
                    ),
                  ),
                ],
              ),
              if (status.mirroring)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'The scrcpy window is separate from this app — look for it on your desktop.',
                    style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.theme, required this.icon, required this.message});

  final ThemeData theme;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
