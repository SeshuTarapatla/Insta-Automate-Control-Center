import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/ui/motion.dart';

import 'test_harness.dart';

void main() {
  testWidgets('FadeSlideIn renders its child and settles', (tester) async {
    await pumpUi(tester, const FadeSlideIn(index: 3, child: Text('row')));
    expect(find.text('row'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('FadeSlideIn caps its stagger so a long list settles quickly', (tester) async {
    await pumpUi(tester, const FadeSlideIn(index: 500, child: Text('far down the list')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('far down the list'), findsOneWidget);
  });

  testWidgets('AnimatedReveal cross-fades between two different children', (tester) async {
    await pumpUi(tester, const AnimatedReveal(visible: true, child: Text('in progress')));
    expect(find.text('in progress'), findsOneWidget);

    await pumpUi(tester, const AnimatedReveal(visible: true, child: Text('resolved')));
    await tester.pumpAndSettle();
    expect(find.text('resolved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AnimatedReveal(visible: false) collapses to nothing', (tester) async {
    await pumpUi(tester, const AnimatedReveal(visible: false, child: Text('hidden')));
    await tester.pumpAndSettle();
    expect(find.text('hidden'), findsNothing);
  });

  testWidgets('PageTransition swaps content when its key changes', (tester) async {
    await pumpUi(tester, const PageTransition(transitionKey: 'flows', child: Text('Flows page')));
    expect(find.text('Flows page'), findsOneWidget);

    await pumpUi(tester, const PageTransition(transitionKey: 'live', child: Text('Live page')));
    await tester.pumpAndSettle();
    expect(find.text('Live page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
