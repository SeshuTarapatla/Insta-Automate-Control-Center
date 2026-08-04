import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_snack_bar.dart';
import '../../core/entity_yield_models.dart';
import '../../core/file_opener.dart';
import '../../core/funnel_stage.dart';
import '../../core/theme/tokens.dart';
import '../../ui/feedback.dart';
import '../../ui/icons.dart';
import '../../ui/status.dart';
import 'library_controller.dart';

/// CP 5.4 — one entity across every stage at once. Opened from the Library
/// screen's toolbar breadcrumb once an entity root is selected.
Future<void> showEntityYieldDialog(BuildContext context, String root) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 600),
        child: Padding(padding: EdgeInsets.all(Theme.of(context).tokens.space.xl), child: _EntityYieldContent(root: root)),
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
    return async.stateView(
      onRetry: () => ref.invalidate(entityYieldProvider(root)),
      // Dialog shrink-wraps to its child's intrinsic size, so the loading/
      // error states (which have no intrinsic height of their own) need an
      // explicit one — the same defensive sizing the original spinner/error
      // `SizedBox`s had.
      skeleton: const SizedBox(height: 220),
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
    final tokens = theme.tokens;
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
                icon: AppIcon(AppIcons.openExternal, size: IconSize.sm),
                onPressed: () {
                  if (!FileOpener.openUrl(data.url) && context.mounted) {
                    AppSnackBar.show(context, 'Could not open ${data.url}', isError: true);
                  }
                },
              ),
            ],
          ),
          Wrap(
            spacing: tokens.space.xs,
            runSpacing: tokens.space.xs / 2,
            children: [
              StatusChip(kind: StatusKind.neutral, label: _titleCase(data.type), dense: true),
              StatusChip(kind: StatusKind.neutral, label: _titleCase(data.access), dense: true),
              StatusChip(kind: StatusKind.neutral, label: _titleCase(data.status), dense: true),
            ],
          ),
          SizedBox(height: tokens.space.xl),
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
          SizedBox(height: tokens.space.sm),
          Text(
            'Scraped/followed counts aren\'t shown here — no accurate per-entity '
            'source exists (see the Insights screen for real whole-library totals).',
            style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
          ),
        ],
      ),
    );
  }
}
