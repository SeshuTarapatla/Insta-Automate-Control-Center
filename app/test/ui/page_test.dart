import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/core/nav_state.dart';
import 'package:ia_control_center/core/theme/build_theme.dart';
import 'package:ia_control_center/core/theme/themes/classic.dart';
import 'package:ia_control_center/ui/page.dart';

import 'test_harness.dart';

void main() {
  testWidgets('AppPage renders title, actions and body with no overflow at the 1024 floor', (tester) async {
    await pumpUi(
      tester,
      AppPage(
        title: 'Ops jobs',
        subtitle: 'Real commands, streamed output',
        actions: [FilledButton(onPressed: () {}, child: const Text('Deploy flows'))],
        body: const Text('body content'),
      ),
      size: const Size(1024, 700),
    );
    expect(find.text('Ops jobs'), findsOneWidget);
    expect(find.text('Deploy flows'), findsOneWidget);
    expect(find.text('body content'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppPage(leading:) sits alongside the title, e.g. the Live flow selector', (tester) async {
    await pumpUi(
      tester,
      AppPage(title: 'Live', leading: const Text('flow chips'), body: const SizedBox.shrink()),
    );
    expect(find.text('flow chips'), findsOneWidget);
  });

  testWidgets('AppPage constrains content to maxContentWidth when set', (tester) async {
    await pumpUi(
      tester,
      AppPage(title: 'Insights', maxContentWidth: 300, body: const SizedBox(key: Key('body'), width: 900, height: 10)),
    );
    // The ConstrainedBox caps the render width even though the child asked
    // for 900 — this is Insights' hardcoded 900 becoming a real constraint.
    final size = tester.getSize(find.byKey(const Key('body')));
    expect(size.width, lessThanOrEqualTo(300));
  });

  testWidgets('SectionHeader with navIndex jumps the shared selectedNavIndexProvider on tap', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1024, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(buildClassicTokens()),
          home: const Scaffold(body: SectionHeader(title: 'Flows', navIndex: flowsIndex)),
        ),
      ),
    );

    expect(container.read(selectedNavIndexProvider), 0);
    await tester.tap(find.text('Flows'));
    await tester.pump();
    expect(container.read(selectedNavIndexProvider), flowsIndex);
  });

  testWidgets('SectionHeader with no navIndex is not tappable', (tester) async {
    await pumpUi(tester, const SectionHeader(title: 'Static section'));
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('Toolbar wraps leading/trailing groups without overflow at a narrow width', (tester) async {
    await pumpUi(
      tester,
      SizedBox(
        width: 200,
        child: Toolbar(
          leading: [const Text('Filter'), const Text('Sort')],
          trailing: [FilledButton(onPressed: () {}, child: const Text('Apply'))],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
