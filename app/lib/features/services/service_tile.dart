import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/service_models.dart';
import 'services_controller.dart';
import 'status_dot.dart';

/// One service in the left-hand list: enough to triage at a glance (state,
/// uptime, restarts, probe latency), with the detail pane holding everything
/// else.
class ServiceTile extends ConsumerWidget {
  const ServiceTile({
    super.key,
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final ServiceStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(uptimeTickProvider);

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = status.state.color(theme);

    return Material(
      color: selected ? scheme.surfaceContainerHighest : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? scheme.primary.withValues(alpha: 0.7) : scheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusDot(state: status.state),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      status.label,
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!status.selfHeal)
                    Tooltip(
                      message: 'Self-heal is off — a crash stays a crash',
                      child: Icon(
                        Icons.healing_outlined,
                        size: 15,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  // The state and its origin badge give way to the uptime
                  // rather than pushing it off the tile: at 300 px "Restarting"
                  // beside an "external" badge already fills the row.
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            status.state.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(color: color),
                          ),
                        ),
                        if (status.origin == ServiceOrigin.adopted ||
                            status.origin == ServiceOrigin.external) ...[
                          const SizedBox(width: 6),
                          Flexible(child: _Pill(text: status.origin.label)),
                        ],
                      ],
                    ),
                  ),
                  if (status.liveUptimeS != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      formatUptime(status.liveUptimeS!),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _subtitle(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                  fontFamily: 'Consolas',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The one line worth spending on a tile: whichever fact explains the current
  /// state. A failure explains itself; a healthy service reports its probe.
  String _subtitle() {
    if (status.error != null) return status.error!;
    if (status.state == ServiceState.failed && status.exitCode != null) {
      return 'exited with code ${status.exitCode}';
    }
    final probe = status.probe;
    if (probe == null) return 'port ${status.port} · no probe yet';
    final latency = '${probe.latencyMs.round()} ms';
    return probe.ok ? '$latency · ${probe.detail}' : probe.detail;
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
