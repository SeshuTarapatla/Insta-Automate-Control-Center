// One connector between two `FlowNode`s (SCREENS.md §2). Carries the live
// backlog count behind it (`GET /api/library/folders`, already exists — no
// agent work needed) and, for the two human-review stages, a ⚑ that jumps
// straight into Library review mode for that folder — the first time the
// app has ever shown that the pipeline waits on the user at two specific
// points.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/nav_state.dart';
import '../../core/theme/tokens.dart';
import '../../ui/icons.dart';
import '../../ui/text.dart';
import '../library/library_controller.dart';
import 'flow_status.dart';

class PipelineEdge extends ConsumerWidget {
  const PipelineEdge({
    super.key,
    required this.label,
    required this.count,
    this.reviewFolder,
    this.warn = false,
  });

  /// The `IA_DIR`-relative folder name shown, e.g. `entities/ queued`.
  final String label;
  final int count;

  /// Non-null for the two ⚑ human-review edges — the library folder name to
  /// jump to. Null for a plain pipeline edge.
  final String? reviewFolder;

  /// True once this edge's backlog exceeds its reserve target — the visible
  /// form of D86/D91's reserve gates (SCRAPE_RESERVE_FACTOR/SCAN_RESERVE_TARGET).
  final bool warn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final review = reviewFolder != null;
    final lineColor = warn ? tokens.status.warn.fg : tokens.surface.borderStrong;
    final textColor = warn ? tokens.status.warn.fg : tokens.content.secondary;

    final content = Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: label),
                if (review)
                  TextSpan(
                    text: '  →  YOU REVIEW',
                    style: TextStyle(color: tokens.status.info.fg, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
            style: theme.textTheme.bodySmall?.copyWith(color: textColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(width: tokens.space.sm),
        NumericText(count, role: TextRole.caption, color: textColor),
        if (review) ...[
          SizedBox(width: tokens.space.xs),
          AppIcon(AppIcons.chevronRight, size: IconSize.sm, color: tokens.content.secondary),
        ],
      ],
    );

    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: flowNodeIconGutter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: tokens.geometry.hairline * 2, height: 8, color: lineColor),
                AppIcon(review ? AppIcons.review : AppIcons.chevronDown, size: IconSize.sm, color: lineColor),
                Container(width: tokens.geometry.hairline * 2, height: 8, color: lineColor),
              ],
            ),
          ),
          SizedBox(width: tokens.space.sm),
          Expanded(child: content),
        ],
      ),
    );

    if (!review) return row;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: () {
          ref.read(selectedFolderProvider.notifier).select(reviewFolder);
          ref.read(selectedEntityProvider.notifier).select(null);
          ref.read(selectedNavIndexProvider.notifier).select(libraryIndex);
        },
        borderRadius: BorderRadius.circular(tokens.geometry.radiusSm),
        child: row,
      ),
    );
  }
}
