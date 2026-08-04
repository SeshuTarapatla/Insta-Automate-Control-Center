// COMPONENTS.md §10 — data display. Generalises the hand-built table from
// D77, which exists precisely because Material's `DataTable` cannot make one
// column flexible while the rest stay fixed — that lesson is preserved and
// made reusable: `width: null` is the flexible column, everything else
// fixed, exactly the behaviour D77 hand-rolled for the ranking table.
import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import 'status.dart';
import 'text.dart';

class AppTableSort {
  const AppTableSort({required this.columnIndex, required this.ascending});

  final int columnIndex;
  final bool ascending;
}

class AppTableColumn<T> {
  const AppTableColumn({required this.label, required this.cell, this.width, this.numeric = false, this.sortable = false, this.sortKey});

  /// Right-aligned, rendered through [NumericText] (AUDIT §8 — the only way
  /// a number should render in v2) and sortable by that same value with no
  /// separate `sortKey` to keep in sync.
  AppTableColumn.numeric({required this.label, required num Function(T) value, this.width, this.sortable = false})
    : cell = ((row) => NumericText(value(row))),
      numeric = true,
      sortKey = value;

  final String label;
  final Widget Function(T) cell;

  /// `null` = flexible — absorbs whatever width the fixed columns leave.
  final double? width;
  final bool numeric;
  final bool sortable;
  final Comparable Function(T)? sortKey;
}

/// The one table widget. Consumers: the Insights ranking table, the queue
/// tab, the paired-devices list, the ops job history, and the dependencies
/// tab — all rendered four different ways today.
class AppTable<T> extends StatelessWidget {
  const AppTable({super.key, required this.columns, required this.rows, this.onRowTap, this.sort, this.onSort, this.emptyState});

  final List<AppTableColumn<T>> columns;
  final List<T> rows;
  final void Function(T)? onRowTap;
  final AppTableSort? sort;
  final ValueChanged<AppTableSort>? onSort;
  final Widget? emptyState;

  Widget _wrap(AppTableColumn<T> column, Widget child) {
    final aligned = Align(alignment: column.numeric ? Alignment.centerRight : Alignment.centerLeft, child: child);
    return column.width == null ? Expanded(child: aligned) : SizedBox(width: column.width, child: aligned);
  }

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty && emptyState != null) return emptyState!;

    final theme = Theme.of(context);
    final tokens = theme.tokens;

    Widget headerCell(int index, AppTableColumn<T> column) {
      final active = sort?.columnIndex == index;
      final label = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: column.numeric ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(child: AppText(column.label, role: TextRole.subTitle, ellipsis: true)),
          if (active) ...[
            SizedBox(width: tokens.space.xs),
            Icon(sort!.ascending ? Icons.arrow_upward : Icons.arrow_downward, size: tokens.space.iconSm),
          ],
        ],
      );
      if (!column.sortable || onSort == null) return label;
      return InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: () => onSort!(AppTableSort(columnIndex: index, ascending: active ? !sort!.ascending : true)),
        child: label,
      );
    }

    final headerRow = Container(
      padding: EdgeInsets.symmetric(vertical: tokens.space.sm, horizontal: tokens.space.md),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tokens.surface.border))),
      child: Row(children: [for (var i = 0; i < columns.length; i++) _wrap(columns[i], headerCell(i, columns[i]))]),
    );

    Widget dataRow(T row) {
      final content = Container(
        padding: EdgeInsets.symmetric(vertical: tokens.space.sm, horizontal: tokens.space.md),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tokens.surface.borderSubtle))),
        child: Row(children: [for (final column in columns) _wrap(column, column.cell(row))]),
      );
      return onRowTap == null ? content : InkWell(onTap: () => onRowTap!(row), child: content);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [headerRow, for (final row in rows) dataRow(row)],
    );
  }
}

/// A tiny inline trend line for the Overview bento tiles and the flow
/// pipeline nodes — the last few days of a counter at a glance, no axes. Not
/// `fl_chart`: at ~60×20 it's all overhead a small `CustomPainter` skips.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.cap, this.tone, this.width = 60, this.height = 20});

  final List<num> values;
  final num? cap;
  final StatusKind? tone;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SparklinePainter(values: values, cap: cap, color: tone?.fg(tokens) ?? tokens.accent.primary, capColor: tokens.chart.capLine),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.cap, required this.color, required this.capColor});

  final List<num> values;
  final num? cap;
  final Color color;
  final Color capColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final maxValue = [...values, ?cap].reduce((a, b) => a > b ? a : b).toDouble();
    final minValue = values.reduce((a, b) => a < b ? a : b).toDouble();
    final range = (maxValue - minValue).abs() < 1e-9 ? 1.0 : maxValue - minValue;

    double xAt(int i) => values.length <= 1 ? size.width / 2 : size.width * i / (values.length - 1);
    double yAt(num v) => size.height - ((v - minValue) / range) * size.height;

    if (cap != null) {
      final y = yAt(cap!);
      final capPaint = Paint()
        ..color = capColor
        ..strokeWidth = 1;
      var x = 0.0;
      while (x < size.width) {
        canvas.drawLine(Offset(x, y), Offset((x + 3).clamp(0, size.width), y), capPaint);
        x += 6;
      }
    }

    final path = Path()..moveTo(xAt(0), yAt(values.first));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(xAt(i), yAt(values[i]));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.cap != cap || oldDelegate.color != color;
}
