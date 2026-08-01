import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/core/notification_models.dart';
import 'package:ia_control_center/features/notifications/notification_center.dart';
import 'package:ia_control_center/features/notifications/notification_controller.dart';

/// Overflow is a paint-time error `flutter analyze` is blind to (D19's
/// precedent). The real risk here is an unbounded `msg` string (pipeline
/// call sites build these from real usernames/reasons, same shape as
/// `flows_layout_test.dart`'s long reason strings) inside the panel's fixed
/// 380px width, plus a long tag name in the filter row's `Wrap`.
class _FakeNotificationController extends NotificationController {
  _FakeNotificationController(this._notifications);
  final List<AppNotification> _notifications;

  @override
  Future<List<AppNotification>> build() async => _notifications;
}

class _FakeMutedTagsController extends MutedTagsController {
  _FakeMutedTagsController(this._muted);
  final Set<String> _muted;

  @override
  Future<Set<String>> build() async => _muted;
}

AppNotification _notification({
  required String id,
  required int seq,
  required String msg,
  List<String> tags = const [],
  bool read = false,
  String level = 'info',
}) => AppNotification(
  id: id,
  seq: seq,
  ts: DateTime(2026, 8, 2, 12, 0),
  msg: msg,
  imageKey: null,
  level: level,
  tags: tags,
  dedupe: null,
  transient: false,
  read: read,
);

void main() {
  testWidgets('Notification panel lays out without overflow: a long unbroken message and a long tag name', (
    tester,
  ) async {
    final longMessage = 'x' * 400;
    final longTag = 'a_very_long_tag_name_for_a_notification_category';

    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationControllerProvider.overrideWith(
            () => _FakeNotificationController([
              _notification(id: '1', seq: 1, msg: longMessage, tags: [longTag]),
              _notification(id: '2', seq: 2, msg: 'short', tags: const ['follow', 'limit'], read: true),
            ]),
          ),
          mutedTagsControllerProvider.overrideWith(() => _FakeMutedTagsController(const {})),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
          home: const Scaffold(body: Align(alignment: Alignment.topRight, child: NotificationCenter())),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // `warnIfMissed: false` throughout — `CompositedTransformTarget`/
    // `Follower`'s global position resolves at paint/composite time, which
    // flutter_test's hit-test-based tap warning doesn't always account for
    // right after an overlay entry is inserted; the tap itself still reaches
    // the real button (the FilterChip assertion below confirms the row
    // actually opened, so this isn't masking a real mis-tap).
    await tester.tap(find.byIcon(Icons.notifications_outlined), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.filter_list), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(FilterChip), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Notification panel: the all-muted empty state renders without overflow', (tester) async {
    tester.view.physicalSize = const Size(1024, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationControllerProvider.overrideWith(
            () => _FakeNotificationController([
              _notification(id: '1', seq: 1, msg: 'muted one', tags: const ['muted-tag']),
            ]),
          ),
          mutedTagsControllerProvider.overrideWith(() => _FakeMutedTagsController(const {'muted-tag'})),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
          home: const Scaffold(body: Align(alignment: Alignment.topRight, child: NotificationCenter())),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.notifications_outlined), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Every notification here is muted.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
