import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/core/insights_models.dart';
import 'package:ia_control_center/features/insights/insights_controller.dart';
import 'package:ia_control_center/features/insights/insights_page.dart';

/// Overflow is a paint-time error `flutter analyze` is blind to (D19's
/// precedent, every UI checkpoint since has added one of these). CP 7.2's
/// three tabs are each exercised directly (made public for exactly this,
/// same as `DependencyRow`) at the app's real 1024x700 floor, since that is
/// where every prior overflow in this project actually reproduced.
EntityRanking _row(String root, {int scanned = 10, int private = 6, int female = 3, int male = 2}) => EntityRanking(
  root: root,
  url: 'https://www.instagram.com/$root',
  type: 'PROFILE',
  access: 'PRIVATE',
  status: 'COMPLETED',
  scanned: scanned,
  private: private,
  female: female,
  male: male,
);

void main() {
  testWidgets('FunnelTab lays out without overflow: huge counts and a long male-comparison caption', (tester) async {
    final summary = FunnelSummary(
      entities: 284,
      scanned: 123456,
      private: 98765,
      female: 54321,
      male: 44444,
      scraped: 12345,
      followed: 1234,
    );

    tester.view.physicalSize = const Size(1024, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [funnelSummaryProvider.overrideWith((ref) async => summary)],
        child: const MaterialApp(home: Scaffold(body: FunnelTab())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('284 entities'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FunnelTab lays out without overflow: an all-zero summary', (tester) async {
    const summary = FunnelSummary(entities: 0, scanned: 0, private: 0, female: 0, male: 0, scraped: 0, followed: 0);

    tester.view.physicalSize = const Size(1024, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [funnelSummaryProvider.overrideWith((ref) async => summary)],
        child: const MaterialApp(home: Scaffold(body: FunnelTab())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });

  testWidgets('RankingTab lays out without overflow: a 60-char root, huge counts, and many rows at the narrow floor', (
    tester,
  ) async {
    final rows = [
      _row('a_very_long_instagram_username_that_keeps_going_60c', scanned: 999999, private: 888888, female: 777777, male: 111),
      for (var i = 0; i < 15; i++) _row('entity_$i', scanned: i * 3),
    ];

    tester.view.physicalSize = const Size(1024, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [entityRankingProvider.overrideWith((ref) async => rows)],
        child: const MaterialApp(home: Scaffold(body: RankingTab())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);

    // Sorting and filtering both drive setState — exercise both to make sure
    // neither leaves the table in a state that overflows.
    await tester.enterText(find.byType(TextField), 'entity_1');
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Scanned'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('RankingTab: no entity has any activity yet shows the empty explanation', (tester) async {
    tester.view.physicalSize = const Size(1024, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [entityRankingProvider.overrideWith((ref) async => const [])],
        child: const MaterialApp(home: Scaffold(body: RankingTab())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No entity has any scan or scrape activity yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('BurndownTab lays out without overflow: 90 days of history, all five cards, at the narrow floor', (
    tester,
  ) async {
    final days = [
      for (var i = 0; i < 90; i++)
        BurndownDay(
          date: '2026-${(5 + i ~/ 30).toString().padLeft(2, '0')}-${(i % 28 + 1).toString().padLeft(2, '0')}',
          values: {'profiles': i % 12, 'reels': i % 31, 'posts': i % 5, 'scraped': i * 3, 'processed': i * 4, 'followed': i},
        ),
    ];
    final burndown = Burndown(
      days: 90,
      limits: const {'profiles': 10, 'reels': 30, 'posts': 30, 'scrape': 300, 'follow': 60},
      scan: days,
      scrape: days,
      follow: days,
    );

    tester.view.physicalSize = const Size(1024, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [burndownProvider.overrideWith((ref) async => burndown)],
        child: const MaterialApp(home: Scaffold(body: BurndownTab())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Scan — profiles'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('BurndownTab lays out without overflow: no history yet and no cap', (tester) async {
    const burndown = Burndown(
      days: 30,
      limits: {'profiles': null, 'reels': null, 'posts': null, 'scrape': null, 'follow': null},
      scan: [],
      scrape: [],
      follow: [],
    );

    tester.view.physicalSize = const Size(1024, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [burndownProvider.overrideWith((ref) async => burndown)],
        child: const MaterialApp(home: Scaffold(body: BurndownTab())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No history yet'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
