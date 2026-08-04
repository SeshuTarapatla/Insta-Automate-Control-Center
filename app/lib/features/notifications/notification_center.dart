import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent_image.dart';
import '../../core/file_opener.dart';
import '../../core/notification_models.dart';
import '../../core/notification_text.dart';
import '../../core/relative_time.dart';
import '../../core/theme/tokens.dart';
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
          child: const Icon(Icons.notifications_outlined, size: 18),
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
    final async = ref.watch(notificationControllerProvider);
    final muted = ref.watch(mutedTagsProvider);

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.surfaceContainerHigh,
      child: SizedBox(
        width: 380,
        height: 480,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
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
                    icon: const Icon(Icons.filter_list, size: 18),
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
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _TagFilterRow(notifications: async.value ?? const [], muted: muted),
              ),
            const Divider(height: 1),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text('Failed to load: $error')),
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

    if (tags.isEmpty) {
      return Text(
        'No tags yet.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
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
    final visible = notifications.where((n) => !notificationIsMuted(n, muted)).toList()
      ..sort((a, b) => b.seq.compareTo(a.seq));

    if (visible.isEmpty) {
      final reason = notifications.isEmpty ? 'No notifications yet.' : 'Every notification here is muted.';
      return Center(
        child: Text(reason, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: visible.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => NotificationTile(notification: visible[index]),
    );
  }
}

class NotificationTile extends ConsumerWidget {
  const NotificationTile({super.key, required this.notification});
  final AppNotification notification;

  static Color? _levelColor(AppTokens tokens, String level) => switch (level) {
    'error' => tokens.status.bad.fg,
    'warning' || 'warn' => tokens.status.warn.fg,
    'info' => tokens.status.info.fg,
    _ => null,
  };

  static const _levelIcons = {
    'error': Icons.error_outline,
    'warning': Icons.warning_amber_outlined,
    'warn': Icons.warning_amber_outlined,
    'info': Icons.info_outline,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final color = _levelColor(theme.tokens, notification.level) ?? theme.tokens.content.secondary;
    final icon = _levelIcons[notification.level] ?? Icons.circle_notifications_outlined;

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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
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
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        relativeTime(notification.ts),
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      if (url != null) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.open_in_new_rounded, size: 12, color: theme.colorScheme.primary.withValues(alpha: 0.7)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (notification.imageKey != null) ...[
              const SizedBox(width: 8),
              SizedBox(width: 40, height: 40, child: AgentImage(imageKey: notification.imageKey, width: 80)),
            ],
            if (!notification.read) ...[
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
