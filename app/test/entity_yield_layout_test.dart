import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/core/entity_yield_models.dart';
import 'package:ia_control_center/features/library/entity_yield_dialog.dart';
import 'package:ia_control_center/features/library/library_controller.dart';

/// Overflow is a paint-time error `flutter analyze` is blind to (D19's
/// precedent). The dialog is fixed at 460px wide (`entity_yield_dialog.dart`)
/// so the real risk is a long entity root in the title row squeezing the
/// "open on Instagram" button, and large counts/percentages/captions
/// widening the funnel's count+percentage row past what's left after the
/// bar's own padding. D81 dropped the scraped/followed_est stages (and
/// their fields) from the model entirely — see `entity_yield_models.dart`.
void main() {
  testWidgets('EntityYield dialog lays out without overflow: a 60-char root, huge counts, long captions', (
    tester,
  ) async {
    final longRoot = 'a_very_long_instagram_username_that_keeps_going_60c';
    final data = EntityYield(
      root: longRoot,
      url: 'https://www.instagram.com/$longRoot',
      type: 'PROFILE',
      access: 'PRIVATE',
      status: 'COMPLETED',
      addedOn: DateTime(2026, 7, 1),
      updatedOn: DateTime(2026, 7, 2),
      scanned: 123456,
      private: 98765,
      female: 54321,
      male: 44444,
    );

    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [entityYieldProvider.overrideWith((ref, root) async => data)],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showEntityYieldDialog(context, longRoot),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(longRoot), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('EntityYield dialog lays out without overflow: an all-zero funnel', (tester) async {
    const root = 'fresh';
    final data = EntityYield(
      root: root,
      url: 'https://www.instagram.com/fresh',
      type: 'PROFILE',
      access: 'UNDEF',
      status: 'QUEUED',
      addedOn: DateTime(2026, 8, 1),
      updatedOn: DateTime(2026, 8, 1),
      scanned: 0,
      private: 0,
      female: 0,
      male: 0,
    );

    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [entityYieldProvider.overrideWith((ref, r) async => data)],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showEntityYieldDialog(context, root),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });
}
