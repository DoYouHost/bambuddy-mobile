import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/api/server_version.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';
import 'sent_writes.dart';

/// Loading an AMS-HT slot by its unit id (`ServerFeature.amsHtLoad`): the
/// version row and the server must agree, since the row alone decides whether
/// the card offers Load and Unload on an AMS-HT.
void main() {
  group('AMS-HT load', skip: brokerSkipReason, () {
    // The seeded X1C (`tool/ci/seed_bambuddy.sh`).
    const serial = '00M09A000000001';
    late Dio dio;
    late int printerId;
    late bool supported;

    setUpAll(() async {
      dio = await authenticatedDio();
      final printers = (await dio.get<List<dynamic>>(Endpoints.printers)).data!;
      printerId =
          printers.cast<Map<String, dynamic>>().firstWhere(
                (p) => p['serial_number'] == serial,
              )['id']
              as int;
      supported = (await contractServerVersion()).supports(
        ServerFeature.amsHtLoad,
      );
    });

    test('the card\'s load reaches the printer where the row says yes, '
        'and is refused where it says no', () async {
      // Recorded by the card's AMS-HT test in printer_card_test.dart.
      final sent = recordedWrites('ams_ht_load');
      if (!supported) {
        // The harness's client hands every status back rather than throwing.
        final answers = await replayWrites(
          dio,
          sent,
          item: printerId,
          itemIn: RegExp(r'(?<=/printers/)\d+'),
        );
        expect(
          answers.single.statusCode,
          400,
          reason: '${answers.single.data}',
        );
        return;
      }
      late List<Response<dynamic>> answers;
      final command = await firstRequest(
        serial,
        () async => answers = await replayWrites(
          dio,
          sent,
          item: printerId,
          itemIn: RegExp(r'(?<=/printers/)\d+'),
        ),
        where: (print) => print['command'] == 'ams_change_filament',
      );
      expect(answers.single.statusCode, 200, reason: '${answers.single.data}');
      // `change_filament_wire_ids`: an AMS-HT is its own unit id, slot 0.
      expect(command['ams_id'], 128);
      expect(command['slot_id'], 0);
      expect(command['target'], 128);
    });
  });
}
