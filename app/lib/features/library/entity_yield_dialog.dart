import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_snack_bar.dart';
import '../../core/entity_yield_models.dart';
import '../../core/file_opener.dart';
import '../../core/funnel_stage.dart';
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
    // scanned is always the widest stage — every later stage is a subset of it.
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
          FunnelStage(label: 'Scanned', count: data.scanned, maxCount: maxCount),
          FunnelStage(label: 'Private', count: data.private, maxCount: maxCount),
          FunnelStage(
            label: 'Female',
            count: data.female,
            maxCount: maxCount,
            caption: data.male > 0
                ? 'of ${data.private} private — ${data.male} classified male instead'
                : null,
          ),
          const SizedBox(height: 8),
          Text(
            'Scraped/followed counts aren\'t shown here — no accurate per-entity '
            'source exists (see the Insights screen for real whole-library totals).',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
