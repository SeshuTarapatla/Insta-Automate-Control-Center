import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/ui/buttons.dart';

import 'test_harness.dart';

void main() {
  testWidgets('AppButton fires onPressed for every tone/size/filled combination', (tester) async {
    for (final tone in ButtonTone.values) {
      for (final size in ButtonSize.values) {
        for (final filled in [true, false]) {
          var pressed = false;
          await pumpUi(
            tester,
            AppButton(label: 'Go', tone: tone, size: size, filled: filled, onPressed: () => pressed = true),
          );
          await tester.tap(find.text('Go'));
          await tester.pump();
          expect(pressed, isTrue, reason: '$tone/$size/filled=$filled');
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets('AppButton(busy: true) disables the button and shows a spinner instead of the label', (tester) async {
    var pressed = false;
    await pumpUi(tester, AppButton(label: 'Apply', busy: true, onPressed: () => pressed = true));
    expect(find.text('Apply'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(OutlinedButton), warnIfMissed: false);
    await tester.pump();
    expect(pressed, isFalse);
  });

  testWidgets('AppButton(onPressed: null) is disabled', (tester) async {
    await pumpUi(tester, const AppButton(label: 'Disabled', onPressed: null));
    final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('IconAction requires and exposes its tooltip as a Semantics label', (tester) async {
    var pressed = false;
    await pumpUi(tester, IconAction(icon: Icons.delete, tooltip: 'Delete', onPressed: () => pressed = true));
    expect(find.bySemanticsLabel('Delete'), findsOneWidget);
    await tester.tap(find.byType(IconButton));
    expect(pressed, isTrue);
  });

  testWidgets('ButtonGroup wraps instead of overflowing at a narrow width', (tester) async {
    await pumpUi(
      tester,
      SizedBox(
        width: 160,
        child: ButtonGroup(
          children: [for (var i = 0; i < 6; i++) AppButton(label: 'Button $i', onPressed: () {})],
        ),
      ),
      size: const Size(1024, 700),
    );
    expect(tester.takeException(), isNull);
  });
}
