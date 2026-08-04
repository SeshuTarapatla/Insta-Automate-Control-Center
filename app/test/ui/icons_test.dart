import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:ia_control_center/ui/icons.dart';

import 'test_harness.dart';

void main() {
  testWidgets('AppIcon resolves every semantic name at every IconSize', (tester) async {
    final glyphs = <PhosphorIconData Function(PhosphorIconsStyle)>[
      AppIcons.flow,
      AppIcons.service,
      AppIcons.dependency,
      AppIcons.library,
      AppIcons.entity,
      AppIcons.insight,
      AppIcons.settings,
      AppIcons.device,
      AppIcons.mirror,
      AppIcons.notification,
      AppIcons.trigger,
      AppIcons.stop,
      AppIcons.apply,
      AppIcons.discard,
      AppIcons.queue,
      AppIcons.terminal,
      AppIcons.job,
      AppIcons.pair,
    ];

    for (final glyph in glyphs) {
      for (final size in IconSize.values) {
        await pumpUi(tester, AppIcon(glyph, size: size));
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('AppIcon size scales from IconSize.sm to .lg', (tester) async {
    await pumpUi(tester, AppIcon(AppIcons.flow, size: IconSize.sm));
    final small = tester.widget<Icon>(find.byType(Icon)).size!;

    await pumpUi(tester, AppIcon(AppIcons.flow, size: IconSize.lg));
    final large = tester.widget<Icon>(find.byType(Icon)).size!;

    expect(large, greaterThan(small));
  });
}
