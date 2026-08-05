// SCREENS.md §1 — "the most valuable thing on the page": the two
// human-in-the-loop backlogs (`gender_valid` → `scrape_queued`,
// `scraped` → `follow_queued`) that are the pipeline's actual bottleneck,
// visible today only by navigating to Library and reading the folder rail.
// Same folders and the same jump-to-Library-review behaviour as V2.6's ⚑
// `PipelineEdge`s.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library_models.dart';
import '../../core/nav_state.dart';
import '../../core/theme/tokens.dart';
import '../../ui/buttons.dart';
import '../../ui/icons.dart';
import '../../ui/text.dart';
import '../library/library_controller.dart';

const curationFolders = ['gender_valid', 'scraped'];

class CurationTile extends ConsumerWidget {
  const CurationTile({super.key, required this.folders});

  final List<LibraryFolderInfo> folders;

  int _count(String folder) => folders.where((f) => f.name == folder).map((f) => f.total).firstOrNull ?? 0;

  void _openLibrary(WidgetRef ref, String folder) {
    ref.read(selectedFolderProvider.notifier).select(folder);
    ref.read(selectedEntityProvider.notifier).select(null);
    ref.read(selectedNavIndexProvider.notifier).select(libraryIndex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final folder in curationFolders)
          Padding(
            padding: EdgeInsets.only(bottom: tokens.space.sm),
            child: InkWell(
              onTap: () => _openLibrary(ref, folder),
              borderRadius: BorderRadius.circular(tokens.geometry.radiusSm),
              child: Row(
                children: [
                  AppIcon(AppIcons.review, size: IconSize.sm, color: tokens.status.info.fg),
                  SizedBox(width: tokens.space.xs),
                  Expanded(
                    child: Text('$folder/', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                  ),
                  NumericText(_count(folder), role: TextRole.body),
                ],
              ),
            ),
          ),
        SizedBox(height: tokens.space.xs),
        AppButton(label: 'Review →', onPressed: () => _openLibrary(ref, curationFolders.first)),
      ],
    );
  }
}
