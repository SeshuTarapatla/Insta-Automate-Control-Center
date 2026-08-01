import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent_client.dart';
import '../../core/agent_ws.dart';
import '../../core/library_models.dart';

bool _touchesLibraryChanges(AgentEvent event) => event.channel == 'library.changes';

/// Which folder the grid is showing. Resetting the entity/selection when this
/// changes is `LibraryEntitiesController`/`LibraryImagesController`/
/// `LibrarySelectionNotifier`'s job (each watches it in `build()`), not this
/// notifier's — same split `SelectedServiceNotifier` uses.
class SelectedFolderNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? folder) => state = folder;

  void selectIfUnset(String folder) => state ??= folder;
}

final selectedFolderProvider = NotifierProvider<SelectedFolderNotifier, String?>(SelectedFolderNotifier.new);

class SelectedEntityNotifier extends Notifier<String?> {
  @override
  String? build() {
    // A folder change always invalidates whatever entity was selected in the
    // *previous* folder — rebuilding on that watch is what clears it.
    ref.watch(selectedFolderProvider);
    return null;
  }

  void select(String? entity) => state = entity;
}

final selectedEntityProvider = NotifierProvider<SelectedEntityNotifier, String?>(SelectedEntityNotifier.new);

/// The seven folders and their cached counts. `library.changes` is cheap
/// enough (measured 15ms over the real 7,655-file `IA_DIR` in
/// `check_library.py`) that a full refetch on every touch is simpler than
/// patching the aggregate in from a per-`(folder, root)` delta.
class LibraryFoldersController extends AsyncNotifier<List<LibraryFolderInfo>> {
  @override
  Future<List<LibraryFolderInfo>> build() async {
    ref.listen<AsyncValue<AgentEvent>>(agentEventsProvider, (previous, next) {
      next.whenData((event) {
        if (_touchesLibraryChanges(event)) refresh();
      });
    });
    return _fetch();
  }

  Future<List<LibraryFolderInfo>> _fetch() async {
    final dio = ref.read(agentClientProvider);
    final response = await dio.get('/api/library/folders');
    final folders = (response.data as List)
        .map((e) => LibraryFolderInfo.fromJson(e as Map<String, dynamic>))
        .toList();
    if (folders.isNotEmpty) {
      ref.read(selectedFolderProvider.notifier).selectIfUnset(folders.first.name);
    }
    return folders;
  }

  Future<void> refresh() async => state = AsyncValue.data(await _fetch());
}

final libraryFoldersControllerProvider = AsyncNotifierProvider<LibraryFoldersController, List<LibraryFolderInfo>>(
  LibraryFoldersController.new,
);

/// Entities inside whichever folder is selected — empty (not fetched) for a
/// flat folder, since `GET /api/library/entities` 400s on those.
class LibraryEntitiesController extends AsyncNotifier<List<LibraryEntityInfo>> {
  @override
  Future<List<LibraryEntityInfo>> build() async {
    final folder = ref.watch(selectedFolderProvider);
    final folders = await ref.watch(libraryFoldersControllerProvider.future);
    ref.listen<AsyncValue<AgentEvent>>(agentEventsProvider, (previous, next) {
      next.whenData((event) {
        if (_touchesLibraryChanges(event)) refresh();
      });
    });

    if (folder == null) return const [];
    final info = folders.where((f) => f.name == folder).firstOrNull;
    if (info == null || info.flat) return const [];
    return _fetch(folder);
  }

  Future<List<LibraryEntityInfo>> _fetch(String folder) async {
    final dio = ref.read(agentClientProvider);
    final response = await dio.get('/api/library/entities', queryParameters: {'folder': folder});
    return (response.data as List).map((e) => LibraryEntityInfo.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> refresh() async {
    final folder = ref.read(selectedFolderProvider);
    if (folder == null) return;
    final folders = ref.read(libraryFoldersControllerProvider).value ?? const [];
    final info = folders.where((f) => f.name == folder).firstOrNull;
    if (info == null || info.flat) return;
    state = AsyncValue.data(await _fetch(folder));
  }
}

final libraryEntitiesControllerProvider = AsyncNotifierProvider<LibraryEntitiesController, List<LibraryEntityInfo>>(
  LibraryEntitiesController.new,
);

class LibraryImagesState {
  const LibraryImagesState({
    required this.images,
    required this.total,
    required this.hasMore,
    required this.loadingMore,
  });

  final List<LibraryImageEntry> images;
  final int total;
  final bool hasMore;
  final bool loadingMore;

  LibraryImagesState copyWith({List<LibraryImageEntry>? images, bool? hasMore, bool? loadingMore}) =>
      LibraryImagesState(
        images: images ?? this.images,
        total: total,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
      );

  static const empty = LibraryImagesState(images: [], total: 0, hasMore: false, loadingMore: false);
}

/// One `(folder, entity)` view at a time — the whole screen only ever shows
/// one grid, so this rebuilds on selection change rather than being a family
/// provider keyed by every folder/entity ever visited (`selectedServiceProvider`'s
/// "one live selection, not one provider per item" precedent).
class LibraryImagesController extends AsyncNotifier<LibraryImagesState> {
  static const _pageSize = 200;

  @override
  Future<LibraryImagesState> build() async {
    final folder = ref.watch(selectedFolderProvider);
    final entity = ref.watch(selectedEntityProvider);
    if (folder == null) return LibraryImagesState.empty;
    return _fetchPage(folder, entity, offset: 0);
  }

  Future<LibraryImagesState> _fetchPage(String folder, String? entity, {required int offset}) async {
    final dio = ref.read(agentClientProvider);
    final response = await dio.get(
      '/api/library/images',
      queryParameters: {'folder': folder, 'entity': ?entity, 'offset': offset, 'limit': _pageSize},
    );
    final page = LibraryImagesPage.fromJson(response.data as Map<String, dynamic>);
    return LibraryImagesState(
      images: page.images,
      total: page.total,
      hasMore: offset + page.images.length < page.total,
      loadingMore: false,
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    final folder = ref.read(selectedFolderProvider);
    if (current == null || !current.hasMore || current.loadingMore || folder == null) return;
    final entity = ref.read(selectedEntityProvider);

    state = AsyncValue.data(current.copyWith(loadingMore: true));
    final next = await _fetchPage(folder, entity, offset: current.images.length);
    state = AsyncValue.data(
      current.copyWith(images: [...current.images, ...next.images], hasMore: next.hasMore, loadingMore: false),
    );
  }

  /// Fetches every remaining page so "select all" really means all — needed
  /// before `ctrl+A`, since the grid otherwise only holds what's been
  /// scrolled into view so far.
  Future<List<String>> loadAllNames() async {
    while (state.value?.hasMore ?? false) {
      await loadMore();
    }
    return state.value?.images.map((e) => e.name).toList() ?? const [];
  }

  Future<void> reload() async {
    final folder = ref.read(selectedFolderProvider);
    if (folder == null) {
      state = const AsyncValue.data(LibraryImagesState.empty);
      return;
    }
    final entity = ref.read(selectedEntityProvider);
    state = await AsyncValue.guard(() => _fetchPage(folder, entity, offset: 0));
  }

  Future<ApplyResult> apply(List<String> selected) async {
    final folder = ref.read(selectedFolderProvider);
    if (folder == null) throw StateError('no folder selected');
    final entity = ref.read(selectedEntityProvider);
    final dio = ref.read(agentClientProvider);
    final response = await dio.post(
      '/api/library/apply',
      data: {'folder': folder, 'entity': entity, 'selected': selected},
    );
    await reload();
    return ApplyResult.fromJson(response.data as Map<String, dynamic>);
  }

  Future<DeleteResult> delete(List<String> paths) async {
    final dio = ref.read(agentClientProvider);
    final response = await dio.post('/api/library/delete', data: {'paths': paths});
    await reload();
    return DeleteResult.fromJson(response.data as Map<String, dynamic>);
  }
}

final libraryImagesControllerProvider = AsyncNotifierProvider<LibraryImagesController, LibraryImagesState>(
  LibraryImagesController.new,
);

/// Per-folder "apply" promotion targets (CP 5.2's `library/settings.py`).
class MoveTargetsController extends AsyncNotifier<Map<String, String>> {
  @override
  Future<Map<String, String>> build() async {
    final dio = ref.read(agentClientProvider);
    final response = await dio.get('/api/library/move-targets');
    return Map<String, String>.from(response.data as Map);
  }

  Future<void> setTarget(String folder, String target) async {
    final dio = ref.read(agentClientProvider);
    final response = await dio.patch('/api/library/move-targets/$folder', data: {'target': target});
    state = AsyncValue.data(Map<String, String>.from(response.data as Map));
  }
}

final moveTargetsControllerProvider = AsyncNotifierProvider<MoveTargetsController, Map<String, String>>(
  MoveTargetsController.new,
);

enum LibraryZoom {
  small(110),
  medium(170),
  large(260);

  const LibraryZoom(this.tileWidth);
  final double tileWidth;
}

class LibraryZoomNotifier extends Notifier<LibraryZoom> {
  @override
  LibraryZoom build() => LibraryZoom.medium;

  void set(LibraryZoom zoom) => state = zoom;
}

final libraryZoomProvider = NotifierProvider<LibraryZoomNotifier, LibraryZoom>(LibraryZoomNotifier.new);

class LibrarySelectionState {
  const LibrarySelectionState({this.selected = const {}, this.anchorIndex, this.focusedIndex});

  final Set<String> selected;
  final int? anchorIndex;
  final int? focusedIndex;

  LibrarySelectionState copyWith({
    Set<String>? selected,
    int? anchorIndex,
    int? focusedIndex,
    bool clearAnchor = false,
  }) => LibrarySelectionState(
    selected: selected ?? this.selected,
    anchorIndex: clearAnchor ? null : (anchorIndex ?? this.anchorIndex),
    focusedIndex: focusedIndex ?? this.focusedIndex,
  );
}

/// Keyed implicitly by whichever `(folder, entity)` is selected — watching
/// both means a fresh, empty selection every time the view changes, the same
/// way `LibraryImagesController` gets a fresh page.
class LibrarySelectionNotifier extends Notifier<LibrarySelectionState> {
  @override
  LibrarySelectionState build() {
    ref.watch(selectedFolderProvider);
    ref.watch(selectedEntityProvider);
    return const LibrarySelectionState();
  }

  /// A plain click or a keyboard Space both call this — toggling never clears
  /// the rest of the selection, so clicking (or space-ing) several images in
  /// turn builds up a batch. The touched index becomes the new range anchor,
  /// so a following Shift+click/arrow extends from *here*, not from whatever
  /// was anchored before.
  void toggle(int index, String name) {
    final next = {...state.selected};
    if (!next.remove(name)) next.add(name);
    state = state.copyWith(selected: next, anchorIndex: index, focusedIndex: index);
  }

  void selectRange(int toIndex, List<LibraryImageEntry> images) {
    final anchor = state.anchorIndex ?? toIndex;
    final lo = anchor < toIndex ? anchor : toIndex;
    final hi = anchor < toIndex ? toIndex : anchor;
    final names = {for (var i = lo; i <= hi && i < images.length; i++) images[i].name};
    state = state.copyWith(selected: names, focusedIndex: toIndex);
  }

  void selectAll(List<String> names) => state = state.copyWith(selected: names.toSet());

  void clear() => state = const LibrarySelectionState();

  void moveFocus(int index) => state = state.copyWith(focusedIndex: index);
}

final librarySelectionProvider = NotifierProvider<LibrarySelectionNotifier, LibrarySelectionState>(
  LibrarySelectionNotifier.new,
);

/// The agent's `detail` sentence when present, matching `describeAgentError`'s
/// convention in `services_controller.dart`.
String describeLibraryError(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) return data['detail'] as String;
    return error.message ?? 'request failed';
  }
  return error.toString();
}
