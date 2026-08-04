import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/ui/overlays.dart';
import 'package:ia_control_center/ui/status.dart';

import 'test_harness.dart';

void main() {
  testWidgets('AppDialog.show renders title/body/actions and Esc closes it', (tester) async {
    late BuildContext ctx;
    await pumpUi(
      tester,
      Builder(
        builder: (context) {
          ctx = context;
          return const SizedBox.shrink();
        },
      ),
    );

    unawaited(
      AppDialog.show<void>(
        ctx,
        title: 'Confirm',
        body: const Text('are you sure'),
        actions: [TextButton(onPressed: () {}, child: const Text('OK'))],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('are you sure'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Confirm'), findsNothing);
  });

  testWidgets('AppTooltip(rich: true) shows title and message on long-press', (tester) async {
    await pumpUi(
      tester,
      const AppTooltip(rich: true, title: 'Why blocked', message: 'scraped ≥ reserve', monoBody: true, child: Icon(Icons.info)),
    );
    await tester.longPress(find.byIcon(Icons.info));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Why blocked'), findsOneWidget);
    expect(find.text('scraped ≥ reserve'), findsOneWidget);
  });

  testWidgets('AppMenu opens on right-click and an item fires', (tester) async {
    var tapped = false;
    await pumpUi(
      tester,
      AppMenu(
        items: [AppMenuItem(label: 'Delete', danger: true, onTap: () => tapped = true)],
        child: const SizedBox(width: 40, height: 40, child: ColoredBox(color: Colors.grey)),
      ),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kSecondaryButton);
    await gesture.addPointer();
    await gesture.down(tester.getCenter(find.byType(ColoredBox)));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });

  testWidgets('AppSnack.show surfaces a message', (tester) async {
    late BuildContext ctx;
    await pumpUi(
      tester,
      Builder(
        builder: (context) {
          ctx = context;
          return const SizedBox.shrink();
        },
      ),
    );
    AppSnack.show(ctx, 'saved', kind: StatusKind.good);
    await tester.pump();
    expect(find.text('saved'), findsOneWidget);
  });
}
