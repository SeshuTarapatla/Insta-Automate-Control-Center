import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/ui/feedback.dart';

import 'test_harness.dart';

void main() {
  testWidgets('LoadingView shows a spinner with no skeleton', (tester) async {
    await pumpUi(tester, const LoadingView());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('LoadingView(skeleton:) shows the skeleton, shimmering, not a spinner', (tester) async {
    await pumpUi(tester, const LoadingView(skeleton: SkeletonBox(width: 100)));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(SkeletonBox), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ErrorView renders the message and an optional retry action', (tester) async {
    var retried = false;
    await pumpUi(tester, ErrorView(message: 'boom', onRetry: () => retried = true));
    expect(find.text('boom'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retried, isTrue);
  });

  testWidgets('ErrorView with no onRetry has no retry button', (tester) async {
    await pumpUi(tester, const ErrorView(message: 'boom'));
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('EmptyView is not styled as an error', (tester) async {
    await pumpUi(tester, const EmptyView(icon: Icons.inbox, title: 'Nothing yet'));
    expect(find.text('Nothing yet'), findsOneWidget);
  });

  testWidgets('stateView renders loading/error/data and honours emptyWhen', (tester) async {
    const loading = AsyncValue<List<int>>.loading();
    await pumpUi(tester, loading.stateView(data: (rows) => Text('${rows.length}')));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    final error = AsyncValue<List<int>>.error('bad', StackTrace.empty);
    await pumpUi(tester, error.stateView(data: (rows) => Text('${rows.length}'), describeError: (e) => 'nope: $e'));
    expect(find.text('nope: bad'), findsOneWidget);

    const empty = AsyncValue<List<int>>.data([]);
    await pumpUi(
      tester,
      empty.stateView(
        data: (rows) => Text('${rows.length}'),
        emptyWhen: (rows) => rows.isEmpty,
        emptyView: const EmptyView(icon: Icons.inbox, title: 'Nothing here'),
      ),
    );
    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('0'), findsNothing);

    const full = AsyncValue<List<int>>.data([1, 2, 3]);
    await pumpUi(
      tester,
      full.stateView(
        data: (rows) => Text('${rows.length}'),
        emptyWhen: (rows) => rows.isEmpty,
        emptyView: const EmptyView(icon: Icons.inbox, title: 'Nothing here'),
      ),
    );
    expect(find.text('3'), findsOneWidget);
  });
}
