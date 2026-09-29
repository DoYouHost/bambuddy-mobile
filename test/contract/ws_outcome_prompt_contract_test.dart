import 'dart:async';
import 'dart:io';

import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/api/ws_messages.dart';
import 'package:bambuddy_mobile/core/api/ws_token.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart'
    show wsUrlFor;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// The outcome question as the server actually asks it (#1898): a print ends,
/// and a `print_confirm_request` frame arrives on the socket naming the archive
/// — parsed here by the app's own [parseWsMessage], which is the half no mock
/// can check.
///
/// The print is started "outside Bambuddy" (a report on the stand-in printer,
/// with `confirm_outcome_external_prints` on), because that is the one path to
/// an opted-in print that needs no FTP upload to a real printer.
///
/// **This file moves the seeded printer off its running job**, which the other
/// contract files read. It is named to sort last: the workflow runs the files
/// one at a time, in order, on a container destroyed afterwards.
void main() {
  group('outcome prompt over the socket', skip: brokerSkipReason, () {
    late Dio dio;
    late String serial;
    late bool served;

    setUpAll(() async {
      dio = await authenticatedDio();
      final settings = (await dio.get<Map<String, dynamic>>(
        Endpoints.appSettings,
      )).data!;
      served = settings.containsKey('confirm_outcome_external_prints');
      final printers = (await dio.get<List<dynamic>>(Endpoints.printers)).data!;
      serial = (printers.first as Map)['serial_number'] as String;
    });

    test(
      'a print that asked sends the question, naming its archive',
      () async {
        if (!served) return markTestSkipped('the server predates #1898');
        await dio.put<dynamic>(
          Endpoints.appSettingsUpdate,
          data: {'confirm_outcome_external_prints': true},
        );

        final frames = await _socket(dio);
        addTearDown(frames.close);
        final asked = frames.stream
            .map(parseWsMessage)
            .where((m) => m is WsPrintConfirmRequest)
            .cast<WsPrintConfirmRequest>()
            .first
            .timeout(const Duration(minutes: 3));

        // Off the seeded job first: a print only starts from a printer that
        // is not already running one.
        await publishReport(serial, {
          'gcode_state': 'FINISH',
          'mc_percent': 100,
        });
        await Future<void>.delayed(const Duration(seconds: 3));
        await publishReport(serial, {
          'gcode_state': 'RUNNING',
          'mc_percent': 5,
          'subtask_name': 'outcome-probe.3mf',
          'gcode_file': 'outcome-probe.3mf',
        });
        // The server makes the archive while it handles the start — after
        // trying the printer's FTP for the 3MF, which the stand-in does not
        // serve — and a finish before that finds no archive to ask about.
        final started = await _archiveAsking(dio);
        await publishReport(serial, {
          'gcode_state': 'FINISH',
          'mc_percent': 100,
          'subtask_name': 'outcome-probe.3mf',
          'gcode_file': 'outcome-probe.3mf',
        });

        final request = await asked;
        expect(request.archiveId, started);
        final archive = await ArchiveRepository(dio).byId(request.archiveId);
        expect(archive.confirmRequested, isTrue);
        expect(archive.awaitsVerdict, isTrue);
        expect(archive.printerId, request.printerId);
        expect(request.printName, isNotEmpty);
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );
  });
}

/// The id of the first archive that asks for its outcome, once the server has
/// made one — a started print that opted in.
Future<int> _archiveAsking(Dio dio) => pollUntil(
  'an archive asking for its outcome',
  () async {
    final rows = (await dio.get<List<dynamic>>(Endpoints.archives)).data!;
    for (final row in rows.whereType<Map<String, dynamic>>()) {
      if (row['confirm_requested'] == true) return row['id'] as int;
    }
    return null;
  },
  within: const Duration(minutes: 2),
  every: const Duration(seconds: 2),
);

/// The server's socket, frames as text. Authenticated the way the app does it:
/// a short-lived token in the query, since the upgrade carries no header.
Future<StreamController<String>> _socket(Dio dio) async {
  final token = await WsTokenService(dio).token();
  final url = wsUrlFor(
    contractBaseUrl,
  ).replace(queryParameters: {'token': ?token});
  final socket = await WebSocket.connect(url.toString());
  final frames = StreamController<String>.broadcast(
    onCancel: () => socket.close(),
  );
  socket.listen((data) {
    if (data is String) frames.add(data);
  }, onDone: frames.close);
  return frames;
}
