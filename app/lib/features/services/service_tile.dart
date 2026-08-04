import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/service_models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/icons.dart';
import '../../ui/status.dart';
import '../../ui/surfaces.dart';
import '../../ui/text.dart';
import 'service_status_kind.dart';
import 'services_controller.dart';

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
    final tokens = theme.tokens;
    final color = status.state.color(theme);

    return AppCard(
      onTap: onTap,
      selected: selected,
      padding: EdgeInsets.symmetric(horizontal: tokens.space.md, vertical: tokens.space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusDot(kind: status.state.statusKind, pulsing: status.state.isTransient),
              SizedBox(width: tokens.space.sm),
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
                  child: AppIcon(AppIcons.selfHeal, size: IconSize.sm, color: tokens.content.secondary),
                ),
            ],
          ),
          SizedBox(height: tokens.space.sm),
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
                      SizedBox(width: tokens.space.xs),
                      Flexible(child: StatusChip(kind: StatusKind.neutral, label: status.origin.label, dense: true)),
                    ],
                  ],
                ),
              ),
              if (status.liveUptimeS != null) ...[
                SizedBox(width: tokens.space.sm),
                NumericText(formatUptime(status.liveUptimeS!), role: TextRole.caption, color: tokens.content.secondary),
              ],
            ],
          ),
          SizedBox(height: tokens.space.xs),
          MonoText(
            _subtitle(),
            role: TextRole.caption,
            color: tokens.content.secondary.withValues(alpha: 0.8),
          ),
        ],
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
