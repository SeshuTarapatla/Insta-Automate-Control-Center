import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/feedback.dart';
import '../../core/library_models.dart';
import 'library_controller.dart';
import 'library_grid.dart';
import 'library_rail.dart';
import 'library_toolbar.dart';

/// Three columns: the seven folders, the entity roots inside whichever one is
/// selected (skipped for the flat `entities` folder), and the grid itself
/// with its toolbar. CP 5.1/5.2 already built everything this reads and
/// writes — `GET/POST /api/library/*` and the `library.changes` channel.
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(libraryFoldersControllerProvider);
    final selectedFolder = ref.watch(selectedFolderProvider);
    final selectedEntity = ref.watch(selectedEntityProvider);

    // Page-level guard only for the states `.value` can't paper over — once
    // a first list has ever loaded, a slow/erroring re-fetch keeps showing
    // the stale layout rather than replacing it with a spinner (same "don't
    // flash a loading state over content the user is looking at" choice the
    // rest of the app already makes).
    if (foldersAsync.isLoading && !foldersAsync.hasValue) return const LoadingView();
    if (foldersAsync.hasError && !foldersAsync.hasValue) {
      return ErrorView(
        message: '${foldersAsync.error}',
        onRetry: () => ref.invalidate(libraryFoldersControllerProvider),
      );
    }

    final flat = foldersAsync.value?.where((f) => f.name == selectedFolder).firstOrNull?.flat ?? true;
    final showGrid = selectedFolder != null && (flat || selectedEntity != null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 220, child: Card(margin: EdgeInsets.zero, child: const FolderRail())),
          if (!flat) ...[
            const SizedBox(width: 12),
            SizedBox(width: 220, child: Card(margin: EdgeInsets.zero, child: const EntityList())),
          ],
          const SizedBox(width: 12),
          Expanded(
            child: Card(
              margin: EdgeInsets.zero,
              child: selectedFolder == null
                  ? const EmptyView(icon: Icons.folder_off_outlined, title: 'No folders yet.')
                  : !showGrid
                  ? const EmptyView(icon: Icons.touch_app_outlined, title: 'Pick an entity to browse its images.')
                  : Column(
                      children: [
                        LibraryToolbar(folder: selectedFolder, entity: flat ? null : selectedEntity),
                        const Divider(height: 1),
                        Expanded(
                          child: LibraryGrid(
                            entityLabel: flat ? null : selectedEntity,
                            onDeleteRequested: () {
                              final selection = ref.read(librarySelectionProvider).selected;
                              final images = ref.read(libraryImagesControllerProvider).value?.images ?? const <LibraryImageEntry>[];
                              final selectedEntries = images.where((e) => selection.contains(e.name)).toList();
                              deleteLibrarySelection(context, ref, selectedEntries);
                            },
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
