import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/agent_client.dart';
import '../../core/app_snack_bar.dart';
import '../../core/device_models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/icons.dart';

/// `GET /api/device` is the only state source (CP 4.5) — no WS channel for
/// this yet, so a light periodic poll keeps it current while the Live screen
/// is on screen. `autoDispose` means the poll stops the moment it isn't.
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

/// Device control, compacted into the Live screen's header row (D46) rather
/// than a full card in `RunSummary`'s body — CP 4.5's original design showed
/// the serial, a status icon, the mirror button and an explanatory sentence
/// in a bordered card; all of that competed with the log console for space
/// it didn't need to. This keeps only what the header has room for and what
/// actually needs a glance: a name for the device and the mirror toggle.
/// Model, not serial, since "Pixel 7" means something at a glance and 15
/// raw digits don't — falls back to the serial if the agent couldn't read
/// the model (`ia_agent/api/device.py`'s `_device_model`, best-effort).
class DeviceBar extends ConsumerWidget {
  const DeviceBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(_deviceTickProvider);
    ref.listen<AsyncValue<int>>(_deviceTickProvider, (previous, next) {
      next.whenData((_) => ref.read(deviceControllerProvider.notifier).refresh());
    });

    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final async = ref.watch(deviceControllerProvider);

    return async.when(
      loading: () => const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (error, _) => _Status(theme: theme, glyph: AppIcons.error, message: 'device error'),
      data: (status) {
        if (!status.bridgeReachable) {
          return _Status(theme: theme, glyph: AppIcons.linkOff, message: 'bridge down');
        }
        if (status.serial == null) {
          return _Status(theme: theme, glyph: AppIcons.device, message: 'no device');
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(AppIcons.device, size: IconSize.sm, color: tokens.content.secondary),
            SizedBox(width: tokens.space.xs),
            // `Flexible` around the existing 140px cap, not the cap alone —
            // the Live header always has ≥140px of slack so this is a no-op
            // there (D46's tuning is untouched), but Overview's Device tile
            // (V2.7) can be narrower than 140+icon+gap+button, and a hard
            // `ConstrainedBox` alone doesn't shrink below its own max when
            // the *row* itself is what's actually too narrow.
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  status.model ?? status.serial!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
            SizedBox(width: tokens.space.sm),
            SizedBox(
              height: 32,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: tokens.space.sm)),
                onPressed: () async {
                  try {
                    await ref.read(deviceControllerProvider.notifier).toggleMirror();
                  } on DioException {
                    if (context.mounted) {
                      AppSnackBar.show(context, 'Could not reach the device mirror', isError: true);
                    }
                  }
                },
                child: Text(status.mirroring ? 'Stop' : 'Start'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.theme, required this.glyph, required this.message});

  final ThemeData theme;
  final PhosphorIconData Function(PhosphorIconsStyle) glyph;
  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = theme.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(glyph, size: IconSize.sm, color: tokens.content.secondary),
        SizedBox(width: tokens.space.xs),
        Text(message, style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary)),
      ],
    );
  }
}
