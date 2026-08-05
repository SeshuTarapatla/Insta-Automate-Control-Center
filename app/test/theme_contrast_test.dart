// THEMES.md §7 / DESIGN_SYSTEM.md §6 — the accessibility floor, enforced
// rather than merely documented: 4.5:1 for body text and status
// foregrounds, 3:1 for `content.tertiary` and UI boundaries (focus rings,
// selection), against each theme's own `surface.base`. THEMES.md's own
// table is "computed, not measured" and explicitly asks the implementing
// session to re-verify with a real test rather than trust it — this is
// that test, parameterized over all six themes (THEMES.md §1) × the four
// `StatusTokens` states (DESIGN_SYSTEM §1.4) × the three `ContentTokens`
// levels (DESIGN_SYSTEM §1.2), plus `accent.primary` (used for focus rings
// and selection — a UI boundary, THEMES.md §7's table has its own column
// for it).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/core/theme/registry.dart';

const _bodyFloor = 4.5;
const _boundaryFloor = 3.0;

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// Some tokens carry real alpha (Mica's whole surface stack, by design —
/// THEMES.md §4; `content.tertiary` in every dark theme, by design —
/// THEMES.md §7's closing note). A translucent color's *own* luminance
/// doesn't describe what a user actually sees; what they see is it
/// composited over whatever's behind it. Flattens against black/white by
/// the theme's own brightness — a defensible stand-in for "whatever's
/// behind a translucent panel," and a no-op for the five fully-opaque
/// themes where every base already has alpha 1.0.
Color _flattenOverBackdrop(Color c, Brightness brightness) =>
    Color.alphaBlend(c, brightness == Brightness.dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF));

void main() {
  for (final entry in themeRegistry.entries) {
    final tokens = entry.value();
    final baseOpaque = _flattenOverBackdrop(tokens.surface.base, tokens.brightness);

    group(tokens.name, () {
      void checkAgainstBase(String label, Color foreground, double floor) {
        test(label, () {
          // Composited onto the (now-opaque) base, same as how it's
          // actually painted — not the raw, possibly-translucent color's
          // own luminance.
          final fg = Color.alphaBlend(foreground, baseOpaque);
          final ratio = _contrastRatio(fg, baseOpaque);
          expect(
            ratio,
            greaterThanOrEqualTo(floor),
            reason: '${tokens.name} $label is ${ratio.toStringAsFixed(2)}:1 against surface.base — needs >= $floor:1',
          );
        });
      }

      // Three content levels (DESIGN_SYSTEM §1.2). `tertiary` is
      // placeholder/disabled text — WCAG's minimum doesn't apply there and
      // full contrast would defeat the purpose (THEMES.md §7) — so it's
      // held to the lower UI-boundary floor instead.
      checkAgainstBase('content.primary', tokens.content.primary, _bodyFloor);
      checkAgainstBase('content.secondary', tokens.content.secondary, _bodyFloor);
      checkAgainstBase('content.tertiary', tokens.content.tertiary, _boundaryFloor);

      // Four statuses (DESIGN_SYSTEM §1.4) — foregrounds only; the
      // container/onContainer pair is a filled chip, not text on
      // `surface.base`, so it's out of scope for this check.
      checkAgainstBase('status.good', tokens.status.good.fg, _bodyFloor);
      checkAgainstBase('status.info', tokens.status.info.fg, _bodyFloor);
      checkAgainstBase('status.warn', tokens.status.warn.fg, _bodyFloor);
      checkAgainstBase('status.bad', tokens.status.bad.fg, _bodyFloor);

      // Accent — focus rings and selection, a UI boundary rather than body
      // text (THEMES.md §7's table carries it as its own column).
      checkAgainstBase('accent.primary', tokens.accent.primary, _boundaryFloor);
    });
  }
}
