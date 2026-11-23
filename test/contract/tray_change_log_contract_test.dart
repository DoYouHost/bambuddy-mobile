import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/queue/queue_filaments.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// The trays a running print fed from, as the status route reports them: what
/// a printing queue row's chip follows to the backup spool (`backupTrays`). A
/// printer of its own, so the print it fakes leaves the seeded one alone.
void main() {
  group('tray_change_log', skip: brokerSkipReason, () {
    const serial = '00M09A000000034';
    late Dio dio;
    late int printerId;
    late PrintersRepository printers;

    Map<String, Object?> tray(int id) => {
      'id': '$id',
      'state': 11,
      'tray_type': 'PLA',
      'tray_color': 'DE4343FF',
      'remain': 50,
    };

    Map<String, Object?> frame({required String trayNow, required int layer}) =>
        {
          'command': 'push_status',
          'gcode_state': 'RUNNING',
          'gcode_file': 'contract-backup.gcode',
          'subtask_name': 'contract-backup',
          'mc_percent': 10,
          'layer_num': layer,
          'total_layer_num': 500,
          'ams': {
            'tray_now': trayNow,
            'tray_exist_bits': 'f',
            'ams_exist_bits': '1',
            'ams': [
              {
                'id': '0',
                'humidity': '4',
                'temp': '25.0',
                'tray': [for (var i = 0; i < 4; i++) tray(i)],
              },
            ],
          },
        };

    setUpAll(() async {
      dio = await authenticatedDio();
      final created = (await dio.post<Map<String, dynamic>>(
        '/api/v1/printers/',
        data: {
          'name': 'Contract tray change log',
          'serial_number': serial,
          'ip_address': contractBrokerIp,
          'access_code': '12345678',
          'model': 'X1C',
        },
      )).data!;
      printerId = created['id'] as int;
      printers = PrintersRepository(dio);
    });

    tearDownAll(() => dio.delete<void>('/api/v1/printers/$printerId'));

    test('a spool that runs out mid-print shows as the backup it handed '
        'over to', () async {
      // The print starts on A3, then A3 runs out and A2 takes over.
      final started = await pollUntil(
        'the print to start on A3',
        () async {
          await publishReport(serial, frame(trayNow: '2', layer: 0));
          final s = await printers.fetchStatus(printerId);
          return s?.state == 'RUNNING' && s?.trayNow == 2 ? s : null;
        },
        within: const Duration(seconds: 30),
        every: const Duration(seconds: 2),
      );
      if (started.trayChangeLog == null) {
        markTestSkipped('server predates tray_change_log in the status');
        return;
      }
      // The printer reports the layer before the swap; the server logs a
      // change at the layer it already holds.
      await pollUntil(
        'layer 120 on A3',
        () async {
          await publishReport(serial, frame(trayNow: '2', layer: 120));
          final s = await printers.fetchStatus(printerId);
          return s?.layerNum == 120 ? s : null;
        },
        within: const Duration(seconds: 20),
        every: const Duration(seconds: 2),
      );
      final status = await pollUntil(
        'the hand-over in the log',
        () async {
          await publishReport(serial, frame(trayNow: '1', layer: 120));
          final s = await printers.fetchStatus(printerId);
          return (s?.trayChangeLog?.length ?? 0) >= 2 ? s : null;
        },
        within: const Duration(seconds: 20),
        every: const Duration(seconds: 2),
      );
      final log = status.trayChangeLog!;
      expect(log.first.$1, 2);
      expect(log.last, (1, 120));
      expect(backupTrays([2], log), {2: 1});
    });
  });
}
