import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_state_view.dart';
import '../../core/library_models.dart';
import 'library_controller.dart';
import 'library_tile.dart';

/// The virtualized image grid: `GridView.builder` already only builds visible
/// tiles (Flutter-level virtualization), and `_maybeLoadMore` pages in the
/// rest of a folder as the user scrolls rather than fetching it all up front
/// — folders here run to thousands of files (ARCHITECTURE §1.1).
///
/// Keyboard multi-select (arrows/space/shift-range/ctrl-A, CP 5.3) needs a
/// known column count to turn Up/Down into "move by one row," which
/// `SliverGridDelegateWithMaxCrossAxisExtent` doesn't expose — using
/// `SliverGridDelegateWithFixedCrossAxisCount` instead, with the count
/// computed once per layout from the zoom level, gives exact arithmetic for
/// both the grid and the scroll-into-view math below.
class LibraryGrid extends ConsumerStatefulWidget {
  const LibraryGrid({super.key, required this.entityLabel, required this.onDeleteRequested});

  final String? entityLabel;
  final VoidCallback onDeleteRequested;

  @override
  ConsumerState<LibraryGrid> createState() => _LibraryGridState();
}

class _LibraryGridState extends ConsumerState<LibraryGrid> {
  final _scrollController = ScrollController();
  final _focusNode = FocusNode(debugLabel: 'LibraryGrid');
  static const _padding = 16.0;
  static const _spacing = 8.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_maybeLoadMore);
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 800) {
      ref.read(libraryImagesControllerProvider.notifier).loadMore();
    }
  }

  int _crossAxisCount(double gridWidth, double tileWidth) => (gridWidth / tileWidth).floor().clamp(1, 200);

  void _scrollToIndex(int index, int crossAxisCount, double rowStep) {
    if (!_scrollController.hasClients) return;
    final row = index ~/ crossAxisCount;
    final top = _padding + row * rowStep;
    final bottom = top + rowStep - _spacing;
    final viewTop = _scrollController.offset;
    final viewBottom = viewTop + _scrollController.position.viewportDimension;
    if (top < viewTop) {
      _scrollController.animateTo(top, duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
    } else if (bottom > viewBottom) {
      _scrollController.animateTo(
        bottom - _scrollController.position.viewportDimension,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    }
  }

  KeyEventResult _handleKey(KeyEvent event, List<LibraryImageEntry> images, int crossAxisCount, double rowStep) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (images.isEmpty) return KeyEventResult.ignored;

    final notifier = ref.read(librarySelectionProvider.notifier);
    final current = ref.read(librarySelectionProvider);
    final key = event.logicalKey;

    if (HardwareKeyboard.instance.isControlPressed && key == LogicalKeyboardKey.keyA) {
      ref.read(libraryImagesControllerProvider.notifier).loadAllNames().then(notifier.selectAll);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      final index = current.focusedIndex ?? 0;
      if (index < images.length) notifier.toggle(index, images[index].name);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete && current.selected.isNotEmpty) {
      widget.onDeleteRequested();
      return KeyEventResult.handled;
    }

    final delta = switch (key) {
      LogicalKeyboardKey.arrowLeft => -1,
      LogicalKeyboardKey.arrowRight => 1,
      LogicalKeyboardKey.arrowUp => -crossAxisCount,
      LogicalKeyboardKey.arrowDown => crossAxisCount,
      _ => null,
    };
    if (delta == null) return KeyEventResult.ignored;

    final from = current.focusedIndex ?? 0;
    final to = (from + delta).clamp(0, images.length - 1);
    if (HardwareKeyboard.instance.isShiftPressed) {
      notifier.selectRange(to, images);
    } else {
      // Plain arrow only moves focus — it must never touch the selection, or
      // "arrow, space, arrow, space" (the whole point of keyboard multi-select)
      // would lose whatever Space just added the moment you moved off it.
      notifier.moveFocus(to);
    }
    _scrollToIndex(to, crossAxisCount, rowStep);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final imagesAsync = ref.watch(libraryImagesControllerProvider);
    final zoom = ref.watch(libraryZoomProvider);
    final selection = ref.watch(librarySelectionProvider);

    return imagesAsync.stateView(
      onRetry: () => ref.read(libraryImagesControllerProvider.notifier).reload(),
      describeError: (error) => 'Could not load this folder: $error',
      data: (data) {
        if (data.images.isEmpty) {
          return const EmptyView(icon: Icons.image_not_supported_outlined, title: 'No images here.');
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final gridWidth = constraints.maxWidth - _padding * 2;
            final crossAxisCount = _crossAxisCount(gridWidth, zoom.tileWidth);
            final rowStep = gridWidth / crossAxisCount + _spacing;

            return Focus(
              focusNode: _focusNode,
              onKeyEvent: (node, event) => _handleKey(event, data.images, crossAxisCount, rowStep),
              child: GridView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(_padding),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: _spacing,
                  crossAxisSpacing: _spacing,
                  childAspectRatio: 1,
                ),
                itemCount: data.images.length + (data.hasMore ? crossAxisCount : 0),
                itemBuilder: (context, index) {
                  if (index >= data.images.length) {
                    return const Center(
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  }
                  final entry = data.images[index];
                  return LibraryTile(
                    entry: entry,
                    selected: selection.selected.contains(entry.name),
                    focused: selection.focusedIndex == index,
                    thumbWidth: zoom.tileWidth.round(),
                    entityLabel: widget.entityLabel,
                    onRequestFocus: _focusNode.requestFocus,
                    onPrimaryTap: ({required shift}) {
                      if (shift) {
                        ref.read(librarySelectionProvider.notifier).selectRange(index, data.images);
                      } else {
                        // Plain click toggles — no ctrl needed. Clicking several
                        // images in a row is how you build up a batch.
                        ref.read(librarySelectionProvider.notifier).toggle(index, entry.name);
                      }
                    },
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
