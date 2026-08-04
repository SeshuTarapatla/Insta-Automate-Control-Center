import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_snack_bar.dart';
import '../../core/service_models.dart';
import '../../core/theme/tokens.dart';
import 'service_terminal.dart';
import 'services_controller.dart';
import 'status_dot.dart';

/// The terminal never shrinks below this, however cramped the window: a pane
/// squeezed to a couple of rows is worse than one you have to scroll to.
const _minTerminalHeight = 220.0;

/// What actually stops working while a service is down. A confirmation without
/// a consequence is not a confirmation — same rule as the flow switches.
const _stopConsequence = {
  'adb': 'Every phone interaction goes through the ADB server: scan, scrape and follow runs will '
      'fail until it is back, and the pods lose the device too.',
  'vl-server': 'Gender and privacy classification stops. entity_classify will fail on every image '
      'it tries while the model is down.',
  'wsl-bridge': 'The device mirror stops. The pipeline itself keeps running — this only affects '
      'scrcpy.',
};

class ServiceDetail extends ConsumerStatefulWidget {
  const ServiceDetail({super.key, required this.status});

  final ServiceStatus status;

  @override
  ConsumerState<ServiceDetail> createState() => _ServiceDetailState();
}

class _ServiceDetailState extends ConsumerState<ServiceDetail> {
  /// The action in flight, or null. One at a time: these kill and spawn process
  /// trees, and letting a second land mid-flight is how you get two copies on
  /// one port.
  String? _busy;

  Future<void> _run(String action, Future<void> Function() body, String success) async {
    setState(() => _busy = action);
    try {
      await body();
      if (mounted) AppSnackBar.show(context, success);
    } catch (error) {
      if (mounted) {
        AppSnackBar.show(
          context,
          '${widget.status.label}: ${describeAgentError(error)}',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(action)),
        ],
      ),
    );
    return answer == true;
  }

  ServicesController get _services => ref.read(servicesControllerProvider.notifier);

  Future<void> _start() =>
      _run('start', () => _services.start(widget.status.name), '${widget.status.label} started');

  Future<void> _stop() async {
    final status = widget.status;
    final consequence =
        _stopConsequence[status.name] ?? 'Anything that depends on it will fail until it is back.';
    if (!await _confirm('Stop ${status.label}?', consequence, 'Stop')) return;
    await _run('stop', () => _services.stop(status.name), '${status.label} stopped');
  }

  Future<void> _restart() =>
      _run('restart', () => _services.restart(widget.status.name), '${widget.status.label} restarted');

  Future<void> _takeover() async {
    final status = widget.status;
    if (!await _confirm(
      'Take over ${status.label}?',
      'The agent will kill ${status.external?.display ?? 'the external process'} '
          '(pid ${status.external?.pid}) and start its own supervised copy on port ${status.port}. '
          'Anything mid-flight through it will be interrupted.',
      'Take over',
    )) {
      return;
    }
    await _run('takeover', () => _services.takeover(status.name), '${status.label} taken over');
  }

  Future<void> _test() async {
    setState(() => _busy = 'test');
    try {
      final outcome = await _services.runTest(widget.status.name);
      if (mounted) {
        // A failing test is an answer, not an error — it is reported as plainly
        // as a passing one, and its metrics stay on screen either way.
        AppSnackBar.show(
          context,
          '${widget.status.label}: ${outcome.summary}',
          isError: !outcome.ok,
        );
      }
    } catch (error) {
      if (mounted) {
        AppSnackBar.show(
          context,
          '${widget.status.label}: ${describeAgentError(error)}',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _setSelfHeal(bool value) => _run(
    'self_heal',
    () => _services.setSelfHeal(widget.status.name, value),
    value
        ? 'Self-heal on — the agent will restart ${widget.status.label} if it dies'
        : 'Self-heal off — ${widget.status.label} will stay down if it dies',
  );

  Future<void> _setAutostart(bool value) => _run(
    'autostart',
    () => _services.setAutostart(widget.status.name, value),
    value ? 'Autostart on' : 'Autostart off',
  );

  @override
  Widget build(BuildContext context) {
    ref.watch(uptimeTickProvider);

    final status = widget.status;
    final theme = Theme.of(context);

    // At the 1024 px minimum window this pane is ~550 wide, where the stat
    // chips wrap onto four rows and every card's text wraps with them — the
    // panels above the terminal can genuinely want more height than the window
    // has. Capping them at "everything except the terminal's floor" means they
    // scroll among themselves instead of pushing the terminal off the bottom,
    // and because the cap is a maximum rather than a share, a tall window still
    // gives the terminal every pixel the panels do not use.
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: (constraints.maxHeight - _minTerminalHeight - 16).clamp(
                0.0,
                double.infinity,
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(theme, status),
                  const SizedBox(height: 16),
                  _stats(theme, status),
                  const SizedBox(height: 12),
                  _switches(theme, status),
                  if (status.hasTest) ...[const SizedBox(height: 12), _testPanel(theme, status)],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(child: ServiceTerminal(key: ValueKey(status.name), status: status)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- header

  Widget _header(ThemeData theme, ServiceStatus status) {
    final scheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusDot(state: status.state, size: 12),
                  const SizedBox(width: 10),
                  // Flexible, not fixed: at the 1024 px minimum window the
                  // action buttons leave this row little to work with, and the
                  // name is the part that can afford to ellipsize.
                  Flexible(
                    child: Text(
                      status.label,
                      style: theme.textTheme.headlineSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    status.state.label.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: status.state.color(theme),
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                status.description,
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // A Row lays its non-flexible children out first, against the full
        // width — without a cap the button Wrap could take the lot and leave
        // the name nothing to render into.
        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360), child: _actions(status)),
      ],
    );
  }

  Widget _actions(ServiceStatus status) {
    final busy = _busy != null;

    return Wrap(
      spacing: 8,
      children: [
        if (status.canTakeover)
          FilledButton.icon(
            onPressed: busy ? null : _takeover,
            icon: _icon('takeover', Icons.swap_horiz),
            label: const Text('Take over'),
          )
        else if (status.isRunning)
          OutlinedButton.icon(
            onPressed: busy ? null : _restart,
            icon: _icon('restart', Icons.refresh),
            label: const Text('Restart'),
          )
        else
          FilledButton.icon(
            onPressed: busy ? null : _start,
            icon: _icon('start', Icons.play_arrow),
            label: const Text('Start'),
          ),
        if (status.canStop)
          OutlinedButton.icon(
            onPressed: busy ? null : _stop,
            icon: _icon('stop', Icons.stop),
            label: const Text('Stop'),
          ),
        if (status.hasTest)
          OutlinedButton.icon(
            // The test needs something to talk to; an external process still
            // answers on the port, so it is testable without being ours.
            onPressed: busy || !status.isRunning ? null : _test,
            icon: _icon('test', Icons.biotech_outlined),
            label: const Text('Test'),
          ),
      ],
    );
  }

  Widget _icon(String action, IconData icon) => _busy == action
      ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
      : Icon(icon, size: 18);

  // ----------------------------------------------------------------- stats

  Widget _stats(ThemeData theme, ServiceStatus status) {
    final probe = status.probe;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _Stat(
          label: 'Uptime',
          value: status.liveUptimeS == null ? '—' : formatUptime(status.liveUptimeS!),
        ),
        _Stat(
          label: 'Restarts',
          value: '${status.restartCount}',
          tone: status.restartCount > 0 ? const Color(0xFFFFB454) : null,
        ),
        _Stat(label: 'PID', value: status.pid?.toString() ?? '—'),
        _Stat(label: 'Port', value: '${status.port}'),
        _Stat(
          label: 'Probe',
          value: probe == null ? '—' : '${probe.latencyMs.round()} ms',
          tone: probe == null
              ? null
              : (probe.ok ? const Color(0xFF3DD68C) : theme.colorScheme.error),
          detail: probe?.detail,
        ),
        if (status.exitCode != null)
          _Stat(
            label: 'Exit code',
            value: '${status.exitCode}',
            tone: theme.colorScheme.error,
          ),
        _Stat(label: 'Owner', value: status.origin.label, detail: _ownerDetail(status)),
      ],
    );
  }

  String? _ownerDetail(ServiceStatus status) => switch (status.origin) {
    ServiceOrigin.supervised => 'Started by the agent this run, so its terminal is captured.',
    ServiceOrigin.adopted =>
      'Left running by an earlier agent run and picked back up — the agent can restart without '
          'taking the pipeline down with it.',
    ServiceOrigin.external =>
      'Port held by ${status.portOwner?.display ?? 'another process'}. Take over would kill '
          '${status.external?.display ?? 'its root process'}.',
    ServiceOrigin.none => null,
  };

  // -------------------------------------------------------------- switches

  Widget _switches(ThemeData theme, ServiceStatus status) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _SwitchCard(
            title: 'Self-heal',
            subtitle: status.selfHeal
                ? 'The agent restarts it if it exits, and if it holds its port while failing its '
                      'probe for a minute.'
                : 'A crash stays a crash: it will sit here with its exit code and final output '
                      'until you restart it.',
            value: status.selfHeal,
            busy: _busy == 'self_heal',
            onChanged: _busy != null ? null : _setSelfHeal,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SwitchCard(
            title: 'Start at logon',
            subtitle: 'Saved now, effective once the agent replaces the startup shortcut (CP 2.5). '
                'Today the shortcut still starts these, and the agent adopts them.',
            value: status.autostart,
            busy: _busy == 'autostart',
            onChanged: _busy != null ? null : _setAutostart,
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ test

  Widget _testPanel(ThemeData theme, ServiceStatus status) {
    final scheme = theme.colorScheme;
    final test = status.lastTest;
    final tone = test == null
        ? scheme.onSurfaceVariant
        : (test.ok ? const Color(0xFF3DD68C) : scheme.error);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                test == null
                    ? Icons.science_outlined
                    : (test.ok ? Icons.check_circle_outline : Icons.error_outline),
                size: 16,
                color: tone,
              ),
              const SizedBox(width: 8),
              Text('Functional test', style: theme.textTheme.labelLarge),
              const Spacer(),
              if (test != null)
                Text(
                  '${test.durationMs.round()} ms',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            test?.summary ??
                'Not run yet. Unlike the probe, this does real work — a shell command, an '
                    'inference, a scrcpy round trip — and reports what it measured.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: test == null ? scheme.onSurfaceVariant : null,
            ),
          ),
          if (test != null && test.metrics.isNotEmpty) ..._metrics(theme, test),
        ],
      ),
    );
  }
}

/// A test reports whatever it measured, and the values are not all the same
/// shape: `231` and a 100-character model blob path both arrive as metrics.
/// Numbers read well as chips; a path does not — as a chip it either runs off
/// the card or squeezes every other chip out of the row. So the long ones drop
/// to their own full-width line underneath.
List<Widget> _metrics(ThemeData theme, TestOutcome test) {
  const inlineLimit = 40;
  final entries = test.metrics.entries.toList();
  final short = entries.where((entry) => '${entry.value}'.length <= inlineLimit);
  final long = entries.where((entry) => '${entry.value}'.length > inlineLimit);

  return [
    if (short.isNotEmpty) ...[
      const SizedBox(height: 10),
      // Wrap hands its children unbounded width, so even a chip that is meant
      // to be short is told the line width it has to fit inside.
      LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in short)
              _MetricChip(
                label: entry.key.replaceAll('_', ' '),
                value: '${entry.value}',
                maxWidth: constraints.maxWidth,
              ),
          ],
        ),
      ),
    ],
    for (final entry in long) ...[
      const SizedBox(height: 8),
      _MetricLine(label: entry.key.replaceAll('_', ' '), value: '${entry.value}'),
    ],
  ];
}

class _MetricLine extends StatelessWidget {
  const _MetricLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Tooltip(
      message: value,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(fontFamily: theme.tokens.type.mono),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.tone, this.detail});

  final String label;
  final String value;
  final Color? tone;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final box = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              color: tone,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );

    return detail == null ? box : Tooltip(message: detail!, child: box);
  }
}

class _SwitchCard extends StatelessWidget {
  const _SwitchCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.busy,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool busy;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.labelLarge),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          busy
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value, required this.maxWidth});

  final String label;
  final String value;

  /// The width of the line the chip sits on. A chip never exceeds it: the value
  /// ellipsizes and the full text moves to the tooltip.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final chip = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontFamily: theme.tokens.type.mono,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Only where it can actually be cut off — a tooltip on `231` is noise.
    return value.length > 24 ? Tooltip(message: value, child: chip) : chip;
  }
}
