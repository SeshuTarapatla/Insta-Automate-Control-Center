import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_snack_bar.dart';
import '../../core/entity_yield_models.dart';
import '../../core/file_opener.dart';
import 'library_controller.dart';

/// CP 5.4 — one entity across every stage at once. Opened from the Library
/// screen's toolbar breadcrumb once an entity root is selected.
Future<void> showEntityYieldDialog(BuildContext context, String root) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 600),
        child: Padding(padding: const EdgeInsets.all(20), child: _EntityYieldContent(root: root)),
      ),
    ),
  );
}

class _EntityYieldContent extends ConsumerWidget {
  const _EntityYieldContent({required this.root});

  final String root;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(entityYieldProvider(root));
    return async.when(
      loading: () => const SizedBox(height: 220, child: Center(child: CircularProgressIndicator())),
      error: (error, _) => SizedBox(height: 120, child: Center(child: Text('$error'))),
      data: (data) => _EntityYieldBody(data: data),
    );
  }
}

String _titleCase(String value) => value.isEmpty ? value : '${value[0]}${value.substring(1).toLowerCase()}';

class _EntityYieldBody extends StatelessWidget {
  const _EntityYieldBody({required this.data});

  final EntityYield data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // scanned is always the widest stage — every later stage is a subset of
    // an earlier one, except followedEst, which is an approximation clamped
    // at 0 but not at scraped, so it also gets clamped against this max.
    final maxCount = data.scanned == 0 ? 1 : data.scanned;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(data.root, style: theme.textTheme.titleLarge, overflow: TextOverflow.ellipsis),
              ),
              IconButton(
                tooltip: 'Open on Instagram',
                icon: const Icon(Icons.open_in_new, size: 18),
                onPressed: () {
                  if (!FileOpener.openUrl(data.url) && context.mounted) {
                    AppSnackBar.show(context, 'Could not open ${data.url}', isError: true);
                  }
                },
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              Chip(label: Text(_titleCase(data.type)), visualDensity: VisualDensity.compact),
              Chip(label: Text(_titleCase(data.access)), visualDensity: VisualDensity.compact),
              Chip(label: Text(_titleCase(data.status)), visualDensity: VisualDensity.compact),
            ],
          ),
          const SizedBox(height: 20),
          _FunnelStage(label: 'Scanned', count: data.scanned, maxCount: maxCount),
          _FunnelStage(label: 'Private', count: data.private, maxCount: maxCount),
          _FunnelStage(
            label: 'Female',
            count: data.female,
            maxCount: maxCount,
            caption: data.male > 0
                ? 'of ${data.private} private — ${data.male} classified male instead'
                : null,
          ),
          _FunnelStage(label: 'Scraped', count: data.scraped, maxCount: maxCount),
          _FunnelStage(
            label: 'Followed (est.)',
            count: data.followedEst,
            maxCount: maxCount,
            caption:
                '≈ scraped, minus ${data.inScrapedFolder} still awaiting review and '
                '${data.inFollowQueuedFolder} still queued to follow',
          ),
        ],
      ),
    );
  }
}

/// One bar: a fixed-height track plus a fill proportional to `count/maxCount`
/// — the same hue throughout (this is one metric across stages, not several
/// series, so there is nothing for color to distinguish), magnitude carried
/// entirely by length. A direct count + percentage label sits above each bar
/// rather than inside it, since several of these bars are too thin at the
/// tail end of the funnel to hold text.
class _FunnelStage extends StatelessWidget {
  const _FunnelStage({required this.label, required this.count, required this.maxCount, this.caption});

  final String label;
  final int count;
  final int maxCount;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fraction = maxCount == 0 ? 0.0 : (count / maxCount).clamp(0.0, 1.0);
    final pct = maxCount == 0 ? 0.0 : (count / maxCount * 100);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              Text('$count', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Text(
                '(${pct.toStringAsFixed(0)}%)',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Container(height: 10, width: constraints.maxWidth, color: scheme.surfaceContainerHighest),
                  Container(height: 10, width: constraints.maxWidth * fraction, color: scheme.primary),
                ],
              ),
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 3),
            Text(caption!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}
