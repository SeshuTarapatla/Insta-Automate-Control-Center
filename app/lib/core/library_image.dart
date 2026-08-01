import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'agent_client.dart';

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
    final async = ref.watch(libraryThumbBytesProvider((path, width)));

    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: async.when(
        loading: () => const Center(
          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (_, _) => Center(
          child: Icon(Icons.broken_image_outlined, size: 20, color: theme.colorScheme.onSurfaceVariant),
        ),
        data: (bytes) => Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
      ),
    );
  }
}
