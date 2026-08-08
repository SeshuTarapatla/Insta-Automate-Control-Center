import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library_models.dart';
import '../../ui/feedback.dart';
import '../../ui/layout.dart';
import '../../ui/page.dart';
import '../../ui/surfaces.dart';
import 'library_controller.dart';
import 'library_grid.dart';
import 'library_rail.dart';
import 'library_toolbar.dart';
import 'review_page.dart';

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

    final gridArea = AppPanel(
      padding: EdgeInsets.zero,
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
    );

    // Nested `ResizableSplit`s (SCREENS.md §5a), not fixed `SizedBox` rails —
    // each panel remembers its own dragged width (`persistKey`), and the
    // hardcoded 220s become just the first-run default. The entity rail
    // only exists for a non-flat folder, so it isn't always a three-pane
    // split.
    final rightOfFolders = flat
        ? gridArea
        : ResizableSplit(
            first: AppPanel(padding: EdgeInsets.zero, child: const EntityList()),
            second: gridArea,
            initialFirstSize: 220,
            minFirst: 160,
            minSecond: 400,
            persistKey: 'library.rail.entities',
          );

    // `R` — SCREENS.md §5b's keyboard entry point into review mode, next to
    // the toolbar's own Review button and the nav rail/Flows ⚑ edge (which
    // pick a folder+entity themselves via `openReviewModeForFolder`). A
    // plain character key, same as the app-wide `?` binding (D79/D80) — a
    // focused `TextField` (the entity filter box) consumes its own character
    // input before this ever sees it, so typing "r" while filtering isn't
    // expected to fire this.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyR): () {
          final images = ref.read(libraryImagesControllerProvider).value;
          if (selectedFolder == null || images == null || images.total == 0) return;
          openReviewMode(context, ref, folder: selectedFolder, entity: flat ? null : selectedEntity);
        },
      },
      child: Focus(
        autofocus: true,
        child: AppPage(
          title: 'Library',
          body: ResizableSplit(
            first: AppPanel(padding: EdgeInsets.zero, child: const FolderRail()),
            second: rightOfFolders,
            initialFirstSize: 220,
            minFirst: 160,
            minSecond: 400,
            persistKey: 'library.rail.folders',
          ),
        ),
      ),
    );
  }
}
