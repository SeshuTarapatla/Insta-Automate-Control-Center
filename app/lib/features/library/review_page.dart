// SCREENS.md §5b — Library review mode, the headline feature of v2. A
// full-window route (pushed via the root Navigator, covering the title bar
// and nav rail the same way the ASCII mockup shows no app chrome at all)
// over a keep/discard decision buffer for one `(folder, entity)` at a time.
//
// Nothing is written until Apply, which reuses `applyLibrarySelection` —
// the exact same `POST /api/library/apply` call and confirm dialog the
// grid's own toolbar button already uses. `Del` is the one exception: a
// real, immediate delete via the shared `deleteLibrarySelection`, same as
// every other delete path in this app.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_snack_bar.dart';
import '../../core/file_opener.dart';
import '../../core/instagram_url.dart';
import '../../core/library_image.dart';
import '../../core/library_models.dart';
import '../../core/nav_state.dart';
import '../../core/theme/tokens.dart';
import '../../ui/icons.dart';
import '../../ui/text.dart';
import 'library_controller.dart';
import 'library_toolbar.dart';

Future<void> openReviewMode(BuildContext context, WidgetRef ref, {required String folder, String? entity}) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => LibraryReviewPage(folder: folder, entity: entity)),
  );
}

Future<void> openLightbox(
  BuildContext context,
  WidgetRef ref, {
  required String folder,
  String? entity,
  required int startIndex,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => LibraryLightboxPage(folder: folder, entity: entity, startIndex: startIndex),
    ),
  );
}

/// Selects [folder] — and, for a non-flat folder, its first entity that
/// actually has a backlog — before pushing into review mode. The nav rail's
/// Review sub-item and the Flows ⚑ edges both use this: SCREENS.md §5b lists
/// both as review-mode entry points, not just folder navigation, and
/// `pipeline_edge.dart`'s own comment already promised "jumps straight into
/// Library review mode." The toolbar's own Review button already has a
/// folder/entity chosen by the user and calls [openReviewMode] directly.
Future<void> openReviewModeForFolder(BuildContext context, WidgetRef ref, String folder) async {
  ref.read(selectedFolderProvider.notifier).select(folder);
  ref.read(selectedEntityProvider.notifier).select(null);
  ref.read(selectedNavIndexProvider.notifier).select(libraryIndex);

  final folders = await ref.read(libraryFoldersControllerProvider.future);
  final info = folders.where((f) => f.name == folder).firstOrNull;
  String? entity;
  if (info != null && !info.flat) {
    final entities = await ref.read(libraryEntitiesControllerProvider.future);
    entity = entities.where((e) => e.count > 0).firstOrNull?.root;
    if (entity == null) return; // nothing queued anywhere in this folder
    ref.read(selectedEntityProvider.notifier).select(entity);
  }
  if (!context.mounted) return;
  await openReviewMode(context, ref, folder: folder, entity: entity);
}

String _idFromName(String name) => name.endsWith('.jpg') ? name.substring(0, name.length - 4) : name;

class LibraryReviewPage extends ConsumerStatefulWidget {
  const LibraryReviewPage({super.key, required this.folder, required this.entity});

  final String folder;
  final String? entity;

  @override
  ConsumerState<LibraryReviewPage> createState() => _LibraryReviewPageState();
}

class _LibraryReviewPageState extends ConsumerState<LibraryReviewPage> {
  final _decisions = <String, bool>{};
  int _position = 0;
  bool _zoomFit = true;
  final _focusNode = FocusNode(debugLabel: 'LibraryReviewPage');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  // Pages in the next batch well before the reviewer actually reaches the
  // loaded boundary — the same "never present a partial set as the whole
  // folder" requirement D90 caught on mobile, just enforced here by staying
  // ahead of the read position instead of a scroll listener. Deferred to a
  // post-frame callback: `loadMore()` writes `state` as its first statement
  // (`loadingMore: true`), and Riverpod forbids mutating a provider from
  // inside a widget's own `build()`.
  void _maybePageMore(LibraryImagesState state) {
    if (!state.hasMore || state.loadingMore) return;
    if (_position < state.images.length - 20) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(libraryImagesControllerProvider.notifier).loadMore();
    });
  }

  void _decide(List<LibraryImageEntry> images, bool keep) {
    if (_position >= images.length) return;
    setState(() {
      _decisions[images[_position].name] = keep;
      _position = (_position + 1).clamp(0, images.length);
    });
  }

  void _toggleCurrent(List<LibraryImageEntry> images) {
    if (_position >= images.length) return;
    final name = images[_position].name;
    setState(() {
      final current = _decisions[name];
      _decisions[name] = current == null ? true : !current;
    });
  }

  void _back(List<LibraryImageEntry> images) {
    if (_position == 0) return;
    setState(() {
      _position -= 1;
      _decisions.remove(images[_position].name);
    });
  }

  Future<void> _deleteCurrent(List<LibraryImageEntry> images) async {
    if (_position >= images.length) return;
    await deleteLibrarySelection(context, ref, [images[_position]]);
  }

  void _openInstagram(List<LibraryImageEntry> images) {
    if (_position >= images.length) return;
    final uri = instagramUrl(images[_position].name);
    if (!FileOpener.openUrl(uri.toString()) && mounted) {
      AppSnackBar.show(context, 'Could not open $uri', isError: true);
    }
  }

  Future<void> _apply(String target) async {
    final selected = _decisions.entries.where((e) => e.value).map((e) => e.key).toSet();
    final applied = await applyLibrarySelection(context, ref, folder: widget.folder, selected: selected, target: target);
    if (applied && mounted) Navigator.of(context).pop();
  }

  KeyEventResult _handleKey(KeyEvent event, List<LibraryImageEntry> images, bool canApply, String target) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.keyL:
        _decide(images, true);
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.keyH:
        _decide(images, false);
      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.keyK:
        _back(images);
      case LogicalKeyboardKey.space:
        _toggleCurrent(images);
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        if (canApply) _apply(target);
      case LogicalKeyboardKey.delete:
        _deleteCurrent(images);
      case LogicalKeyboardKey.keyZ:
        setState(() => _zoomFit = !_zoomFit);
      case LogicalKeyboardKey.keyO:
        _openInstagram(images);
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    final imagesAsync = ref.watch(libraryImagesControllerProvider);
    final targets = ref.watch(moveTargetsControllerProvider).value;
    final target = targets?[widget.folder] ?? widget.folder;

    return Scaffold(
      backgroundColor: tokens.surface.canvas,
      body: SafeArea(
        child: imagesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('$error')),
          data: (state) {
            _maybePageMore(state);
            final images = state.images;
            final position = _position.clamp(0, images.length);
            // The whole loaded set must be decided, with nothing left to
            // page in, before Apply is allowed — otherwise Apply's own
            // `POST /api/library/apply` (whole-directory scoped) would trash
            // every image past whatever's been decided so far. Same class of
            // bug D90 caught on mobile.
            final canApply = !state.hasMore && images.isNotEmpty && images.every((e) => _decisions.containsKey(e.name));
            final keepCount = _decisions.values.where((v) => v).length;
            final discardCount = _decisions.values.where((v) => !v).length;

            return Focus(
              autofocus: true,
              focusNode: _focusNode,
              onKeyEvent: (node, event) => _handleKey(event, images, canApply, target),
              child: Column(
                children: [
                  _ReviewHeader(
                    folder: widget.folder,
                    entity: widget.entity,
                    position: position,
                    total: state.total,
                    onClose: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: images.isEmpty
                        ? const Center(child: Text('Nothing left to review.'))
                        : position >= images.length
                        // Reached the loaded boundary but more pages exist —
                        // `_maybePageMore` has already requested them; this is
                        // the wait, not "done." Showing `_ReviewDone` here
                        // would be exactly the "partial set as the whole
                        // folder" bug D90 caught on mobile, just one frame
                        // earlier in the sequence.
                        ? (state.hasMore || state.loadingMore)
                              ? const Center(child: CircularProgressIndicator())
                              : _ReviewDone(keep: keepCount, discard: discardCount)
                        : _ReviewStage(
                            entry: images[position],
                            root: widget.entity,
                            zoomFit: _zoomFit,
                            onToggleZoom: () => setState(() => _zoomFit = !_zoomFit),
                            onKeep: () => _decide(images, true),
                            onDiscard: () => _decide(images, false),
                            onOpenInstagram: () => _openInstagram(images),
                          ),
                  ),
                  if (images.isNotEmpty)
                    _ReviewFilmstrip(
                      images: images,
                      decisions: _decisions,
                      position: position,
                      keep: keepCount,
                      discard: discardCount,
                      canApply: canApply,
                      onJump: (i) => setState(() => _position = i),
                      onApply: () => _apply(target),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReviewHeader extends StatelessWidget {
  const _ReviewHeader({
    required this.folder,
    required this.entity,
    required this.position,
    required this.total,
    required this.onClose,
  });

  final String folder;
  final String? entity;
  final int position;
  final int total;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final progress = total == 0 ? 0.0 : (position / total).clamp(0.0, 1.0);

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(tokens.space.lg, tokens.space.md, tokens.space.md, tokens.space.md),
          child: Row(
            children: [
              AppIcon(AppIcons.review, size: IconSize.md, color: tokens.status.info.fg),
              SizedBox(width: tokens.space.sm),
              Expanded(
                child: Text(
                  entity == null ? 'REVIEW · $folder' : 'REVIEW · $folder / $entity',
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              NumericText('${(position + 1).clamp(0, total == 0 ? 0 : total)}', role: TextRole.body),
              Text(' of ', style: theme.textTheme.bodyMedium?.copyWith(color: tokens.content.secondary)),
              NumericText(total, role: TextRole.body),
              SizedBox(width: tokens.space.lg),
              IconButton(tooltip: 'Close (Esc)', icon: AppIcon(AppIcons.close, size: IconSize.md), onPressed: onClose),
            ],
          ),
        ),
        LinearProgressIndicator(value: progress, minHeight: 3),
      ],
    );
  }
}

class _ReviewStage extends StatelessWidget {
  const _ReviewStage({
    required this.entry,
    required this.root,
    required this.zoomFit,
    required this.onToggleZoom,
    required this.onKeep,
    required this.onDiscard,
    required this.onOpenInstagram,
  });

  final LibraryImageEntry entry;
  final String? root;
  final bool zoomFit;
  final VoidCallback onToggleZoom;
  final VoidCallback onKeep;
  final VoidCallback onDiscard;
  final VoidCallback onOpenInstagram;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.all(tokens.space.lg),
            child: AnimatedSwitcher(
              duration: tokens.motion.reduced ? Duration.zero : tokens.motion.standard,
              switchInCurve: tokens.motion.enter,
              switchOutCurve: tokens.motion.exit,
              child: ClipRRect(
                key: ValueKey(entry.path),
                borderRadius: BorderRadius.circular(tokens.geometry.radiusMd),
                child: ColoredBox(
                  color: tokens.surface.raised,
                  child: LibraryFullImage(path: entry.path, zoomFit: zoomFit),
                ),
              ),
            ),
          ),
        ),
        Text('@${_idFromName(entry.name)}', style: theme.textTheme.titleMedium),
        SizedBox(height: tokens.space.xs),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (root != null) ...[
              Text('root: $root', style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary)),
              SizedBox(width: tokens.space.sm),
              Text('·', style: TextStyle(color: tokens.content.secondary)),
              SizedBox(width: tokens.space.sm),
            ],
            InkWell(
              onTap: onOpenInstagram,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('open on Instagram', style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary)),
                  SizedBox(width: tokens.space.xs),
                  AppIcon(AppIcons.openExternal, size: IconSize.sm, color: tokens.content.secondary),
                ],
              ),
            ),
            SizedBox(width: tokens.space.lg),
            IconButton(
              tooltip: zoomFit ? 'Actual size (Z)' : 'Zoom to fit (Z)',
              icon: AppIcon(zoomFit ? AppIcons.expand : AppIcons.collapse, size: IconSize.sm, color: tokens.content.secondary),
              onPressed: onToggleZoom,
            ),
          ],
        ),
        SizedBox(height: tokens.space.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: onDiscard,
              style: FilledButton.styleFrom(backgroundColor: tokens.status.bad.fg, foregroundColor: tokens.status.bad.onContainer),
              icon: AppIcon(AppIcons.close, size: IconSize.md),
              label: const Text('Discard   ←'),
            ),
            SizedBox(width: tokens.space.lg),
            FilledButton.icon(
              onPressed: onKeep,
              style: FilledButton.styleFrom(backgroundColor: tokens.status.good.fg, foregroundColor: tokens.status.good.onContainer),
              icon: AppIcon(AppIcons.check, size: IconSize.md),
              label: const Text('Keep   →'),
            ),
          ],
        ),
        SizedBox(height: tokens.space.lg),
      ],
    );
  }
}

class _ReviewDone extends StatelessWidget {
  const _ReviewDone({required this.keep, required this.discard});

  final int keep;
  final int discard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(AppIcons.check, size: IconSize.lg, color: tokens.status.good.fg),
          SizedBox(height: tokens.space.md),
          Text('All reviewed — $keep keep · $discard discard', style: theme.textTheme.titleMedium),
          SizedBox(height: tokens.space.xs),
          Text('Apply batch below to save.', style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary)),
        ],
      ),
    );
  }
}

/// Every decision so far, a dot per image, clickable to jump back — with the
/// current position kept in view as it moves via a fixed [_itemExtent] scroll
/// calculation, the same style `library_grid.dart`'s `_scrollToIndex` uses.
class _ReviewFilmstrip extends StatefulWidget {
  const _ReviewFilmstrip({
    required this.images,
    required this.decisions,
    required this.position,
    required this.keep,
    required this.discard,
    required this.canApply,
    required this.onJump,
    required this.onApply,
  });

  final List<LibraryImageEntry> images;
  final Map<String, bool> decisions;
  final int position;
  final int keep;
  final int discard;
  final bool canApply;
  final ValueChanged<int> onJump;
  final VoidCallback onApply;

  @override
  State<_ReviewFilmstrip> createState() => _ReviewFilmstripState();
}

class _ReviewFilmstripState extends State<_ReviewFilmstrip> {
  final _controller = ScrollController();
  static const _itemExtent = 14.0;

  @override
  void didUpdateWidget(covariant _ReviewFilmstrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
    }
  }

  void _scrollToCurrent() {
    if (!_controller.hasClients) return;
    final target = (widget.position * _itemExtent - _controller.position.viewportDimension / 2).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    _controller.animateTo(target, duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: tokens.space.lg, vertical: tokens.space.sm),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: tokens.surface.border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 18,
            child: ListView.builder(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              itemExtent: _itemExtent,
              itemCount: widget.images.length,
              itemBuilder: (context, index) {
                final entry = widget.images[index];
                final decision = widget.decisions[entry.name];
                final current = index == widget.position;
                final color = decision == null
                    ? tokens.surface.borderStrong
                    : (decision ? tokens.status.good.fg : tokens.status.bad.fg);
                return Padding(
                  key: ValueKey('review-dot-$index'),
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: InkWell(
                    onTap: () => widget.onJump(index),
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                        border: current ? Border.all(color: tokens.content.primary, width: 2) : null,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(height: tokens.space.sm),
          Row(
            children: [
              NumericText(widget.keep, role: TextRole.body, color: tokens.status.good.fg),
              Text(' keep · ', style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color)),
              NumericText(widget.discard, role: TextRole.body, color: tokens.status.bad.fg),
              Text(' discard', style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color)),
              const Spacer(),
              FilledButton.icon(
                onPressed: widget.canApply ? widget.onApply : null,
                icon: AppIcon(AppIcons.apply, size: IconSize.sm),
                label: const Text('Apply batch   ⏎'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The double-click lightbox (SCREENS.md §5c) — the same large single-image
/// view review mode uses, minus the decision buffer: prev/next only, nothing
/// buffered or written. For people browsing rather than batch-reviewing.
class LibraryLightboxPage extends ConsumerStatefulWidget {
  const LibraryLightboxPage({super.key, required this.folder, required this.entity, required this.startIndex});

  final String folder;
  final String? entity;
  final int startIndex;

  @override
  ConsumerState<LibraryLightboxPage> createState() => _LibraryLightboxPageState();
}

class _LibraryLightboxPageState extends ConsumerState<LibraryLightboxPage> {
  late int _position = widget.startIndex;
  bool _zoomFit = true;
  final _focusNode = FocusNode(debugLabel: 'LibraryLightboxPage');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _openInstagram(LibraryImageEntry entry) {
    final uri = instagramUrl(entry.name);
    if (!FileOpener.openUrl(uri.toString()) && mounted) {
      AppSnackBar.show(context, 'Could not open $uri', isError: true);
    }
  }

  KeyEventResult _handleKey(KeyEvent event, List<LibraryImageEntry> images) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.keyL:
        if (_position < images.length - 1) setState(() => _position++);
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.keyH:
        if (_position > 0) setState(() => _position--);
      case LogicalKeyboardKey.keyZ:
        setState(() => _zoomFit = !_zoomFit);
      case LogicalKeyboardKey.keyO:
        if (_position < images.length) _openInstagram(images[_position]);
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final imagesAsync = ref.watch(libraryImagesControllerProvider);

    return Scaffold(
      backgroundColor: tokens.surface.canvas,
      body: SafeArea(
        child: imagesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('$error')),
          data: (state) {
            final images = state.images;
            if (images.isEmpty) return const Center(child: Text('Nothing to show.'));
            final position = _position.clamp(0, images.length - 1);
            final entry = images[position];

            return Focus(
              autofocus: true,
              focusNode: _focusNode,
              onKeyEvent: (node, event) => _handleKey(event, images),
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(tokens.space.lg, tokens.space.md, tokens.space.md, tokens.space.md),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.entity == null ? widget.folder : '${widget.folder} / ${widget.entity}',
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        NumericText('${position + 1}', role: TextRole.body),
                        Text(' of ', style: theme.textTheme.bodyMedium?.copyWith(color: tokens.content.secondary)),
                        NumericText(images.length, role: TextRole.body),
                        SizedBox(width: tokens.space.lg),
                        IconButton(
                          tooltip: 'Close (Esc)',
                          icon: AppIcon(AppIcons.close, size: IconSize.md),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Previous (←)',
                          icon: AppIcon(AppIcons.chevronLeft, size: IconSize.lg),
                          onPressed: position > 0 ? () => setState(() => _position--) : null,
                        ),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: tokens.space.lg),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(tokens.geometry.radiusMd),
                              child: ColoredBox(
                                color: tokens.surface.raised,
                                child: LibraryFullImage(path: entry.path, zoomFit: _zoomFit),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next (→)',
                          icon: AppIcon(AppIcons.chevronRight, size: IconSize.lg),
                          onPressed: position < images.length - 1 ? () => setState(() => _position++) : null,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(bottom: tokens.space.lg),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('@${_idFromName(entry.name)}', style: theme.textTheme.titleMedium),
                        SizedBox(width: tokens.space.lg),
                        InkWell(
                          onTap: () => _openInstagram(entry),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'open on Instagram',
                                style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
                              ),
                              SizedBox(width: tokens.space.xs),
                              AppIcon(AppIcons.openExternal, size: IconSize.sm, color: tokens.content.secondary),
                            ],
                          ),
                        ),
                        SizedBox(width: tokens.space.lg),
                        IconButton(
                          tooltip: _zoomFit ? 'Actual size (Z)' : 'Zoom to fit (Z)',
                          icon: AppIcon(
                            _zoomFit ? AppIcons.expand : AppIcons.collapse,
                            size: IconSize.sm,
                            color: tokens.content.secondary,
                          ),
                          onPressed: () => setState(() => _zoomFit = !_zoomFit),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
