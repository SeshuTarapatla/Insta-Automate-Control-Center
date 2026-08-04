// COMPONENTS.md §12 — icons. Phosphor replaces Material Icons app-wide
// (DESIGN_SYSTEM §3): semantic names here, resolved to a glyph at the
// theme's own weight, so Swiss's bold / Nocturne's light apply everywhere
// without a per-call-site choice, and changing a glyph is a one-line edit
// instead of a sweep across ~200 call sites.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/theme/tokens.dart';

/// `space.iconSm/Md/Lg` (14/18/24 at comfortable — DESIGN_SYSTEM §3),
/// replacing the eight literal sizes AUDIT §1.8 found.
enum IconSize { sm, md, lg }

extension IconSizeX on IconSize {
  double resolve(AppTokens t) => switch (this) {
    IconSize.sm => t.space.iconSm,
    IconSize.md => t.space.iconMd,
    IconSize.lg => t.space.iconLg,
  };
}

/// One name per concept this app actually renders. Glyph names, not layout —
/// swapping the Phosphor glyph for "flow" is a one-line change here, never a
/// grep across features.
class AppIcons {
  const AppIcons._();

  static PhosphorIconData flow(PhosphorIconsStyle w) => PhosphorIcons.flowArrow(w);
  static PhosphorIconData service(PhosphorIconsStyle w) => PhosphorIcons.plugsConnected(w);
  static PhosphorIconData dependency(PhosphorIconsStyle w) => PhosphorIcons.treeStructure(w);
  static PhosphorIconData library(PhosphorIconsStyle w) => PhosphorIcons.imagesSquare(w);
  static PhosphorIconData entity(PhosphorIconsStyle w) => PhosphorIcons.userCircle(w);
  static PhosphorIconData insight(PhosphorIconsStyle w) => PhosphorIcons.chartLine(w);
  static PhosphorIconData settings(PhosphorIconsStyle w) => PhosphorIcons.gear(w);
  static PhosphorIconData device(PhosphorIconsStyle w) => PhosphorIcons.deviceMobile(w);
  static PhosphorIconData mirror(PhosphorIconsStyle w) => PhosphorIcons.monitor(w);
  static PhosphorIconData notification(PhosphorIconsStyle w) => PhosphorIcons.bell(w);
  static PhosphorIconData trigger(PhosphorIconsStyle w) => PhosphorIcons.playCircle(w);
  static PhosphorIconData stop(PhosphorIconsStyle w) => PhosphorIcons.stop(w);
  static PhosphorIconData apply(PhosphorIconsStyle w) => PhosphorIcons.checkCircle(w);
  static PhosphorIconData discard(PhosphorIconsStyle w) => PhosphorIcons.trash(w);
  static PhosphorIconData queue(PhosphorIconsStyle w) => PhosphorIcons.listBullets(w);
  static PhosphorIconData terminal(PhosphorIconsStyle w) => PhosphorIcons.terminal(w);
  static PhosphorIconData job(PhosphorIconsStyle w) => PhosphorIcons.gearSix(w);
  static PhosphorIconData pair(PhosphorIconsStyle w) => PhosphorIcons.qrCode(w);
}

/// Resolves a semantic glyph function at the theme's `iconWeight` — every
/// call site passes one of the `AppIcons.*` functions above, never a raw
/// `PhosphorIconData`, so a theme change re-weights the whole app for free.
class AppIcon extends StatelessWidget {
  const AppIcon(this.glyph, {super.key, this.size = IconSize.md, this.color});

  final PhosphorIconData Function(PhosphorIconsStyle) glyph;
  final IconSize size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    return Icon(glyph(tokens.type.iconWeight), size: size.resolve(tokens), color: color);
  }
}
