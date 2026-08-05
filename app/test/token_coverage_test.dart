// V2.3's acceptance criteria (PLAN_V2.md), enforced rather than merely
// documented: greps `lib/` for the three literal patterns the token layer
// exists to eliminate, so a regression shows up as a failing test instead of
// something only caught by a future audit pass. Mirrors the plan's own three
// `grep` commands exactly, including their exclusions:
//   grep -rn "Color(0x" lib --include=*.dart | grep -v core/theme/
//   grep -rn "Colors\.[a-z]" lib --include=*.dart | grep -v Colors.transparent
//   grep -rn "fontFamily: '" lib --include=*.dart | grep -v core/theme/
//
// One exception exists beyond what those `grep -v` filters express: the QR
// quiet zone (`themes/classic.dart`'s `qrQuietZone: Colors.white`) is where
// `AppTokens.chart.qrQuietZone` — the token DESIGN_SYSTEM §1.4 built for
// exactly this — is *defined*. PLAN_V2.md's own criteria comment calls this
// out by name ("the QR quiet zone excepted, tokened as chart.qrQuietZone"),
// the same way `Color(0x`'s exclusion lets `core/theme/` define token values
// without tripping on itself.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _colorLiteralPattern = 'Color(0x';
const _colorsNamedPattern = r'Colors\.[a-z]';
const _fontFamilyPattern = "fontFamily: '";

const _qrQuietZoneException = 'lib/core/theme/themes/classic.dart';

bool _isThemeFile(String relativePath) => relativePath.startsWith('core/theme/') || relativePath.startsWith('core\\theme\\');

Iterable<File> _dartFiles(Directory root) =>
    root.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

String _relativeTo(File file, Directory root) => file.path.substring(root.path.length + 1).replaceAll('\\', '/');

/// Every `lib/*.dart` line matching [pattern], paired with its file:line,
/// excluding [skipTheme] (files under `core/theme/`) and any line matching
/// [lineExclude].
List<String> _violations(
  Directory libDir, {
  required Pattern pattern,
  bool skipTheme = false,
  Pattern? lineExclude,
  bool Function(String relativePath, String line)? extraExclude,
}) {
  final hits = <String>[];
  for (final file in _dartFiles(libDir)) {
    final relative = _relativeTo(file, libDir);
    if (skipTheme && _isThemeFile(relative)) continue;
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!line.contains(pattern)) continue;
      if (lineExclude != null && line.contains(lineExclude)) continue;
      if (extraExclude != null && extraExclude(relative, line)) continue;
      hits.add('lib/$relative:${i + 1}: ${line.trim()}');
    }
  }
  return hits;
}

void main() {
  // Both the test file and `lib/` live under `app/` — `Directory.current` is
  // the package root when `flutter test` runs from `app/`, matching every
  // other test in this suite.
  final libDir = Directory('${Directory.current.path}/lib');

  test('no hardcoded Color(0x...) literals outside core/theme/', () {
    final hits = _violations(libDir, pattern: _colorLiteralPattern, skipTheme: true);
    expect(hits, isEmpty, reason: 'Hardcoded color literals found — route through AppTokens instead:\n${hits.join('\n')}');
  });

  test('no Colors.* literals outside core/theme/, except Colors.transparent and the documented QR quiet zone', () {
    final hits = _violations(
      libDir,
      pattern: RegExp(_colorsNamedPattern),
      lineExclude: 'Colors.transparent',
      extraExclude: (relative, line) => 'lib/$relative' == _qrQuietZoneException && line.contains('qrQuietZone'),
    );
    expect(hits, isEmpty, reason: 'Named Colors.* literals found — route through AppTokens instead:\n${hits.join('\n')}');
  });

  test('no fontFamily string literals outside core/theme/', () {
    final hits = _violations(libDir, pattern: _fontFamilyPattern, skipTheme: true);
    expect(hits, isEmpty, reason: 'Hardcoded fontFamily literals found — route through tokens.typography.mono instead:\n${hits.join('\n')}');
  });
}
