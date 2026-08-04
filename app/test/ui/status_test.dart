import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/ui/status.dart';

import 'test_harness.dart';

void main() {
  for (final kind in StatusKind.values) {
    testWidgets('StatusDot renders for $kind, pulsing and not', (tester) async {
      await pumpUi(tester, StatusDot(kind: kind));
      expect(tester.takeException(), isNull);
      await pumpUi(tester, StatusDot(kind: kind, pulsing: true));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('StatusChip pairs color with a label, never color alone', (tester) async {
    await pumpUi(tester, const StatusChip(kind: StatusKind.warn, label: 'Blocked', icon: Icons.warning_amber));
    expect(find.text('Blocked'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber), findsOneWidget);
  });

  testWidgets('CountBadge hides at zero unless dot mode', (tester) async {
    await pumpUi(tester, const CountBadge(count: 0));
    expect(find.byType(CountBadge), findsOneWidget);
    expect(find.descendant(of: find.byType(CountBadge), matching: find.byType(Text)), findsNothing);

    await pumpUi(tester, const CountBadge(count: 0, dot: true));
    expect(tester.takeException(), isNull);

    await pumpUi(tester, const CountBadge(count: 250));
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('OutcomeBadge renders its label', (tester) async {
    await pumpUi(tester, const OutcomeBadge(label: 'PRIVATE', kind: StatusKind.good));
    expect(find.text('PRIVATE'), findsOneWidget);
  });
}
