import 'package:bambuddy_mobile/core/ams/filament_mapping.dart';
import 'package:bambuddy_mobile/core/models/plate_list.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/features/queue/queue_filaments.dart';
import 'package:flutter_test/flutter_test.dart';

QueueItem _item({
  String status = 'pending',
  List<int>? mapping,
  int? plateId,
  List<Map<String, dynamic>>? overrides,
  String? colour,
}) => QueueItem.fromJson({
  'id': 1,
  'position': 1,
  'status': status,
  'printer_id': 1,
  'ams_mapping': ?mapping,
  'plate_id': ?plateId,
  'filament_overrides': ?overrides,
  'filament_color': ?colour,
  'filament_type': 'PLA',
});

PlateFilament _slot(int id, {double grams = 10, bool used = true}) => (
  type: 'PLA',
  color: '#FF0000',
  slotId: id,
  usedGrams: grams,
  usedInPlate: used,
);

PlateInfo _plate(int index, List<PlateFilament> filaments) =>
    PlateInfo(index: index, filaments: filaments);

/// AMS 0: slot 1 PETG blue, slot 2 empty, slot 3 a spool nobody named.
PrinterStatus _status({bool connected = true}) => PrinterStatus(
  id: 1,
  connected: connected,
  ams: [
    AmsUnit(
      id: 0,
      trays: [
        AmsTray(id: 0, state: 11, trayType: 'PETG', trayColor: '0000FFFF'),
        AmsTray(id: 1, state: 9),
        AmsTray(id: 2, exists: true),
      ],
    ),
  ],
);

void main() {
  final status = _status();
  final loaded = buildLoadedFilaments(status);

  test('the chosen plate decides the slots; unused ones are left out', () {
    final out = resolveQueueFilaments(
      _item(plateId: 2),
      [
        _plate(1, [_slot(1)]),
        _plate(2, [_slot(1), _slot(2, grams: 0), _slot(3, used: false)]),
      ],
      const [],
      null,
    );
    expect(out.map((f) => f.slotId), [1]);
    expect(out.single.slotLabel, isNull);
  });

  test('an override replaces only its own slot', () {
    final out = resolveQueueFilaments(
      _item(
        overrides: [
          {'slot_id': 2, 'type': 'PETG', 'color': '#00FF00'},
        ],
      ),
      [
        _plate(1, [_slot(1), _slot(2)]),
      ],
      const [],
      null,
    );
    expect(
      [for (final f in out) (f.type, f.color)],
      [('PLA', '#FF0000'), ('PETG', '#00FF00')],
    );
  });

  test('a mapped tray shows what it holds and where it is', () {
    final out = resolveQueueFilaments(
      _item(mapping: [0]),
      [
        _plate(1, [_slot(1)]),
      ],
      loaded,
      status,
    );
    expect(out.single.slotLabel, 'A1');
    expect(out.single.type, 'PETG');
    expect(out.single.emptySlot, isFalse);
  });

  test('a mapped tray the printer reports empty is named and flagged', () {
    final out = resolveQueueFilaments(
      _item(mapping: [1]),
      [
        _plate(1, [_slot(1)]),
      ],
      loaded,
      status,
    );
    expect(out.single.slotLabel, 'A2');
    expect(out.single.emptySlot, isTrue);
    expect(out.single.type, 'PLA', reason: 'the planned filament stays');
  });

  test('an unnamed spool, an offline printer or no mapping flag nothing', () {
    for (final (mapping, s) in [
      ([2], status),
      ([1], _status(connected: false)),
      ([-1], status),
    ]) {
      final f = resolveQueueFilaments(
        _item(mapping: mapping),
        [
          _plate(1, [_slot(1)]),
        ],
        buildLoadedFilaments(s),
        s,
      ).single;
      expect((f.slotLabel, f.emptySlot), (null, false), reason: '$mapping');
    }
  });

  test('without plates the overrides, then the item colour, then nothing', () {
    expect(
      resolveQueueFilaments(
        _item(
          overrides: [
            {'slot_id': 3, 'type': 'TPU', 'color': '#111111'},
          ],
        ),
        const [],
        const [],
        null,
      ).single.slotId,
      3,
    );
    final fallback = resolveQueueFilaments(
      _item(colour: '#ABCDEF'),
      const [],
      const [],
      null,
    ).single;
    expect((fallback.type, fallback.color), ('PLA', '#ABCDEF'));
    expect(resolveQueueFilaments(_item(), const [], const [], null), isEmpty);
  });

  group('backupTrays (the web\'s cases)', () {
    test('a mapped tray that ran out hands over to the next one logged', () {
      expect(backupTrays([2], [(2, 0), (1, 350)]), {2: 1});
    });

    test('a backup that ran out in turn is followed', () {
      expect(backupTrays([2], [(2, 0), (1, 120), (0, 400)]), {2: 0});
    });

    test(
      'a change to another mapped tray is a colour change, not a backup',
      () {
        expect(backupTrays([2, 1], [(2, 0), (1, 30)]), isEmpty);
      },
    );

    test('nothing logged or nothing mapped is no backup', () {
      expect(backupTrays([2], null), isEmpty);
      expect(backupTrays(null, [(2, 0), (1, 5)]), isEmpty);
      expect(backupTrays([-1], [(2, 0), (1, 5)]), isEmpty);
    });
  });

  group('the chip of a printing job', () {
    // A2 is empty: its spool ran out and A1 took over.
    final printing = PrinterStatus(
      id: 1,
      connected: true,
      ams: status.ams,
      trayChangeLog: const [(1, 0), (0, 350)],
    );
    final plates = [
      _plate(1, [_slot(1)]),
    ];

    test('shows the backup the printer switched to', () {
      final f = resolveQueueFilaments(
        _item(status: 'printing', mapping: [1]),
        plates,
        buildLoadedFilaments(printing),
        printing,
      ).single;
      expect((f.slotLabel, f.type, f.emptySlot), ('A1', 'PETG', false));
    });

    test('a queued job keeps pointing at its own mapped tray', () {
      // The log belongs to whatever the printer prints now, not this job.
      final f = resolveQueueFilaments(
        _item(mapping: [1]),
        plates,
        buildLoadedFilaments(printing),
        printing,
      ).single;
      expect((f.slotLabel, f.emptySlot), ('A2', true));
    });
  });
}
