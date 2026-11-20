import 'package:bambuddy_mobile/core/models/plate_list.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_screen.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

class _Queue extends QueueNotifier {
  _Queue(this._items);

  final List<QueueItem> _items;

  @override
  Future<List<QueueItem>> build() async => _items;
}

class _Statuses extends PrinterStatusesNotifier {
  @override
  Map<int, PrinterStatus> build() => {
    1: const PrinterStatus(
      id: 1,
      connected: true,
      ams: [
        AmsUnit(
          id: 0,
          trays: [
            AmsTray(id: 0, state: 11, trayType: 'PETG', trayColor: '0000FFFF'),
            AmsTray(id: 1, state: 9),
          ],
        ),
      ],
    ),
  };
}

/// Slot 1 mapped to A1 (PETG), slot 2 to A2, which the printer reports empty.
final _item = QueueItem.fromJson({
  'id': 7,
  'position': 1,
  'status': 'pending',
  'printer_id': 1,
  'printer_name': 'X1 Carbon',
  'archive_id': 42,
  'archive_name': 'Headphone hanger',
  'ams_mapping': [0, 1],
});

const _plates = PlateList(
  plates: [
    PlateInfo(
      index: 1,
      filaments: [
        (
          type: 'PLA',
          color: '#FF0000',
          slotId: 1,
          usedGrams: 20,
          usedInPlate: true,
        ),
        (
          type: 'PLA',
          color: '#FFFFFF',
          slotId: 2,
          usedGrams: 5,
          usedInPlate: true,
        ),
      ],
    ),
  ],
);

void main() {
  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('a queue row lists its filaments, an empty tray flagged, at '
        'text scale $scale', (tester) async {
      usePhoneWindow(tester);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        ProviderScope(
          retry: neverRetry,
          overrides: [
            queueProvider.overrideWith(() => _Queue([_item])),
            noServerProfileOverride,
            printerStatusesProvider.overrideWith(_Statuses.new),
            plateListProvider.overrideWith((ref, key) async => _plates),
          ],
          child: plApp(const QueueScreen()),
        ),
      );
      await tester.pumpAndSettle();
      // An overflow is a FlutterError, which fails the test on its own.

      expect(find.textContaining('A1 · PETG ·'), findsOneWidget);
      expect(find.textContaining('A2 · ${pl.traySlotEmpty} ·'), findsOneWidget);
    });
  }
}
