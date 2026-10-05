import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// The Filament Track Switch as the mapping sees it: a switch reported by the
/// printer, and the inlet each AMS is plumbed into, which the same-inlet
/// warning reads (`FilamentMapping.tsx::sameInletWarning`).
///
/// Named `ws_…` to run last: a switch, once reported, stays installed on the
/// server until it restarts — no report can take it away again.
void main() {
  group('Filament Track Switch inlets', skip: brokerSkipReason, () {
    test('a reported switch and AMS info give the unit its inlet', () async {
      final dio = await authenticatedDio();
      final printers = PrintersRepository(dio);
      final first =
          (await dio.get<List<dynamic>>('/api/v1/printers/')).data!.first
              as Map<String, dynamic>;
      final printerId = first['id'] as int;
      final serial = first['serial_number'] as String;

      // `ams[].info` bits 8-11 = 0xE (behind the switch), bits 24-27 = 1
      // (inlet A) — `bambu_mqtt.py`, the AMS info decode.
      await publishReport(serial, {
        'device': {
          'fila_switch': {'in': [], 'out': [], 'stat': 0, 'info': 0},
        },
        'ams': {
          'ams': [
            {
              'id': 0,
              'info': '01000E00',
              'tray': [
                {
                  'id': 0,
                  'tray_type': 'PLA',
                  'tray_color': 'FF0000FF',
                  'tray_info_idx': 'GFL99',
                },
                {
                  'id': 1,
                  'tray_type': 'PLA',
                  'tray_color': '00FF00FF',
                  'tray_info_idx': 'GFL99',
                },
              ],
            },
          ],
          'ams_exist_bits': '1',
        },
      });

      final status = await pollUntil('the switch inlet', () async {
        final s = await printers.fetchStatus(printerId);
        return (s?.filaSwitch?.installed ?? false) &&
                s?.amsSwitchInlet?[0] != null
            ? s
            : null;
      }, within: const Duration(seconds: 20));

      expect(status.amsSwitchInlet?[0], 'A');
    });
  });
}
