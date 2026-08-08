import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'agent_client.dart';
import 'theme/tokens.dart';

/// `GET /api/library/image/thumb?path=&w=` — the Library screen's sibling to
/// `agent_image.dart`'s `imageBytesProvider`, keyed by `IA_DIR`-relative path
/// rather than a flow event's content-hash key, since library images were
/// never part of an emitted event.
final libraryThumbBytesProvider = FutureProvider.family<Uint8List, (String path, int width)>((ref, params) async {
  final (path, width) = params;
  final dio = ref.read(agentClientProvider);
  final response = await dio.get<List<int>>(
    '/api/library/image/thumb',
    queryParameters: {'path': path, 'w': width},
    options: Options(responseType: ResponseType.bytes),
  );
  return Uint8List.fromList(response.data!);
});

/// `GET /api/library/image?path=` — the original, full-resolution file.
/// Review mode (V2.10) and the lightbox are the only callers; the grid always
/// uses [libraryThumbBytesProvider] instead.
final libraryImageBytesProvider = FutureProvider.family<Uint8List, String>((ref, path) async {
  final dio = ref.read(agentClientProvider);
  final response = await dio.get<List<int>>(
    '/api/library/image',
    queryParameters: {'path': path},
    options: Options(responseType: ResponseType.bytes),
  );
  return Uint8List.fromList(response.data!);
});

/// A single library thumbnail. `BoxFit.contain` rather than `cover` — D41
/// already found that cropping loses real content on this project's genuinely
/// mixed aspect ratios (1080×198 row crops next to 1080×2246 full pages);
/// letterboxing inside a uniform grid tile is the same tradeoff made there.
class LibraryThumbnail extends ConsumerWidget {
  const LibraryThumbnail({super.key, required this.path, required this.width});

  final String path;
  final int width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final async = ref.watch(libraryThumbBytesProvider((path, width)));

    return ColoredBox(
      color: tokens.surface.raised,
      child: async.when(
        loading: () => const Center(
          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        // A raw `Icon`, not `AppIcon` — see `agent_image.dart`'s identical
        // note on why `ui/` can't be reached from `core/`.
        error: (_, _) => Center(
          child: Icon(Icons.broken_image_outlined, size: tokens.space.iconMd, color: tokens.content.secondary),
        ),
        data: (bytes) => Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
      ),
    );
  }
}

/// The original-resolution image, for review mode and the lightbox — the
/// "you cannot actually read a 1080×2246 profile page at ~120px" problem
/// [SCREENS.md] §5b exists to fix. `zoomFit == false` renders at intrinsic
/// pixel size inside an [InteractiveViewer] so a large image can be panned;
/// `zoomFit == true` letterboxes it to whatever space is available, same
/// [BoxFit.contain] reasoning as [LibraryThumbnail].
class LibraryFullImage extends ConsumerWidget {
  const LibraryFullImage({super.key, required this.path, required this.zoomFit});

  final String path;
  final bool zoomFit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final async = ref.watch(libraryImageBytesProvider(path));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(
        child: Icon(Icons.broken_image_outlined, size: tokens.space.iconLg, color: tokens.content.secondary),
      ),
      data: (bytes) => zoomFit
          ? Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true)
          : InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(child: Image.memory(bytes, gaplessPlayback: true)),
            ),
    );
  }
}
