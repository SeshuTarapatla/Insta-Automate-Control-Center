import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/app_snack_bar.dart';
import '../../core/pairing_models.dart';
import '../../core/relative_time.dart';
import '../../core/theme/tokens.dart';
import 'devices_controller.dart';

/// CP 6.3 — the desktop half of mobile pairing (ARCHITECTURE §7). Placement
/// decided before writing any code (D54): a Settings tab alongside
/// Flows/Limits/Queue, not a new nav destination — the notification center
/// this checkpoint also builds lives in the title bar instead.
class DevicesTab extends ConsumerWidget {
  const DevicesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final devicesAsync = ref.watch(devicesControllerProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pair a phone', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Scan the QR code from the Insta-Automate mobile app to receive live notifications '
            'on your phone.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          const _PairingCard(),
          const SizedBox(height: 32),
          Text('Paired devices', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          devicesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('Failed to load devices: $error'),
            ),
            data: (devices) => devices.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No devices paired yet.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  )
                : Column(children: [for (final d in devices) _DeviceTile(device: d)]),
          ),
        ],
      ),
    );
  }
}

enum _PairingPhase { idle, minting, showing, expired, paired }

class _PairingCard extends ConsumerStatefulWidget {
  const _PairingCard();

  @override
  ConsumerState<_PairingCard> createState() => _PairingCardState();
}

class _PairingCardState extends ConsumerState<_PairingCard> {
  _PairingPhase _phase = _PairingPhase.idle;
  PairingCode? _code;
  Timer? _countdownTimer;
  Timer? _pollTimer;
  Timer? _resetTimer;
  Duration _remaining = Duration.zero;
  String _pairedName = '';
  Set<String> _knownIds = {};

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pollTimer?.cancel();
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _startPairing() async {
    _countdownTimer?.cancel();
    _pollTimer?.cancel();
    _resetTimer?.cancel();
    setState(() => _phase = _PairingPhase.minting);

    final known = ref.read(devicesControllerProvider).value ?? const [];
    _knownIds = known.map((d) => d.id).toSet();

    try {
      final code = await ref.read(devicesControllerProvider.notifier).startPairing();
      if (!mounted) return;
      setState(() {
        _code = code;
        _phase = _PairingPhase.showing;
        _remaining = code.expiresAt.difference(DateTime.now());
      });
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickCountdown());
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollForClaim());
    } on DioException {
      if (!mounted) return;
      setState(() => _phase = _PairingPhase.idle);
      if (context.mounted) {
        AppSnackBar.show(context, 'Could not reach the agent to mint a pairing code', isError: true);
      }
    }
  }

  void _tickCountdown() {
    final code = _code;
    if (code == null) return;
    final remaining = code.expiresAt.difference(DateTime.now());
    if (remaining.isNegative) {
      _countdownTimer?.cancel();
      _pollTimer?.cancel();
      setState(() => _phase = _PairingPhase.expired);
      return;
    }
    setState(() => _remaining = remaining);
  }

  Future<void> _pollForClaim() async {
    await ref.read(devicesControllerProvider.notifier).refresh();
    if (!mounted) return;
    final devices = ref.read(devicesControllerProvider).value;
    if (devices == null) return;
    final newlyPaired = devices.where((d) => !_knownIds.contains(d.id)).toList();
    if (newlyPaired.isEmpty) return;

    _countdownTimer?.cancel();
    _pollTimer?.cancel();
    setState(() {
      _phase = _PairingPhase.paired;
      _pairedName = newlyPaired.first.name;
    });
    _resetTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _phase = _PairingPhase.idle);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
      child: switch (_phase) {
        _PairingPhase.idle => _IdleContent(onGenerate: _startPairing),
        _PairingPhase.minting => const SizedBox(height: 96, child: Center(child: CircularProgressIndicator())),
        _PairingPhase.showing => _CodeContent(code: _code!, remaining: _remaining, onRegenerate: _startPairing),
        _PairingPhase.expired => _ExpiredContent(onRegenerate: _startPairing),
        _PairingPhase.paired => _PairedContent(name: _pairedName),
      },
    );
  }
}

class _IdleContent extends StatelessWidget {
  const _IdleContent({required this.onGenerate});
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.qr_code_2, size: 40, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 16),
        Expanded(
          child: Text('Generate a QR code to pair a new phone. It expires in 2 minutes.', style: theme.textTheme.bodyMedium),
        ),
        const SizedBox(width: 16),
        FilledButton.icon(
          onPressed: onGenerate,
          icon: const Icon(Icons.qr_code_2, size: 18),
          label: const Text('Generate QR code'),
        ),
      ],
    );
  }
}

class _CodeContent extends StatelessWidget {
  const _CodeContent({required this.code, required this.remaining, required this.onRegenerate});

  final PairingCode code;
  final Duration remaining;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seconds = remaining.inSeconds.clamp(0, 999);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: theme.tokens.chart.qrQuietZone, borderRadius: BorderRadius.circular(8)),
          // qr_flutter renders black modules regardless of app theme — wrapped
          // in an explicit light card so it stays scannable in dark mode.
          child: QrImageView(data: code.qrPayload, size: 160, backgroundColor: theme.tokens.chart.qrQuietZone),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Scan with the Insta-Automate app', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 10),
              Text(
                'Or enter this code manually:',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(
                code.code,
                style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 6, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Text(
                'Expires in ${seconds}s',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRegenerate, child: const Text('Generate a new code')),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExpiredContent extends StatelessWidget {
  const _ExpiredContent({required this.onRegenerate});
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.timer_off_outlined, size: 32, color: theme.colorScheme.error),
        const SizedBox(width: 16),
        Expanded(child: Text('That code expired before it was claimed.', style: theme.textTheme.bodyMedium)),
        const SizedBox(width: 16),
        FilledButton(onPressed: onRegenerate, child: const Text('Generate a new code')),
      ],
    );
  }
}

class _PairedContent extends StatelessWidget {
  const _PairedContent({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.check_circle_outline, size: 32, color: theme.tokens.status.good.fg),
        const SizedBox(width: 16),
        Expanded(child: Text('Paired "$name" successfully.', style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}

class _DeviceTile extends ConsumerWidget {
  const _DeviceTile({required this.device});
  final PairedDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.phone_android_outlined),
        title: Text(device.name, overflow: TextOverflow.ellipsis),
        subtitle: Text('Paired ${relativeTime(device.createdAt)} · last seen ${relativeTime(device.lastSeen)}'),
        trailing: IconButton(
          tooltip: 'Revoke access',
          icon: const Icon(Icons.link_off),
          onPressed: () => _confirmRevoke(context, ref),
        ),
      ),
    );
  }

  Future<void> _confirmRevoke(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Revoke "${device.name}"?'),
        content: const Text(
          'This device will stop receiving live notifications and lose access to the agent '
          'immediately. It can be paired again with a new QR code.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Revoke')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(devicesControllerProvider.notifier).revoke(device.id);
      if (context.mounted) AppSnackBar.show(context, '"${device.name}" revoked.');
    } on DioException {
      if (context.mounted) AppSnackBar.show(context, 'Failed to revoke device', isError: true);
    }
  }
}
