import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library_models.dart';
import '../../core/theme/tokens.dart';
import '../../ui/feedback.dart';
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
    // Per-folder, not a bare `1` — SCREENS.md §5a-0, the highest-impact
    // single Library fix: a row-crop folder's real cells are a 5.45:1
    // strip, a full-page folder's are a 1:2.08 portrait, and a near-square
    // cell wasted 40–82% of every one of them.
    final aspectRatio = libraryAspectRatioFor(ref.watch(selectedFolderProvider));

    return imagesAsync.stateView(
      onRetry: () => ref.read(libraryImagesControllerProvider.notifier).reload(),
      describeError: (error) => 'Could not load this folder: $error',
      skeleton: _GridSkeleton(tileWidth: zoom.tileWidth, aspectRatio: aspectRatio),
      data: (data) {
        if (data.images.isEmpty) {
          return const EmptyView(icon: Icons.image_not_supported_outlined, title: 'No images here.');
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final gridWidth = constraints.maxWidth - _padding * 2;
            final crossAxisCount = _crossAxisCount(gridWidth, zoom.tileWidth);
            // The real cell height, not the (former, square-cell) assumption
            // that it equals the cell width — the scroll-into-view and
            // arrow-key row math both depend on this being right or every
            // row after the first drifts out of sync with what's on screen.
            final cellHeight = (gridWidth / crossAxisCount) / aspectRatio;
            final rowStep = cellHeight + _spacing;

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
                  childAspectRatio: aspectRatio,
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

/// A grid-shaped skeleton (COMPONENTS.md §8) for the moment before the first
/// page of a folder arrives — the grid's shape (a folder's real aspect
/// ratio, roughly how many columns) is known before the data is, so this
/// reads as faster than a bare spinner at identical latency.
class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton({required this.tileWidth, required this.aspectRatio});

  final double tileWidth;
  final double aspectRatio;

  static const _padding = 16.0;
  static const _spacing = 8.0;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final gridWidth = constraints.maxWidth - _padding * 2;
        final crossAxisCount = (gridWidth / tileWidth).floor().clamp(1, 200);
        final cellHeight = (gridWidth / crossAxisCount) / aspectRatio;
        // Enough rows to plausibly fill the viewport without measuring it —
        // a skeleton that runs a little short or long of the real content
        // is fine, since it's replaced the instant real data arrives.
        final rows = (constraints.maxHeight / (cellHeight + _spacing)).ceil() + 1;

        return GridView.builder(
          padding: const EdgeInsets.all(_padding),
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: _spacing,
            crossAxisSpacing: _spacing,
            childAspectRatio: aspectRatio,
          ),
          itemCount: crossAxisCount * rows,
          // A tight grid cell forces `SkeletonBox` to its real size
          // regardless of the (irrelevant, default) height passed here —
          // `RenderConstrainedBox.enforce()` clamps it to the incoming
          // tight constraint either way.
          itemBuilder: (context, index) => SkeletonBox(radius: tokens.geometry.radiusSm),
        );
      },
    );
  }
}
