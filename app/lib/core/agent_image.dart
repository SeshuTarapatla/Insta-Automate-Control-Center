import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'agent_client.dart';

/// `GET /api/images/{key}` (original) or `.../thumb?w=` — fetched through
/// `dio` so the bearer token interceptor applies, since a plain
/// `Image.network` has no way to attach one. Riverpod's own cache means a key
/// already fetched at a given width is never re-requested.
final imageBytesProvider = FutureProvider.family<Uint8List, (String key, int? width)>((ref, params) async {
  final (key, width) = params;
  final dio = ref.read(agentClientProvider);
  final path = width == null ? '/api/images/$key' : '/api/images/$key/thumb?w=$width';
  final response = await dio.get<List<int>>(path, options: Options(responseType: ResponseType.bytes));
  return Uint8List.fromList(response.data!);
});

/// One cached flow-event image, or a placeholder explaining why there is
/// none — `imageKey` is null whenever the agent lost the race to read the
/// source file before the flow deleted it (D31), which is expected often
/// enough that a blank box would read as broken rather than as normal.
class AgentImage extends ConsumerWidget {
  const AgentImage({super.key, required this.imageKey, this.width, this.aspectRatio, this.fit = BoxFit.contain});

  final String? imageKey;
  final int? width;
  final double? aspectRatio;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final key = imageKey;
    Widget child;
    if (key == null) {
      child = _placeholder(theme, Icons.image_not_supported_outlined, 'image unavailable');
    } else {
      final async = ref.watch(imageBytesProvider((key, width)));
      child = async.when(
        loading: () => const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
        error: (_, _) => _placeholder(theme, Icons.broken_image_outlined, 'failed to load'),
        data: (bytes) => Image.memory(bytes, fit: fit, gaplessPlayback: true),
      );
    }

    final framed = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: ColoredBox(color: theme.colorScheme.surfaceContainerHighest, child: child),
    );

    return aspectRatio == null ? framed : AspectRatio(aspectRatio: aspectRatio!, child: framed);
  }

  // FittedBox rather than a fixed icon+text layout: some callers show this at
  // a wide aspect ratio (the 1080:198 row-crop shape) sized narrow enough
  // that icon + spacing + label no longer fits its height — a real overflow
  // caught by live_layout_test.dart, not a hypothetical one.
  Widget _placeholder(ThemeData theme, IconData icon, String label) => Center(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 4),
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    ),
  );
}
