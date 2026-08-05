import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:ia_control_center/core/notification_models.dart';
import 'package:ia_control_center/features/notifications/notification_center.dart';
import 'package:ia_control_center/features/notifications/notification_controller.dart';
import 'package:ia_control_center/ui/icons.dart';

// AppIcon resolves through Phosphor now, not Material `Icons.*` — every
// finder below needs the exact glyph+weight `AppIcon` renders. The bare
// `ThemeData(...)` these tests build has no `AppTokens` registered, so
// `AppTokensX.tokens` falls back to `buildClassicTokens()` (D99), whose
// `typography.iconWeight` is `PhosphorIconsStyle.regular` — matched explicitly
// here rather than assumed.
const _iconWeight = PhosphorIconsStyle.regular;

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
  String? url,
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
  url: url,
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
    await tester.tap(find.byIcon(AppIcons.notification(_iconWeight)), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(AppIcons.filter(_iconWeight)), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(FilterChip), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Notification panel: a per-profile notification with markdown + url renders without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final longUsername = 'a_very_long_instagram_username_for_testing_wrap_1234567890';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationControllerProvider.overrideWith(
            () => _FakeNotificationController([
              _notification(
                id: '1',
                seq: 1,
                msg: '**[@$longUsername](https://www.instagram.com/$longUsername)** is Followed by someone_else',
                tags: const ['follow'],
                level: 'warn',
                url: 'https://www.instagram.com/$longUsername',
              ),
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

    await tester.tap(find.byIcon(AppIcons.notification(_iconWeight)), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The raw markdown syntax must not appear literally — it should have
    // been formatted (bold, link syntax stripped) rather than shown as-is.
    expect(find.textContaining('**['), findsNothing);
    expect(find.textContaining('](https'), findsNothing);
    expect(find.byIcon(AppIcons.openExternal(_iconWeight)), findsOneWidget);
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

    await tester.tap(find.byIcon(AppIcons.notification(_iconWeight)), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Every notification here is muted.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
