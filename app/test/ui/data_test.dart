import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ia_control_center/ui/data.dart';

import 'test_harness.dart';

class _Row {
  const _Row(this.name, this.count);
  final String name;
  final int count;
}

void main() {
  group('AppTable', () {
    // The exact D77 regression: with one `width: null` column and the rest
    // fixed, the flexible column must absorb *all* leftover width and the
    // fixed ones must not grow — Material's `DataTable` cannot do this,
    // which is why the ranking table was hand-built in the first place.
    testWidgets('the flexible column absorbs all leftover width; fixed columns never grow', (tester) async {
      final rows = [const _Row('sejjjalll', 2529), const _Row('another_root', 12)];

      await pumpUi(
        tester,
        SizedBox(
          width: 700,
          child: AppTable<_Row>(
            rows: rows,
            columns: [
              AppTableColumn<_Row>(label: 'Entity', cell: (r) => Text(r.name)),
              AppTableColumn<_Row>.numeric(label: 'Scanned', value: (r) => r.count, width: 96),
            ],
          ),
        ),
      );

      final flexible = tester.widget<Expanded>(
        find.ancestor(of: find.text('sejjjalll'), matching: find.byType(Expanded)).first,
      );
      final fixedBox = tester.widget<SizedBox>(
        find.ancestor(of: find.text('2529'), matching: find.byType(SizedBox)).first,
      );
      expect(fixedBox.width, 96);

      final flexibleWidth = tester.getSize(find.ancestor(of: find.text('sejjjalll'), matching: find.byType(Expanded)).first).width;
      // Total 700 minus the table's own horizontal padding minus the fixed
      // 96px column should land in the flexible column — it must be far
      // wider than the fixed column, not an even split.
      expect(flexibleWidth, greaterThan(400));
      expect(flexible.flex, 1);
    });

    testWidgets('tapping a sortable header reports the new sort, toggling direction on the active column', (tester) async {
      AppTableSort? reported;
      await pumpUi(
        tester,
        AppTable<_Row>(
          rows: const [_Row('a', 1)],
          sort: const AppTableSort(columnIndex: 0, ascending: false),
          onSort: (s) => reported = s,
          columns: [AppTableColumn<_Row>.numeric(label: 'Count', value: (r) => r.count, sortable: true, width: 80)],
        ),
      );
      await tester.tap(find.text('Count'));
      expect(reported, isNotNull);
      expect(reported!.columnIndex, 0);
      expect(reported!.ascending, isTrue, reason: 'was descending and active — should flip');
    });

    testWidgets('onRowTap fires with the tapped row', (tester) async {
      _Row? tapped;
      final rows = [const _Row('a', 1), const _Row('b', 2)];
      await pumpUi(
        tester,
        AppTable<_Row>(
          rows: rows,
          onRowTap: (r) => tapped = r,
          columns: [AppTableColumn<_Row>(label: 'Name', cell: (r) => Text(r.name))],
        ),
      );
      await tester.tap(find.text('b'));
      expect(tapped?.name, 'b');
    });

    testWidgets('emptyState renders instead of a zero-row table', (tester) async {
      await pumpUi(
        tester,
        AppTable<_Row>(
          rows: const [],
          emptyState: const Text('nothing here'),
          columns: [AppTableColumn<_Row>(label: 'Name', cell: (r) => Text(r.name))],
        ),
      );
      expect(find.text('nothing here'), findsOneWidget);
      expect(find.text('Name'), findsNothing);
    });
  });

  testWidgets('Sparkline paints without a cap line, and with one', (tester) async {
    await pumpUi(tester, const Sparkline(values: [1, 4, 2, 8, 5]));
    expect(tester.takeException(), isNull);
    await pumpUi(tester, const Sparkline(values: [1, 4, 2, 8, 5], cap: 6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sparkline tolerates a single value and an empty list', (tester) async {
    await pumpUi(tester, const Sparkline(values: [3]));
    expect(tester.takeException(), isNull);
    await pumpUi(tester, const Sparkline(values: []));
    expect(tester.takeException(), isNull);
  });
}
