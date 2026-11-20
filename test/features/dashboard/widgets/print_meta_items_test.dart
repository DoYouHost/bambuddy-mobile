import 'package:bambuddy_mobile/core/format/datetime_format.dart';
import 'package:bambuddy_mobile/core/format/duration_format.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/print_meta_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers.dart';

PrinterStatus _status({int? remaining, int? layer, int? total}) =>
    PrinterStatus(
      id: 1,
      remainingTime: remaining,
      layerNum: layer,
      totalLayers: total,
    );

/// Builds the items inside a Polish app, where `DateTimeFormats.of` has a tree.
Future<List<PrintMetaItem>> _time(WidgetTester tester, PrinterStatus s) async {
  late List<PrintMetaItem> items;
  late String eta;
  await tester.pumpWidget(
    plApp(
      Builder(
        builder: (context) {
          items = timeMetaItems(context, pl, s);
          eta = pl.eta(
            etaClock(DateTimeFormats.of(context), s.remainingTime ?? 0),
          );
          return const SizedBox();
        },
      ),
    ),
  );
  if (items.isNotEmpty) expect(items.last.text, eta);
  return items;
}

void main() {
  group('timeMetaItems', () {
    testWidgets('a remaining time gives the remaining and the finish time', (
      tester,
    ) async {
      final items = await _time(tester, _status(remaining: 52));
      expect(items.map((i) => i.icon), [Icons.schedule, Icons.flag_outlined]);
      expect(items.first.text, pl.remaining(formatMinutes(pl, 52)));
    });

    testWidgets('one minute is still a remaining time', (tester) async {
      expect(await _time(tester, _status(remaining: 1)), hasLength(2));
    });

    for (final remaining in <int?>[null, 0, -5]) {
      testWidgets('$remaining is "unknown": no items', (tester) async {
        expect(await _time(tester, _status(remaining: remaining)), isEmpty);
      });
    }
  });

  group('layerMetaItem', () {
    test('both figures give layer/total', () {
      final item = layerMetaItem(_status(layer: 113, total: 264))!;
      expect(item.text, '113/264');
      expect(item.icon, Icons.layers_outlined);
    });

    test('layer 0 of a known total is still shown', () {
      expect(layerMetaItem(_status(layer: 0, total: 264))!.text, '0/264');
    });

    test('a missing figure gives nothing', () {
      expect(layerMetaItem(_status(layer: 3)), isNull);
      expect(layerMetaItem(_status(total: 264)), isNull);
      expect(layerMetaItem(_status()), isNull);
    });
  });
}
