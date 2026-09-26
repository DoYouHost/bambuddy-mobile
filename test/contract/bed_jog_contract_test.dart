import 'dart:convert';
import 'dart:io';

import 'package:bambuddy_mobile/core/api/api_client.dart';
import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/printers/bed_jog.dart';
import 'package:bambuddy_mobile/data/printer_commands_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// The sign an arrow ends up as in the G-code the server sends the printer —
/// what bambuddy #1334 got wrong, and what no mocked transport can see. Read
/// straight off the stand-in printer's broker.
void main() {
  group('bed-jog contract', skip: brokerSkipReason, () {
    late Dio dio;
    late PrinterCommandsRepository commands;
    late BedJogConvention convention;
    final added = <int>[];

    setUpAll(() async {
      dio = await authenticatedDio();
      commands = PrinterCommandsRepository(dio);
      // Resolved the way bedJogConventionProvider does it.
      convention = bedJogConventionFor(
        await ServerVersionService(dio).current(),
      );
      if (convention == BedJogConvention.unknown) {
        convention = bedJogConventionFromOpenApi(await commands.fetchOpenApi());
      }
    });

    tearDownAll(() async {
      for (final id in added) {
        await dio.delete<Object>('${Endpoints.printers}$id');
      }
    });

    test(
      '/openapi.json answers without credentials and names the route',
      () async {
        final bare = createBareDio()..options.baseUrl = contractBaseUrl;
        final res = await bare.get<Object>(Endpoints.openApi);
        expect(
          bedJogConventionFromOpenApi(res.data),
          isNot(BedJogConvention.unknown),
        );
      },
    );

    test(
      'the schema and the version table agree wherever both answer',
      () async {
        final version = await ServerVersionService(dio).current();
        final byVersion = bedJogConventionFor(version);
        if (byVersion == BedJogConvention.unknown) return;
        expect(
          bedJogConventionFromOpenApi(await commands.fetchOpenApi()),
          byVersion,
          reason: 'server ${version?.raw}',
        );
      },
    );

    Future<String> gcodeFor(
      String serial,
      int printerId,
      bool up,
      String model,
    ) async {
      final distance = bedJogDistance(
        up: up,
        step: 10,
        model: model,
        convention: convention,
      );
      expect(distance, isNotNull, reason: 'convention: $convention');
      return _published(serial, () => commands.bedJog(printerId, distance!));
    }

    test('A1 mini: up lifts the toolhead, i.e. opens the gap', () async {
      const serial = '00M09A000000002';
      final res = await dio.post<Map<String, dynamic>>(
        Endpoints.printers,
        data: {
          'name': 'Contract A1 mini',
          'serial_number': serial,
          'ip_address': contractBrokerIp,
          'access_code': '12345678',
          'model': 'A1 mini',
        },
      );
      final id = res.data!['id'] as int;
      added.add(id);
      await _connected(dio, id);

      expect(
        await gcodeFor(serial, id, true, 'A1 mini'),
        contains('G1 Z10.00'),
      );
      expect(
        await gcodeFor(serial, id, false, 'A1 mini'),
        contains('G1 Z-10.00'),
      );
    });

    test('X1C: up raises the plate, i.e. closes the gap', () async {
      // The seeded printer (tool/ci/seed_bambuddy.sh).
      const serial = '00M09A000000001';
      final list = (await dio.get<List<dynamic>>(Endpoints.printers)).data!;
      final x1c = list.cast<Map<String, dynamic>>().firstWhere(
        (p) => p['serial_number'] == serial,
      );

      expect(
        await gcodeFor(serial, x1c['id'] as int, true, 'X1C'),
        contains('G1 Z-10.00'),
      );
    });
  });
}

/// Waits until the server holds an MQTT session to the new printer — a jog
/// before that is a 400 "Printer not connected".
Future<void> _connected(Dio dio, int id) async {
  for (var i = 0; i < 30; i++) {
    final status = await dio.get<Map<String, dynamic>>(
      '${Endpoints.printers}$id/status',
    );
    if (status.data?['connected'] == true) return;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  fail('printer $id never connected to the stand-in broker');
}

/// The `param` of the first `gcode_line` the server publishes to [serial]
/// while [send] runs. The server publishes other requests on the same topic
/// (pushall and the like), hence the filter.
Future<String> _published(String serial, Future<void> Function() send) async {
  final sub = await Process.start('docker', [
    'exec',
    contractBrokerContainer!,
    'mosquitto_sub',
    '-h',
    'localhost',
    '-p',
    '8883',
    '--insecure',
    '--cafile',
    '/mosquitto/certs/server.crt',
    '-t',
    'device/$serial/request',
    '-W',
    '15',
  ]);
  try {
    final gcode = sub.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .map((line) => (jsonDecode(line) as Map)['print'])
        .where((p) => p is Map && p['command'] == 'gcode_line')
        .map((p) => (p as Map)['param'] as String)
        .first;
    // mosquitto_sub has no "subscribed" signal; a jog sent before the
    // subscription lands is simply never seen, and the -W timeout reports it.
    await Future<void>.delayed(const Duration(seconds: 1));
    await send();
    return await gcode.timeout(const Duration(seconds: 15));
  } finally {
    sub.kill();
  }
}
