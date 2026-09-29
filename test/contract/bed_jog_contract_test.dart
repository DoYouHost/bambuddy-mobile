import 'dart:async';
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
Future<void> _connected(Dio dio, int id) => pollUntil(
  'printer $id to connect to the stand-in broker',
  () async {
    final status = await dio.get<Map<String, dynamic>>(
      '${Endpoints.printers}$id/status',
    );
    return status.data?['connected'] == true ? true : null;
  },
  within: const Duration(seconds: 30),
);

/// The `param` of the first `gcode_line` the server publishes to [serial]
/// while [send] runs. The server publishes other requests on the same topic
/// (pushall and the like), hence the filter.
///
/// `-d` makes mosquitto_sub log its SUBACK to the same stdout the messages
/// arrive on, so one subscription can wait for it before [send] — a jog sent
/// earlier is never delivered. `-W` bounds the process inside the container.
Future<String> _published(String serial, Future<void> Function() send) async {
  final sub = await Process.start('docker', [
    'exec',
    // A TTY, or libc block-buffers the piped debug log and the SUBACK only
    // shows up when the process exits. The image has no `stdbuf`.
    '-t',
    contractBrokerContainer!,
    'mosquitto_sub',
    '-d',
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
    '20',
  ]);
  final subscribed = Completer<void>();
  final gcode = Completer<String>();
  final lines = sub.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        if (line.contains('received SUBACK')) {
          if (!subscribed.isCompleted) subscribed.complete();
          return;
        }
        if (!line.startsWith('{')) return;
        final print = (jsonDecode(line) as Map)['print'];
        if (print is Map &&
            print['command'] == 'gcode_line' &&
            !gcode.isCompleted) {
          gcode.complete(print['param'] as String);
        }
      });
  try {
    await subscribed.future.timeout(const Duration(seconds: 10));
    await send();
    return await gcode.future.timeout(const Duration(seconds: 15));
  } finally {
    await lines.cancel();
    sub.kill();
  }
}
