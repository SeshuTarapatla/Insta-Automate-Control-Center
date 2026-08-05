// D104 — regression test for a real bug that shipped invisibly from V2.1
// through V2.3: `AppTokens` had a field literally named `type`, colliding
// with `ThemeExtension<T>`'s own `type` getter, which Flutter uses as the
// map key when building `ThemeData.extensions` from the constructor's list.
// That silently broke `Theme.of(context).extension<AppTokens>()` for every
// theme, always — `AppTokensX.tokens` fell back to `buildClassicTokens()`
// unconditionally. It was invisible for three checkpoints because Classic
// was the only theme that existed, so the fallback and the real value were
// identical; every other test in this suite either builds against Classic
// only (`test_harness.dart`) or reads a theme's `AppTokens` directly without
// going through `Theme.of(context)` at all (`theme_contrast_test.dart`), so
// none of them could have caught it either. This test renders a widget
// under each *non-Classic* theme and asserts the extension actually
// resolved to it — the one thing every other test structurally couldn't
// check.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/core/theme/build_theme.dart';
import 'package:ia_control_center/core/theme/registry.dart';
import 'package:ia_control_center/core/theme/tokens.dart';

void main() {
  for (final entry in themeRegistry.entries) {
    final id = entry.key;

    testWidgets('Theme.of(context).tokens resolves to $id, not the Classic fallback', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(entry.value()),
          home: Builder(
            builder: (context) {
              final resolved = Theme.of(context).tokens;
              return Text(resolved.id.name);
            },
          ),
        ),
      );

      expect(find.text(id.name), findsOneWidget);
    });
  }
}
