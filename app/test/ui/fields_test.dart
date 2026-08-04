import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/ui/fields.dart';

import 'test_harness.dart';

void main() {
  testWidgets('AppTextField reports changes', (tester) async {
    String? value;
    await pumpUi(tester, AppTextField(hint: 'name', onChanged: (v) => value = v));
    await tester.enterText(find.byType(TextField), 'sejjjalll');
    expect(value, 'sejjjalll');
  });

  testWidgets('SearchField debounces, shows a clear button once non-empty, and Esc clears', (tester) async {
    final calls = <String>[];
    await pumpUi(tester, SearchField(onChanged: calls.add, debounce: const Duration(milliseconds: 50)));

    expect(find.byIcon(Icons.close), findsNothing);
    await tester.enterText(find.byType(TextField), 'root');
    await tester.pump(const Duration(milliseconds: 10));
    expect(calls, isEmpty, reason: 'debounced — should not have fired yet');
    await tester.pump(const Duration(milliseconds: 60));
    expect(calls, ['root']);
    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(calls.last, '');
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('AppSelect shows every option and reports the selection', (tester) async {
    var selected = 'a';
    await pumpUi(
      tester,
      StatefulBuilder(
        builder: (context, setState) => AppSelect<String>(
          value: selected,
          options: const [AppOption(value: 'a', label: 'Alpha'), AppOption(value: 'b', label: 'Beta')],
          onChanged: (v) => setState(() => selected = v),
        ),
      ),
    );
    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta').last);
    await tester.pumpAndSettle();
    expect(selected, 'b');
  });

  testWidgets('AppSwitch turning on needs no confirmation', (tester) async {
    var value = false;
    await pumpUi(tester, AppSwitch(value: value, confirmMessage: 'stops everything', onChanged: (v) => value = v));
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(value, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('AppSwitch turning off with confirmMessage prompts, and only fires onChanged when confirmed', (tester) async {
    var value = true;
    await pumpUi(tester, AppSwitch(value: value, confirmMessage: 'stops everything', onChanged: (v) => value = v));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('stops everything'), findsOneWidget);
    expect(value, isTrue, reason: 'not yet confirmed');

    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();
    expect(value, isFalse);
  });

  testWidgets('AppSwitch turning off cancelled leaves the value unchanged', (tester) async {
    var value = true;
    await pumpUi(tester, AppSwitch(value: value, confirmMessage: 'stops everything', onChanged: (v) => value = v));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(value, isTrue);
  });
}
