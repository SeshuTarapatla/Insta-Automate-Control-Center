import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/agent_image.dart';
import '../../core/file_opener.dart';
import '../../core/notification_models.dart';
import '../../core/notification_text.dart';
import '../../core/relative_time.dart';
import '../../core/theme/tokens.dart';
import '../../ui/feedback.dart';
import '../../ui/icons.dart';
import '../../ui/status.dart';
import 'notification_controller.dart';

/// The bell icon in the title bar (D54 — reachable from every screen rather
/// than a nav destination of its own) plus the dropdown panel it opens.
/// `Overlay`/`CompositedTransformFollower` rather than `showDialog`, since
/// this needs to feel anchored to the bell, not modal over the whole window.
class NotificationCenter extends ConsumerStatefulWidget {
  const NotificationCenter({super.key});

  @override
  ConsumerState<NotificationCenter> createState() => _NotificationCenterState();
}

class _NotificationCenterState extends ConsumerState<NotificationCenter> {
  final _link = LayerLink();
  OverlayEntry? _entry;

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  void _toggle() => _entry == null ? _open() : _close();

  void _open() {
    final overlay = Overlay.of(context);
    _entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _close)),
          CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 8),
            child: _NotificationPanel(onClose: _close),
          ),
        ],
      ),
    );
    overlay.insert(_entry!);
  }

  void _close() {
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadNotificationCountProvider);
    return CompositedTransformTarget(
      link: _link,
      child: IconButton(
        tooltip: 'Notifications',
        onPressed: _toggle,
        icon: Badge(
          label: Text('$unread'),
          isLabelVisible: unread > 0,
          child: AppIcon(AppIcons.notification, size: IconSize.sm),
        ),
      ),
    );
  }
}

class _NotificationPanel extends ConsumerStatefulWidget {
  const _NotificationPanel({required this.onClose});
  final VoidCallback onClose;

  @override
  ConsumerState<_NotificationPanel> createState() => _NotificationPanelState();
}

class _NotificationPanelState extends ConsumerState<_NotificationPanel> {
  bool _showFilters = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final async = ref.watch(notificationControllerProvider);
    final muted = ref.watch(mutedTagsProvider);

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(tokens.geometry.radiusMd),
      color: tokens.surface.raised,
      child: SizedBox(
        width: 380,
        height: 480,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(tokens.space.md, tokens.space.sm, tokens.space.xs, tokens.space.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Notifications',
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Filter by tag',
                    visualDensity: VisualDensity.compact,
                    icon: AppIcon(AppIcons.filter, size: IconSize.sm),
                    onPressed: () => setState(() => _showFilters = !_showFilters),
                  ),
                  TextButton(
                    onPressed: () => ref.read(notificationControllerProvider.notifier).markAllRead(),
                    child: const Text('Mark all read'),
                  ),
                ],
              ),
            ),
            if (_showFilters)
              Padding(
                padding: EdgeInsets.fromLTRB(tokens.space.md, 0, tokens.space.md, tokens.space.xs),
                child: _TagFilterRow(notifications: async.value ?? const [], muted: muted),
              ),
            const Divider(height: 1),
            Expanded(
              child: async.stateView(
                describeError: (error) => 'Failed to load: $error',
                onRetry: () => ref.invalidate(notificationControllerProvider),
                data: (notifications) => _NotificationList(notifications: notifications, muted: muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagFilterRow extends ConsumerWidget {
  const _TagFilterRow({required this.notifications, required this.muted});

  final List<AppNotification> notifications;
  final Set<String> muted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = {for (final n in notifications) ...n.tags, ...muted}.toList()..sort();

    final tokens = Theme.of(context).tokens;

    if (tags.isEmpty) {
      return Text(
        'No tags yet.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
      );
    }

    return Wrap(
      spacing: tokens.space.xs,
      runSpacing: tokens.space.xs,
      children: [
        for (final tag in tags)
          FilterChip(
            label: Text(tag),
            visualDensity: VisualDensity.compact,
            selected: !muted.contains(tag),
            onSelected: (_) => ref.read(mutedTagsControllerProvider.notifier).toggle(tag),
          ),
      ],
    );
  }
}

class _NotificationList extends ConsumerWidget {
  const _NotificationList({required this.notifications, required this.muted});

  final List<AppNotification> notifications;
  final Set<String> muted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final visible = notifications.where((n) => !notificationIsMuted(n, muted)).toList()
      ..sort((a, b) => b.seq.compareTo(a.seq));

    if (visible.isEmpty) {
      final reason = notifications.isEmpty ? 'No notifications yet.' : 'Every notification here is muted.';
      return Center(
        child: Text(reason, style: theme.textTheme.bodyMedium?.copyWith(color: tokens.content.secondary)),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.symmetric(vertical: tokens.space.xs),
      itemCount: visible.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => NotificationTile(notification: visible[index]),
    );
  }
}

class NotificationTile extends ConsumerWidget {
  const NotificationTile({super.key, required this.notification});
  final AppNotification notification;

  static StatusKind _levelKind(String level) => switch (level) {
    'error' => StatusKind.bad,
    'warning' || 'warn' => StatusKind.warn,
    'info' => StatusKind.info,
    _ => StatusKind.neutral,
  };

  static PhosphorIconData Function(PhosphorIconsStyle) _levelGlyph(String level) => switch (level) {
    'error' => AppIcons.error,
    'warning' || 'warn' => AppIcons.warning,
    'info' => AppIcons.info,
    _ => AppIcons.notification,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final color = _levelKind(notification.level).fg(tokens);
    final glyph = _levelGlyph(notification.level);

    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: notification.read ? FontWeight.normal : FontWeight.w600,
    );
    final url = notification.url;

    return InkWell(
      onTap: () {
        if (!notification.read) {
          ref.read(notificationControllerProvider.notifier).markRead(notification.id);
        }
        if (url != null) FileOpener.openUrl(url);
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: tokens.space.md, vertical: tokens.space.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIcon(glyph, size: IconSize.sm, color: color),
            SizedBox(width: tokens.space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stripNotificationMarkdown(notification.msg),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: bodyStyle,
                  ),
                  SizedBox(height: tokens.space.xs),
                  Row(
                    children: [
                      Text(
                        relativeTime(notification.ts),
                        style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
                      ),
                      if (url != null) ...[
                        SizedBox(width: tokens.space.xs),
                        AppIcon(AppIcons.openExternal, size: IconSize.sm, color: theme.colorScheme.primary.withValues(alpha: 0.7)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (notification.imageKey != null) ...[
              SizedBox(width: tokens.space.xs),
              SizedBox(width: 40, height: 40, child: AgentImage(imageKey: notification.imageKey, width: 80)),
            ],
            if (!notification.read) ...[
              SizedBox(width: tokens.space.xs),
              Container(
                width: 8,
                height: 8,
                margin: EdgeInsets.only(top: tokens.space.xs),
                decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
