// COMPONENTS.md §7 — layout.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/tokens.dart';

/// The answer to AUDIT §11 — thirteen hardcoded pixel widths, several of
/// which the code itself flags as tuned to one flow or one window size
/// (`live_page.dart:179-190`). Draggable, persisted to `shared_preferences`
/// under [persistKey], with `SystemMouseCursors.resizeColumn`/`.resizeRow` on
/// the handle and arrow-key nudging so the divider is keyboard-reachable too.
/// [initialFirstSize] becomes the default the very first time this key is
/// seen — the app opens exactly as it does today, and the user can change it.
class ResizableSplit extends StatefulWidget {
  const ResizableSplit({
    super.key,
    required this.first,
    required this.second,
    this.axis = Axis.horizontal,
    this.initialFirstSize = 320,
    this.minFirst = 160,
    this.minSecond = 160,
    required this.persistKey,
  });

  final Widget first;
  final Widget second;
  final Axis axis;
  final double initialFirstSize;
  final double minFirst;
  final double minSecond;
  final String persistKey;

  @override
  State<ResizableSplit> createState() => _ResizableSplitState();
}

class _ResizableSplitState extends State<ResizableSplit> {
  static const _handleThickness = 10.0;
  static const _keyboardStep = 24.0;

  double? _firstSize;
  final _focusNode = FocusNode(debugLabel: 'ResizableSplit handle');

  String get _prefsKey => 'ui.resizable_split.${widget.persistKey}';

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_prefsKey);
    if (saved != null && mounted) setState(() => _firstSize = saved);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefsKey, _firstSize ?? widget.initialFirstSize);
  }

  double _clamp(double value, double maxExtent) {
    final ceiling = (maxExtent - widget.minSecond - _handleThickness).clamp(widget.minFirst, double.infinity);
    return value.clamp(widget.minFirst, ceiling);
  }

  void _nudge(double delta, double maxExtent) {
    setState(() => _firstSize = _clamp((_firstSize ?? widget.initialFirstSize) + delta, maxExtent));
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    final horizontal = widget.axis == Axis.horizontal;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxExtent = horizontal ? constraints.maxWidth : constraints.maxHeight;
        final firstSize = _clamp(_firstSize ?? widget.initialFirstSize, maxExtent);

        final handle = Focus(
          focusNode: _focusNode,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
            final key = event.logicalKey;
            final step = horizontal
                ? (key == LogicalKeyboardKey.arrowLeft
                      ? -_keyboardStep
                      : (key == LogicalKeyboardKey.arrowRight ? _keyboardStep : null))
                : (key == LogicalKeyboardKey.arrowUp
                      ? -_keyboardStep
                      : (key == LogicalKeyboardKey.arrowDown ? _keyboardStep : null));
            if (step == null) return KeyEventResult.ignored;
            _nudge(step, maxExtent);
            _persist();
            return KeyEventResult.handled;
          },
          child: MouseRegion(
            cursor: horizontal ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
            child: GestureDetector(
              key: ValueKey('resizable_split_handle:${widget.persistKey}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _focusNode.requestFocus(),
              onPanUpdate: (details) => _nudge(horizontal ? details.delta.dx : details.delta.dy, maxExtent),
              onPanEnd: (_) => _persist(),
              child: SizedBox(
                width: horizontal ? _handleThickness : double.infinity,
                height: horizontal ? double.infinity : _handleThickness,
                child: Center(
                  child: AnimatedContainer(
                    duration: tokens.motion.instant,
                    width: horizontal ? tokens.geometry.hairline : 28,
                    height: horizontal ? 28 : tokens.geometry.hairline,
                    decoration: BoxDecoration(
                      color: _focusNode.hasFocus ? tokens.accent.primary : tokens.surface.borderStrong,
                      borderRadius: BorderRadius.circular(tokens.geometry.radiusFull),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        return Flex(
          direction: widget.axis,
          children: [
            SizedBox(width: horizontal ? firstSize : null, height: horizontal ? null : firstSize, child: widget.first),
            handle,
            Expanded(child: widget.second),
          ],
        );
      },
    );
  }
}

/// Replaces the ~200 `SizedBox(height/width: N)` literals AUDIT found —
/// reads its size from `tokens.space` at build time, so it scales with
/// density (DESIGN_SYSTEM §1.8) automatically.
class Gap extends StatelessWidget {
  const Gap.xs({super.key}) : _size = _GapSize.xs;
  const Gap.sm({super.key}) : _size = _GapSize.sm;
  const Gap.md({super.key}) : _size = _GapSize.md;
  const Gap.lg({super.key}) : _size = _GapSize.lg;
  const Gap.xl({super.key}) : _size = _GapSize.xl;

  final _GapSize _size;

  @override
  Widget build(BuildContext context) {
    final space = Theme.of(context).tokens.space;
    final size = switch (_size) {
      _GapSize.xs => space.xs,
      _GapSize.sm => space.sm,
      _GapSize.md => space.md,
      _GapSize.lg => space.lg,
      _GapSize.xl => space.xl,
    };
    return SizedBox(width: size, height: size);
  }
}

enum _GapSize { xs, sm, md, lg, xl }

/// `tokens.surface.border`/`.borderStrong` at `tokens.geometry.hairline` —
/// the one place a divider color/thickness is chosen.
class AppDivider extends StatelessWidget {
  const AppDivider({super.key, this.strong = false, this.axis = Axis.horizontal});

  final bool strong;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    final color = strong ? tokens.surface.borderStrong : tokens.surface.border;
    return axis == Axis.horizontal
        ? Divider(color: color, thickness: tokens.geometry.hairline, height: tokens.geometry.hairline)
        : VerticalDivider(color: color, thickness: tokens.geometry.hairline, width: tokens.geometry.hairline);
  }
}

/// One label/value pair. Usable standalone in a `Column`, or as the data a
/// [KeyValueList] lays out with a shared label column width.
class MetricRow extends StatelessWidget {
  const MetricRow({super.key, required this.label, required this.value, this.icon, this.labelWidth});

  final String label;
  final Widget value;
  final IconData? icon;
  final double? labelWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: tokens.space.iconSm, color: tokens.content.secondary),
            SizedBox(width: tokens.space.xs),
          ],
          SizedBox(width: labelWidth, child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary))),
          SizedBox(width: tokens.space.sm),
          Expanded(child: value),
        ],
      ),
    );
  }
}

/// [MetricRow]s sharing one label column, auto-sized to the longest label —
/// replaces `run_summary.dart`'s private `_SummaryRow` (a hardcoded 76px
/// gutter) and the several label/value stacks in `service_detail.dart`.
class KeyValueList extends StatelessWidget {
  const KeyValueList({super.key, required this.rows, this.labelWidth});

  final List<MetricRow> rows;
  final double? labelWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    return Table(
      columnWidths: {0: labelWidth != null ? FixedColumnWidth(labelWidth!) : const IntrinsicColumnWidth()},
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        for (final row in rows)
          TableRow(
            children: [
              Padding(
                padding: EdgeInsets.only(right: tokens.space.sm, top: tokens.space.xs, bottom: tokens.space.xs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (row.icon != null) ...[
                      Icon(row.icon, size: tokens.space.iconSm, color: tokens.content.secondary),
                      SizedBox(width: tokens.space.xs),
                    ],
                    // Flexible, not a bare `Text` — a fixed [labelWidth] minus
                    // this padding can be narrower than a real label's
                    // intrinsic width, and a bare `Text` here throws a
                    // `RenderFlex` overflow instead of ellipsizing the way
                    // every other label in v2 defaults to.
                    Flexible(
                      child: Text(
                        row.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: tokens.content.secondary),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(padding: EdgeInsets.symmetric(vertical: tokens.space.xs), child: row.value),
            ],
          ),
      ],
    );
  }
}
