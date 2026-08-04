import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/ui/text.dart';

import 'test_harness.dart';

void main() {
  testWidgets('AppText ellipsizes to one line by default', (tester) async {
    await pumpUi(
      tester,
      SizedBox(width: 80, child: AppText('a very long string that will not fit on one line at all')),
    );
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppText(ellipsis: false) allows wrapping', (tester) async {
    await pumpUi(tester, const AppText('wraps', ellipsis: false));
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.maxLines, isNull);
  });

  testWidgets('NumericText always renders tabular figures in the mono face', (tester) async {
    await pumpUi(tester, const NumericText(1234));
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.style!.fontFamily, 'JetBrains Mono');
    expect(text.style!.fontFeatures, contains(const FontFeature.tabularFigures()));
    expect(find.text('1234'), findsOneWidget);
  });

  testWidgets('NumericText accepts a pre-formatted ratio string', (tester) async {
    await pumpUi(tester, const NumericText('170/300'));
    expect(find.text('170/300'), findsOneWidget);
  });

  testWidgets('MonoText uses the theme mono family', (tester) async {
    await pumpUi(tester, const MonoText('config.env'));
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.style!.fontFamily, 'JetBrains Mono');
  });

  testWidgets('AnimatedCounter settles on the target value', (tester) async {
    await pumpUi(tester, const AnimatedCounter(42));
    await tester.pumpAndSettle();
    expect(find.text('42'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AnimatedCounter retargets when its value changes', (tester) async {
    await pumpUi(tester, const AnimatedCounter(1));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);

    await pumpUi(tester, const AnimatedCounter(9));
    await tester.pumpAndSettle();
    expect(find.text('9'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
