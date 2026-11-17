import 'dart:convert';

import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/panda_breath.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';
import 'sent_writes.dart';

/// The BIQU Panda Breath (#1466): the heater's state on a printer's status,
/// and the commands the card's sheet sends (`sent/panda_breath.json`), on
/// both server generations. A server before #1466 sends no `panda_breath` key
/// and has no route, and the card shows nothing.
///
/// The heater is played by the stand-in broker: the server follows it on the
/// broker of its MQTT relay settings, which this test points at that broker
/// for its run and puts back after.
void main() {
  late Dio dio;
  late int printerId;
  late String serial;
  late bool hasField;

  setUpAll(() async {
    if (contractSkipReason != null) return;
    dio = await authenticatedDio();
    final printers = (await dio.get<List<dynamic>>(Endpoints.printers)).data!;
    final first = printers.first as Map<String, dynamic>;
    printerId = first['id'] as int;
    serial = first['serial_number'] as String;
    final raw = (await dio.get<Map<String, dynamic>>(
      Endpoints.printerStatus(printerId),
    )).data!;
    hasField = raw.containsKey('panda_breath');
  });

  Future<PrinterStatus> status() async => PrinterStatus.fromJson(
    (await dio.get<Map<String, dynamic>>(
      Endpoints.printerStatus(printerId),
    )).data!,
  );

  group('without a heater', skip: contractSkipReason, () {
    test('the status carries none, on either generation', () async {
      expect((await status()).pandaBreath, isNull);
    });

    test('the sheet\'s writes pass validation and find no heater', () async {
      final answers = await replayWrites(
        dio,
        recordedWrites('panda_breath'),
        item: printerId,
      );
      for (final answer in answers) {
        // A 400 or 422 would mean the body is wrong. A newer server answers
        // 404 for the missing heater; an older one has no route, and a sibling
        // `/printers/{id}/…` route makes that a 405.
        if (hasField) {
          expect(answer.statusCode, 404, reason: '${answer.data}');
          expect('${answer.data}', contains('No Panda Breath'));
        } else {
          expect(answer.statusCode, anyOf(404, 405), reason: '${answer.data}');
        }
      }
    });
  });

  group('with a heater on the broker', skip: brokerSkipReason, () {
    const device = 'pb-contract';
    const relayKeys = [
      'mqtt_enabled',
      'mqtt_broker',
      'mqtt_port',
      'mqtt_use_tls',
      'panda_breath_enabled',
    ];
    Map<String, dynamic>? before;

    setUpAll(() async {
      if (!hasField) return;
      final settings = (await dio.get<Map<String, dynamic>>(
        Endpoints.appSettings,
      )).data!;
      before = {for (final k in relayKeys) k: settings[k]};
      await dio.patch<dynamic>(
        Endpoints.appSettings,
        data: {
          'mqtt_enabled': true,
          'mqtt_broker': contractBrokerIp,
          'mqtt_port': 8883,
          'mqtt_use_tls': true,
          'panda_breath_enabled': true,
        },
      );
      // Retained, as the firmware publishes it: the server subscribes after
      // it connects. `work_on` and `drying_running` are "ON"/"OFF" on the wire.
      await publishTopic(
        'panda_breath/$device/state',
        jsonEncode({
          'printer_sn': serial,
          'chamber_temp': 41.5,
          'target_temp': 45,
          'work_on': 'ON',
          'mode': 'filament drying',
          'drying_running': 'ON',
          'drying_remaining_min': 95,
        }),
        retain: true,
      );
      await publishTopic(
        'panda_breath/$device/availability',
        'online',
        retain: true,
      );
    });

    tearDownAll(() async {
      if (before == null) return;
      await publishTopic('panda_breath/$device/state', '', retain: true);
      await publishTopic('panda_breath/$device/availability', '', retain: true);
      await dio.patch<dynamic>(Endpoints.appSettings, data: before);
    });

    Future<PandaBreathState> heater() => pollUntil(
      'the heater on the printer status',
      () async => (await status()).pandaBreath,
      within: const Duration(seconds: 30),
      every: const Duration(milliseconds: 500),
    );

    test('reaches the printer\'s status as the card reads it', () async {
      if (!hasField) return markTestSkipped('server before #1466');
      final p = await heater();
      expect(p.deviceId, device);
      expect(p.online, isTrue);
      expect(p.chamberTemp, 41.5);
      expect(p.targetTemp, 45);
      expect(p.workOn, isTrue);
      expect(p.knownMode, PandaBreathMode.drying);
      expect(p.dryingRunning, isTrue);
      expect(p.dryingRemainingMin, 95);
    });

    test('each recorded write reaches the heater as one command', () async {
      if (!hasField) return markTestSkipped('server before #1466');
      await heater();
      final expected = [
        {'work_on': 'OFF'},
        {'mode': 'filament drying'},
        {'target_temp': 46},
      ];
      final writes = recordedWrites('panda_breath');
      expect(writes, hasLength(expected.length));
      for (var i = 0; i < writes.length; i++) {
        late Response<dynamic> answer;
        final command = await firstMessage(
          'panda_breath/$device/command',
          () async => answer = (await replayWrites(dio, [
            writes[i],
          ], item: printerId)).single,
          where: (_) => true,
        );
        expect(answer.statusCode, 200, reason: '${answer.data}');
        expect(command, expected[i]);
      }
    });

    test('a heater that says offline is shown offline', () async {
      if (!hasField) return markTestSkipped('server before #1466');
      await heater();
      await publishTopic(
        'panda_breath/$device/availability',
        'offline',
        retain: true,
      );
      final offline = await pollUntil(
        'the heater offline',
        () async {
          final p = (await status()).pandaBreath;
          return p != null && !p.usable ? p : null;
        },
        within: const Duration(seconds: 30),
        every: const Duration(milliseconds: 500),
      );
      expect(offline.online, isFalse);
      await publishTopic(
        'panda_breath/$device/availability',
        'online',
        retain: true,
      );
    });
  });
}
