import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ia_control_center/ui/layout.dart';

import 'test_harness.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ResizableSplit', () {
    Finder handle(String persistKey) => find.byKey(ValueKey('resizable_split_handle:$persistKey'));
    Finder firstPane() => find.byKey(const ValueKey('first-pane'));

    Widget split(String persistKey) => SizedBox(
      width: 600,
      height: 400,
      child: ResizableSplit(
        first: const ColoredBox(key: ValueKey('first-pane'), color: Colors.red, child: SizedBox.expand()),
        second: const ColoredBox(color: Colors.blue, child: SizedBox.expand()),
        initialFirstSize: 200,
        minFirst: 100,
        minSecond: 100,
        persistKey: persistKey,
      ),
    );

    testWidgets('drag resizes the first pane and clamps at minFirst', (tester) async {
      await pumpUi(tester, split('test.resize.clamp'));
      expect(tester.getSize(firstPane()).width, 200);

      // Drag far past minFirst — the pane must clamp, never go below it.
      await tester.drag(handle('test.resize.clamp'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      final width = tester.getSize(firstPane()).width;
      expect(width, greaterThanOrEqualTo(100));
      expect(width, lessThan(200));
    });

    testWidgets('a real drag persists the new size, restored on the next mount', (tester) async {
      await pumpUi(tester, split('test.resize.persist'));
      await tester.drag(handle('test.resize.persist'), const Offset(80, 0));
      await tester.pumpAndSettle();
      final draggedWidth = tester.getSize(firstPane()).width;
      expect(draggedWidth, greaterThan(200));
      // Let the fire-and-forget persist future land.
      await tester.pump(const Duration(milliseconds: 50));

      // A fresh mount (a new SharedPreferences read, same key) should pick
      // the persisted size back up instead of `initialFirstSize`.
      await pumpUi(tester, const SizedBox.shrink());
      await pumpUi(tester, split('test.resize.persist'));
      await tester.pumpAndSettle();

      expect(tester.getSize(firstPane()).width, closeTo(draggedWidth, 0.5));
    });

    testWidgets('arrow keys nudge the focused handle', (tester) async {
      await pumpUi(tester, split('test.resize.keyboard'));
      await tester.tap(handle('test.resize.keyboard'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(tester.getSize(firstPane()).width, greaterThan(200));
    });
  });

  testWidgets('Gap sizes render without overflow', (tester) async {
    await pumpUi(
      tester,
      const Row(children: [Gap.xs(), Gap.sm(), Gap.md(), Gap.lg(), Gap.xl()]),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppDivider renders on both axes', (tester) async {
    await pumpUi(tester, const Column(children: [AppDivider(), SizedBox(height: 20, child: AppDivider(axis: Axis.vertical))]));
    expect(tester.takeException(), isNull);
  });

  testWidgets('KeyValueList shares one label column across rows', (tester) async {
    await pumpUi(
      tester,
      KeyValueList(
        rows: [
          MetricRow(label: 'Short', value: const Text('a')),
          MetricRow(label: 'A much longer label', value: const Text('b')),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Short'), findsOneWidget);
    expect(find.text('A much longer label'), findsOneWidget);
  });
}
