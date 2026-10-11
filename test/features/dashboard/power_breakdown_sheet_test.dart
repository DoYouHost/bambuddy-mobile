import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/smart_plug.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/features/dashboard/smart_plugs_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/power_breakdown_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

class _FixedPlugs extends SmartPlugsNotifier {
  _FixedPlugs(this._state);
  final SmartPlugsState _state;
  @override
  SmartPlugsState build() => _state;
}

SmartPlugStatus _watts(double? w) => SmartPlugStatus(
  state: 'ON',
  energy: SmartPlugEnergy(power: w),
);

const _x1 = Printer(id: 1, name: 'X1 Carbon');
const _a1 = Printer(id: 2, name: 'A1 mini');

void main() {
  group('groupPlugsByPrinter', () {
    test('keeps the order printers are given in, unassigned last', () {
      final groups = groupPlugsByPrinter(
        const [
          SmartPlug(id: 10, name: 'Lamp'),
          SmartPlug(id: 11, name: 'X1 plug', printerId: 1),
          SmartPlug(id: 12, name: 'A1 plug', printerId: 2),
          SmartPlug(id: 13, name: 'X1 fan', printerId: 1),
        ],
        const [_x1, _a1],
      );
      expect(groups.map((g) => g.printer?.name), [
        'X1 Carbon',
        'A1 mini',
        null,
      ]);
      expect(groups[0].plugs.map((p) => p.id), [11, 13]);
      expect(groups.last.plugs.single.id, 10);
    });

    test('a plug for an unknown printer counts as unassigned', () {
      final groups = groupPlugsByPrinter(
        const [SmartPlug(id: 1, name: 'Orphan', printerId: 99)],
        const [_x1],
      );
      expect(groups.single.printer, isNull);
    });

    test('keeps disabled plugs', () {
      final groups = groupPlugsByPrinter(
        const [SmartPlug(id: 1, printerId: 1, enabled: false)],
        const [_x1],
      );
      expect(groups.single.plugs.single.id, 1);
    });

    test('no plugs, no groups', () {
      expect(groupPlugsByPrinter(const [], const [_x1]), isEmpty);
    });
  });

  testWidgets('sums a printer\'s plugs and lists them under it', (
    tester,
  ) async {
    await pumpPhone(
      tester,
      const Scaffold(body: PowerBreakdownSheet(printers: [_x1, _a1])),
      overrides: [
        smartPlugsProvider.overrideWith(
          () => _FixedPlugs(
            SmartPlugsState(
              plugs: const [
                SmartPlug(id: 11, name: 'X1 plug', printerId: 1),
                SmartPlug(id: 13, name: 'X1 fan', printerId: 1),
                SmartPlug(id: 12, name: 'A1 plug', printerId: 2),
                SmartPlug(id: 10, name: 'Lamp'),
              ],
              statuses: {
                11: _watts(90),
                13: _watts(5),
                12: _watts(null),
                10: _watts(2),
              },
            ),
          ),
        ),
      ],
    );

    expect(find.text('97\u00A0W'), findsOneWidget); // total
    expect(find.text('95\u00A0W'), findsOneWidget); // X1 group
    expect(find.text('X1 fan'), findsOneWidget);
    expect(find.text('90\u00A0W'), findsOneWidget); // X1 plug inside the group
    // A single plug is named but carries no watts of its own, and its silent
    // reading is a dash on the printer row.
    expect(find.text('A1 plug'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.bySemanticsLabel(pl.plugStateOn), findsNWidgets(4));
    // The bar has a run for X1 and the lamp, none for the silent A1 — in the
    // colours of their tiles (X1 first, A1 second, the lamp third).
    final runs = tester
        .widgetList<ColoredBox>(
          find.byWidgetPredicate(
            (w) => w is ColoredBox && seriesPalette.contains(w.color),
          ),
        )
        .map((b) => b.color);
    expect(runs, [seriesPalette[0], seriesPalette[2]]);
    // And they are drawn: a run with no height passed the colour check above.
    for (final run
        in find
            .byWidgetPredicate(
              (w) => w is ColoredBox && seriesPalette.contains(w.color),
            )
            .evaluate()) {
      expect(tester.getSize(find.byWidget(run.widget)).height, greaterThan(0));
    }
    expect(find.text('Lamp'), findsOneWidget);
  });
}
