// SCREENS.md §1 — a ~140px-wide summary of one flow: status dot, name,
// one-line state, no controls. Overview *summarises*; Flows *controls* — the
// fix for AUDIT §12's duplication, where Overview used to embed five full
// 360px `FlowCard`s.
import 'package:flutter/material.dart';

import '../../core/scheduler_models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/status.dart';
import '../../ui/surfaces.dart';
import '../flows/flow_status.dart';

class FlowCardCompact extends StatelessWidget {
  const FlowCardCompact({super.key, required this.state});

  final FlowState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final kind = flowStatusKindOf(state);
    final accent = flowAccent(kind);

    return SizedBox(
      width: 140,
      child: AppCard(
        accentEdge: accent,
        padding: EdgeInsets.symmetric(horizontal: tokens.space.sm, vertical: tokens.space.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                StatusDot(kind: accent, pulsing: kind == FlowStatusKind.running, size: 8),
                SizedBox(width: tokens.space.xs),
                Expanded(
                  child: Text(
                    (flowTitle[state.flow] ?? state.flow).toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 0.4),
                  ),
                ),
              ],
            ),
            SizedBox(height: tokens.space.xs / 2),
            Text(
              flowStatusLabel(kind, state),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: kind == FlowStatusKind.blocked ? tokens.status.warn.fg : tokens.content.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
