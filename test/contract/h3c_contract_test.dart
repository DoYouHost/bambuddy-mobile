import 'package:bambuddy_mobile/core/ams/filament_mapping.dart';
import 'package:bambuddy_mobile/core/ams/slot_addressing.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';
import 'sent_writes.dart';

/// The H3C (server #3442) as the app reads it: its AMS 3H as unit 32, slots
/// numbered 28-36, and the dryer's own slots and readings.
///
/// The report is the live capture from the server's `test_h3c_ams3h.py`
/// (`FRAME`, firmware 01.01.03.00, mid-print, tray_now "6", slot 7 empty) with
/// its drying zones (`TestDrying.ZONES`). The capture has no `vt_tray`, so the
/// nine external inputs are left to the unit tests rather than invented here.
///
/// A printer of its own, deleted afterwards: the seeded X1C stays as the other
/// files expect it.
void main() {
  group('H3C', skip: brokerSkipReason, () {
    const serial = '00M09A000000032';

    Map<String, Object?> tray(int id, String colour) => {
      'id': '$id',
      'state': 27,
      'tray_type': 'PLA',
      'tray_color': colour,
      'remain': -1,
      'tray_info_idx': 'GFL99',
      'tag_uid': '0000000000000000',
    };

    final report = <String, Object?>{
      'command': 'push_status',
      'ams': {
        'tray_now': '6',
        'tray_pre': '6',
        'tray_tar': '6',
        'tray_exist_bits': '17f0000000',
        'ams_exist_bits': '2000',
        'ams': [
          {
            'id': '32',
            'info': '240842026',
            'dry_info': '1',
            'tray': [
              tray(0, 'DE4343FF'),
              tray(1, 'FFFFFFFF'),
              tray(2, '757575FF'),
              tray(3, '000000FF'),
              tray(4, '0178BFFF'),
              tray(5, 'AE96D4FF'),
              tray(6, 'F7D959FF'),
              {'id': '7', 'state': 160},
              tray(8, '61C680FF'),
            ],
            'zone_info': [
              {
                'zone_id': 0,
                'zone_slots': [5, 7],
                'dry_time': 675,
                'info': '240842026',
                'temp': '55.5',
                'humidity_raw': '25',
              },
              {
                'zone_id': 1,
                'zone_slots': [0, 1, 2, 3, 4, 6, 8],
                'dry_time': 675,
                'info': '240042006',
                'temp': '27.6',
                'humidity_raw': '33',
              },
            ],
          },
        ],
      },
    };

    late Dio dio;
    late int printerId;
    late PrinterStatus status;
    // Whether the server knows the H3C (#3442): it then types the unit.
    late bool knowsH3c;

    setUpAll(() async {
      dio = await authenticatedDio();
      final created = (await dio.post<Map<String, dynamic>>(
        '/api/v1/printers/',
        data: {
          'name': 'Contract H3C',
          'serial_number': serial,
          'ip_address': contractBrokerIp,
          'access_code': '12345678',
          'model': 'H3C',
        },
      )).data!;
      printerId = created['id'] as int;
      final printers = PrintersRepository(dio);

      // Published again on every poll: the server subscribes some time after
      // the printer is created, and a report before that is lost.
      status = await pollUntil(
        'the AMS 3H',
        () async {
          await publishReport(serial, report);
          final s = await printers.fetchStatus(printerId);
          final unit = s?.ams?.where((u) => u.id == 32).firstOrNull;
          return (unit?.trays?.length ?? 0) == 9 ? s : null;
        },
        within: const Duration(seconds: 30),
        every: const Duration(seconds: 2),
      );

      final raw = (await dio.get<Map<String, dynamic>>(
        '/api/v1/printers/$printerId/status',
      )).data!;
      knowsH3c = (raw['ams'] as List)
          .cast<Map<String, dynamic>>()
          .single
          .containsKey('ams_type');
    });

    tearDownAll(() => dio.delete<void>('/api/v1/printers/$printerId'));

    test('the AMS 3H reaches the app numbered as on the web', () {
      final unit = status.ams!.singleWhere((u) => u.id == 32);

      // Unit 32 is the AMS 3H by its id alone, so the name and numbering hold
      // on any server.
      expect(amsUnitName(unit.id!, amsType: unit.amsType), 'AMS 3H');
      expect(status.trayLayout.rack, isTrue);

      if (!knowsH3c) {
        // A server older than the H3C: no type, no dryer, its own tray_now.
        // The app still reads the status, and shows no dryer.
        expect(unit.hasDryer, isFalse);
        markTestSkipped('server predates the H3C (#3442)');
        return;
      }

      expect(unit.amsType, AmsType.zmultiA);
      expect(unit.canDry, isTrue);
      // The ambient zone is the unit's reading, the drying zone the dryer's.
      expect((unit.humidity, unit.temp), (33, 27.6));
      expect(unit.dryerSlots, [5, 7]);
      expect((unit.dryerHumidity, unit.dryerTemp), (25, 55.5));

      // tray_now "6" is the raw slot; the server hands out global 34.
      expect(status.trayNow, 34);
      expect(status.activeTray?.trayColor, 'F7D959FF');
      expect(
        [for (final f in buildLoadedFilaments(status)) f.globalTrayId],
        [28, 29, 30, 31, 32, 33, 34, 36],
        reason: 'slot 7 (35) is empty',
      );
    });

    test('the drying sheet starts the AMS 3H on its drying zone', () async {
      if (!knowsH3c) {
        markTestSkipped('server predates the H3C (#3442)');
        return;
      }
      // Recorded by the card's drying test in printer_card_test.dart.
      final sent = recordedWrites('ams3h_drying_start');
      late List<Response<dynamic>> answers;
      final command = await firstRequest(
        serial,
        () async => answers = await replayWrites(
          dio,
          sent,
          item: printerId,
          itemIn: RegExp(r'(?<=/printers/)\d+'),
        ),
        where: (print) => print['command'] == 'ams_filament_drying',
      );

      expect(answers.single.statusCode, 200, reason: '${answers.single.data}');
      // `send_drying_command`: the firmware's own unit id and the zone that
      // holds two slots, and no spool turning on an AMS 3H.
      expect(command['ams_id'], 32);
      expect(command['zone_id'], 0);
      expect(command['mode'], 1);
      expect(command['rotate_tray'], isFalse);
      final query = sent.single.query!;
      expect(command['temp'], query['temp']);
      expect(command['duration'], query['duration']);
    });
  });
}
