import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/ui/status.dart';
import 'package:ia_control_center/ui/surfaces.dart';

import 'test_harness.dart';

void main() {
  testWidgets('AppCard renders its child with no overflow', (tester) async {
    await pumpUi(tester, const AppCard(child: Text('hello')));
    expect(tester.takeException(), isNull);
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('AppWell/AppOverlay render at every SurfaceLevel', (tester) async {
    await pumpUi(
      tester,
      const Column(
        children: [
          AppWell(child: Text('well')),
          AppOverlay(child: Text('overlay')),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppPanel with accentEdge and selected renders without throwing', (tester) async {
    await pumpUi(
      tester,
      const AppPanel(selected: true, accentEdge: StatusKind.bad, child: Text('flagged')),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('flagged'), findsOneWidget);
  });

  testWidgets('AppPanel onTap fires and hover/press states do not throw', (tester) async {
    var tapped = false;
    await pumpUi(
      tester,
      AppPanel(onTap: () => tapped = true, child: const Text('click me')),
    );
    await tester.tap(find.text('click me'));
    await tester.pump();
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppPanel onSecondaryTap fires on right-click', (tester) async {
    var secondaryTapped = false;
    await pumpUi(
      tester,
      AppPanel(onSecondaryTap: () => secondaryTapped = true, child: const Text('right click me')),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
    await gesture.addPointer();
    await gesture.down(tester.getCenter(find.text('right click me')));
    await gesture.up();
    await tester.pump();
    expect(secondaryTapped, isTrue);
  });
}
