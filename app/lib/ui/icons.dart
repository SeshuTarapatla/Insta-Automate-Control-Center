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
  static PhosphorIconData notificationOff(PhosphorIconsStyle w) => PhosphorIcons.bellSlash(w);
  static PhosphorIconData trigger(PhosphorIconsStyle w) => PhosphorIcons.playCircle(w);
  static PhosphorIconData stop(PhosphorIconsStyle w) => PhosphorIcons.stop(w);
  static PhosphorIconData apply(PhosphorIconsStyle w) => PhosphorIcons.checkCircle(w);
  static PhosphorIconData discard(PhosphorIconsStyle w) => PhosphorIcons.trash(w);
  static PhosphorIconData queue(PhosphorIconsStyle w) => PhosphorIcons.listBullets(w);
  static PhosphorIconData terminal(PhosphorIconsStyle w) => PhosphorIcons.terminal(w);
  static PhosphorIconData job(PhosphorIconsStyle w) => PhosphorIcons.gearSix(w);
  static PhosphorIconData pair(PhosphorIconsStyle w) => PhosphorIcons.qrCode(w);
  static PhosphorIconData command(PhosphorIconsStyle w) => PhosphorIcons.command(w);
  static PhosphorIconData sidebarCollapse(PhosphorIconsStyle w) => PhosphorIcons.sidebarSimple(w);

  /// The human-review waypoint marker (Flows' two ⚑ edges, V2.6; Library's
  /// folder-rail review markers, V2.9) — one glyph for "the pipeline is
  /// waiting on you here," reused wherever that's true.
  static PhosphorIconData review(PhosphorIconsStyle w) => PhosphorIcons.flag(w);

  // Generic, reused across several screens rather than tied to one domain
  // concept — added during the V2.3 migration as real repeated needs, not
  // guessed up front.
  static PhosphorIconData search(PhosphorIconsStyle w) => PhosphorIcons.magnifyingGlass(w);
  static PhosphorIconData close(PhosphorIconsStyle w) => PhosphorIcons.x(w);
  static PhosphorIconData copy(PhosphorIconsStyle w) => PhosphorIcons.copy(w);
  static PhosphorIconData openExternal(PhosphorIconsStyle w) => PhosphorIcons.arrowSquareOut(w);
  static PhosphorIconData folderOpen(PhosphorIconsStyle w) => PhosphorIcons.folderOpen(w);
  static PhosphorIconData folderOff(PhosphorIconsStyle w) => PhosphorIcons.folderMinus(w);
  static PhosphorIconData refresh(PhosphorIconsStyle w) => PhosphorIcons.arrowsClockwise(w);
  static PhosphorIconData warning(PhosphorIconsStyle w) => PhosphorIcons.warningCircle(w);
  static PhosphorIconData error(PhosphorIconsStyle w) => PhosphorIcons.xCircle(w);
  static PhosphorIconData info(PhosphorIconsStyle w) => PhosphorIcons.info(w);
  static PhosphorIconData success(PhosphorIconsStyle w) => PhosphorIcons.checkCircle(w);
  static PhosphorIconData check(PhosphorIconsStyle w) => PhosphorIcons.check(w);
  static PhosphorIconData play(PhosphorIconsStyle w) => PhosphorIcons.play(w);
  static PhosphorIconData pause(PhosphorIconsStyle w) => PhosphorIcons.pause(w);
  static PhosphorIconData chevronDown(PhosphorIconsStyle w) => PhosphorIcons.caretDown(w);
  static PhosphorIconData chevronUp(PhosphorIconsStyle w) => PhosphorIcons.caretUp(w);
  static PhosphorIconData chevronRight(PhosphorIconsStyle w) => PhosphorIcons.caretRight(w);
  static PhosphorIconData link(PhosphorIconsStyle w) => PhosphorIcons.link(w);
  static PhosphorIconData linkOff(PhosphorIconsStyle w) => PhosphorIcons.linkBreak(w);
  static PhosphorIconData image(PhosphorIconsStyle w) => PhosphorIcons.image(w);
  static PhosphorIconData imageOff(PhosphorIconsStyle w) => PhosphorIcons.imageBroken(w);
  static PhosphorIconData hourglass(PhosphorIconsStyle w) => PhosphorIcons.hourglassMedium(w);
  static PhosphorIconData filter(PhosphorIconsStyle w) => PhosphorIcons.funnel(w);
  static PhosphorIconData sort(PhosphorIconsStyle w) => PhosphorIcons.sortAscending(w);
  static PhosphorIconData dragHandle(PhosphorIconsStyle w) => PhosphorIcons.dotsSixVertical(w);
  static PhosphorIconData moreVertical(PhosphorIconsStyle w) => PhosphorIcons.dotsThreeVertical(w);
  static PhosphorIconData help(PhosphorIconsStyle w) => PhosphorIcons.question(w);
  static PhosphorIconData grid(PhosphorIconsStyle w) => PhosphorIcons.gridFour(w);
  static PhosphorIconData list(PhosphorIconsStyle w) => PhosphorIcons.listChecks(w);
  static PhosphorIconData add(PhosphorIconsStyle w) => PhosphorIcons.plus(w);
  static PhosphorIconData remove(PhosphorIconsStyle w) => PhosphorIcons.minus(w);
  static PhosphorIconData person(PhosphorIconsStyle w) => PhosphorIcons.user(w);
  static PhosphorIconData science(PhosphorIconsStyle w) => PhosphorIcons.testTube(w);
  static PhosphorIconData swap(PhosphorIconsStyle w) => PhosphorIcons.swap(w);
  static PhosphorIconData server(PhosphorIconsStyle w) => PhosphorIcons.hardDrive(w);
  static PhosphorIconData offline(PhosphorIconsStyle w) => PhosphorIcons.cloudSlash(w);
  static PhosphorIconData movie(PhosphorIconsStyle w) => PhosphorIcons.filmSlate(w);
  static PhosphorIconData document(PhosphorIconsStyle w) => PhosphorIcons.fileText(w);
  static PhosphorIconData sensor(PhosphorIconsStyle w) => PhosphorIcons.pulse(w);
  static PhosphorIconData arrowUp(PhosphorIconsStyle w) => PhosphorIcons.arrowUp(w);
  static PhosphorIconData arrowDown(PhosphorIconsStyle w) => PhosphorIcons.arrowDown(w);
  static PhosphorIconData sync(PhosphorIconsStyle w) => PhosphorIcons.arrowsClockwise(w);
  static PhosphorIconData schedule(PhosphorIconsStyle w) => PhosphorIcons.clock(w);
  static PhosphorIconData calendar(PhosphorIconsStyle w) => PhosphorIcons.calendarBlank(w);
  static PhosphorIconData eye(PhosphorIconsStyle w) => PhosphorIcons.eye(w);
  static PhosphorIconData eyeOff(PhosphorIconsStyle w) => PhosphorIcons.eyeSlash(w);
  static PhosphorIconData selfHeal(PhosphorIconsStyle w) => PhosphorIcons.bandaids(w);
  static PhosphorIconData history(PhosphorIconsStyle w) => PhosphorIcons.clockCounterClockwise(w);
  static PhosphorIconData overview(PhosphorIconsStyle w) => PhosphorIcons.squaresFour(w);
  static PhosphorIconData brand(PhosphorIconsStyle w) => PhosphorIcons.shareNetwork(w);
  static PhosphorIconData windowMinimize(PhosphorIconsStyle w) => PhosphorIcons.minus(w);
  static PhosphorIconData windowMaximize(PhosphorIconsStyle w) => PhosphorIcons.square(w);
  static PhosphorIconData windowRestore(PhosphorIconsStyle w) => PhosphorIcons.copy(w);
  static PhosphorIconData windowClose(PhosphorIconsStyle w) => PhosphorIcons.x(w);

  /// Maximise/restore a single pane (the Live screen's log/visualization
  /// split, V2.8) — distinct from the window-chrome icons above.
  static PhosphorIconData expand(PhosphorIconsStyle w) => PhosphorIcons.arrowsOut(w);
  static PhosphorIconData collapse(PhosphorIconsStyle w) => PhosphorIcons.arrowsIn(w);

  // Density/zoom steps — the library grid's small/medium/large tile-size
  // control, small→large by dot/square count so the icon itself communicates
  // scale.
  static PhosphorIconData densitySmall(PhosphorIconsStyle w) => PhosphorIcons.dotsNine(w);
  static PhosphorIconData densityMedium(PhosphorIconsStyle w) => PhosphorIcons.squaresFour(w);
  static PhosphorIconData densityLarge(PhosphorIconsStyle w) => PhosphorIcons.square(w);
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
    return Icon(glyph(tokens.typography.iconWeight), size: size.resolve(tokens), color: color);
  }
}
