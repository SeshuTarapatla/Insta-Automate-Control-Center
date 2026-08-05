import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/feedback.dart';
import '../notifications/notification_center.dart';
import '../notifications/notification_controller.dart';

/// The last few notifications, at a glance — same `NotificationTile` the
/// bell panel uses (made public for this, D77's precedent for reusing a
/// once-private widget rather than duplicating it), just without the mute/
/// filter controls, which stay the bell panel's job.
class RecentNotificationsCard extends ConsumerWidget {
  const RecentNotificationsCard({super.key, this.maxShown = 5});

  final int maxShown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationControllerProvider);

    return async.stateView(
      describeError: (error) => 'Failed to load: $error',
      data: (notifications) {
        if (notifications.isEmpty) {
          return const EmptyView(icon: Icons.notifications_none, title: 'No notifications yet.');
        }
        final recent = [...notifications]..sort((a, b) => b.seq.compareTo(a.seq));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final notification in recent.take(maxShown)) NotificationTile(notification: notification),
          ],
        );
      },
    );
  }
}
