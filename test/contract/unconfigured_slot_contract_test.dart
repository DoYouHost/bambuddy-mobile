import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// A slot that holds a spool the printer cannot name (#2527) against one that
/// is empty: what `AmsTray.emptyKind` reads off the status route. A printer of
/// its own, so the report leaves the seeded one alone.
void main() {
  group('unconfigured AMS slot', skip: brokerSkipReason, () {
    const serial = '00M09A000000033';
    late Dio dio;
    late int printerId;
    late PrinterStatus status;

    // Slot 1 named, slot 2 blank but present (bit 1 set), slot 3 blank and
    // absent; states as a firmware without the bitmask would say it.
    final report = <String, Object?>{
      'command': 'push_status',
      'ams': {
        'tray_now': '255',
        'tray_exist_bits': '3',
        'ams_exist_bits': '1',
        'ams': [
          {
            'id': '0',
            'humidity': '4',
            'temp': '25.0',
            'tray': [
              {
                'id': '0',
                'state': 11,
                'tray_type': 'PLA',
                'tray_color': 'DE4343FF',
                'remain': 80,
              },
              {'id': '1', 'state': 11},
              {'id': '2', 'state': 9},
            ],
          },
        ],
      },
    };

    setUpAll(() async {
      dio = await authenticatedDio();
      final created = (await dio.post<Map<String, dynamic>>(
        '/api/v1/printers/',
        data: {
          'name': 'Contract unconfigured slot',
          'serial_number': serial,
          'ip_address': contractBrokerIp,
          'access_code': '12345678',
          'model': 'X1C',
        },
      )).data!;
      printerId = created['id'] as int;
      final printers = PrintersRepository(dio);
      // Published on every poll: a report before the server subscribes is lost.
      status = await pollUntil(
        'the AMS',
        () async {
          await publishReport(serial, report);
          final s = await printers.fetchStatus(printerId);
          return (s?.ams?.firstOrNull?.trays?.length ?? 0) == 3 ? s : null;
        },
        within: const Duration(seconds: 30),
        every: const Duration(seconds: 2),
      );
    });

    tearDownAll(() => dio.delete<void>('/api/v1/printers/$printerId'));

    test('a present blank spool reads unconfigured, an absent one empty', () {
      final trays = status.ams!.single.trays!;
      expect(trays[0].emptyKind, isNull);
      expect(trays[1].emptyKind, EmptySlotKind.unconfigured);
      expect(trays[2].emptyKind, EmptySlotKind.empty);
    });
  });
}
