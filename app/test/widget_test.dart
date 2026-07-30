import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/features/placeholder_page.dart';

void main() {
  testWidgets('PlaceholderPage renders its title', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PlaceholderPage(title: 'Overview')),
    );

    expect(find.text('Overview'), findsOneWidget);
  });
}
