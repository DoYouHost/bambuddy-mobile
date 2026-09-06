import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/data/printer_commands_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late PrinterCommandsRepository repo;

  setUp(() {
    dio = testDio();
    adapter = DioAdapter(dio: dio);
    repo = PrinterCommandsRepository(dio);
  });

  test('pause/resume/stop hit the right POST paths', () async {
    adapter
      ..onPost('/api/v1/printers/1/print/pause', (s) => s.reply(200, null))
      ..onPost('/api/v1/printers/1/print/resume', (s) => s.reply(200, null))
      ..onPost('/api/v1/printers/1/print/stop', (s) => s.reply(200, null));

    // No exception thrown = success.
    await repo.pause(1);
    await repo.resume(1);
    await repo.stop(1);
  });

  test('chamber-light sends on=true in the query', () async {
    adapter.onPost(
      '/api/v1/printers/2/chamber-light',
      (s) => s.reply(200, null),
      queryParameters: {'on': true},
    );
    await repo.setChamberLight(2, on: true);
  });

  test('print-speed sends the mode in the query', () async {
    adapter.onPost(
      '/api/v1/printers/3/print-speed',
      (s) => s.reply(200, null),
      queryParameters: {'mode': 3},
    );
    await repo.setPrintSpeed(3, 3);
  });

  test('403 → AuthException(forbidden) — brak can_control_printer', () async {
    adapter.onPost(
      '/api/v1/printers/1/print/pause',
      (s) => s.reply(403, {'detail': 'forbidden'}),
    );
    await expectLater(
      repo.pause(1),
      throwsA(
        isA<AuthException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.forbidden,
        ),
      ),
    );
  });

  test('401 → AuthException(unauthorized), nie mylone z 403', () async {
    adapter.onPost(
      '/api/v1/printers/1/print/stop',
      (s) => s.reply(401, {'detail': 'unauthorized'}),
    );
    await expectLater(
      repo.stop(1),
      throwsA(
        isA<AuthException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.unauthorized,
        ),
      ),
    );
  });

  test('5xx → ApiException(badResponse)', () async {
    adapter.onPost(
      '/api/v1/printers/1/print/resume',
      (s) => s.reply(500, {'detail': 'boom'}),
    );
    await expectLater(repo.resume(1), throwsA(isA<ApiException>()));
  });

  test('refresh-status posts to the printer', () async {
    adapter.onPost(
      '/api/v1/printers/4/refresh-status',
      (s) => s.reply(200, null),
    );
    await repo.refreshStatus(4);
  });

  group('nudgeRepublish', () {
    test('nudges every printer it is given', () async {
      for (final id in [4, 7]) {
        adapter.onPost(
          '/api/v1/printers/$id/refresh-status',
          (s) => s.reply(200, null),
        );
      }
      final sent = captureRequests(dio);

      repo.nudgeRepublish([4, 7]);
      await sent.untilCount(2);

      expect(sent.calls, [
        'POST /api/v1/printers/4/refresh-status',
        'POST /api/v1/printers/7/refresh-status',
      ]);
    });

    test('swallows a refusal instead of raising it into the caller', () async {
      // An offline printer answers 400 and a narrow key can be refused — the
      // republish is a hint, and neither is a reason to fail the action the
      // user actually asked for.
      adapter
        ..onPost(
          '/api/v1/printers/4/refresh-status',
          (s) => s.reply(400, {'detail': 'Printer not connected'}),
        )
        ..onPost(
          '/api/v1/printers/7/refresh-status',
          (s) => s.reply(403, {'detail': 'forbidden'}),
        );

      final sent = captureRequests(dio);

      repo.nudgeRepublish([4, 7]);

      // Nothing thrown here, and nothing left unhandled to fail the test at
      // the end of the microtask queue either.
      await sent.untilCount(2);

      // Asserted explicitly because the swallow eats the adapter's own
      // "no matching route" failure too: without this the test passed with
      // both mocks pointing at paths the app never calls.
      expect(sent.calls, [
        'POST /api/v1/printers/4/refresh-status',
        'POST /api/v1/printers/7/refresh-status',
      ]);
      // And the statuses, or the test only proves that *some* failure is
      // swallowed — not that the refusals it named are. Unordered: the two
      // requests are in flight together, so which answer lands first is not
      // this test's business.
      expect(sent.statuses, unorderedEquals(<int?>[400, 403]));
    });
  });

  test('ams/load leaves the hotend out when none was chosen', () async {
    // "Optional" has to mean absent: a printer without a Filament Track Switch
    // derives the hotend itself, and the server validates the parameter, so a
    // value sent for the sake of sending one is at best noise and at worst a 422.
    adapter.onPost(
      '/api/v1/printers/1/ams/load',
      (s) => s.reply(200, {'success': true}),
      queryParameters: {'tray_id': 6},
    );
    await repo.amsLoad(1, 6);
  });

  test('ams/load names the hotend when one was chosen', () async {
    adapter.onPost(
      '/api/v1/printers/1/ams/load',
      (s) => s.reply(200, {'success': true}),
      queryParameters: {'tray_id': 6, 'extruder_id': 1},
    );
    await repo.amsLoad(1, 6, extruderId: 1);
  });

  test('ams/load sends hotend 0 rather than dropping it as falsy', () async {
    adapter.onPost(
      '/api/v1/printers/1/ams/load',
      (s) => s.reply(200, {'success': true}),
      queryParameters: {'tray_id': 6, 'extruder_id': 0},
    );
    await repo.amsLoad(1, 6, extruderId: 0);
  });

  test('ams/unload takes no slot when none was named', () async {
    adapter.onPost(
      '/api/v1/printers/1/ams/unload',
      (s) => s.reply(200, {'success': true}),
    );
    await repo.amsUnload(1);
  });

  test('ams/unload names the slot when one was given', () async {
    adapter.onPost(
      '/api/v1/printers/1/ams/unload',
      (s) => s.reply(200, {'success': true}),
      queryParameters: {'tray_id': 0},
    );
    await repo.amsUnload(1, trayId: 0);
  });

  test('the RFID re-read addresses the slot locally, in the path', () async {
    adapter.onPost(
      '/api/v1/printers/2/ams/1/slot/3/refresh',
      (s) => s.reply(200, {'success': true}),
    );
    await repo.refreshAmsSlot(2, amsId: 1, slotId: 3);
  });

  group('amsLoadTrayId', () {
    test('numbers an AMS slot as unit * 4 + slot', () {
      expect(amsLoadTrayId(amsId: 0, trayId: 0), 0);
      expect(amsLoadTrayId(amsId: 1, trayId: 2), 6);
      expect(amsLoadTrayId(amsId: 3, trayId: 3), 15);
    });

    test('keeps the A2L AMS-Lite inside the range the server accepts', () {
      // Normalised unit 6 lands on 24..27, which the server allows next to 0..15.
      expect(amsLoadTrayId(amsId: 6, trayId: 0), 24);
      expect(amsLoadTrayId(amsId: 6, trayId: 3), 27);
    });

    test('numbers the external holder by its side, like every other route', () {
      // Ids in are local throughout: Ext-L is side 0 and loads as 254.
      expect(amsLoadTrayId(amsId: 255, trayId: 0), 254);
      expect(amsLoadTrayId(amsId: 255, trayId: 1), 255);
      // The inventory backend has been seen calling the holder 254 too.
      expect(amsLoadTrayId(amsId: 254, trayId: 1), 255);
    });

    test('refuses a holder side that is neither', () {
      // Passing it on would silently address AMS 1 slot 2 instead.
      expect(amsLoadTrayId(amsId: 255, trayId: 5), isNull);
      expect(amsLoadTrayId(amsId: 255, trayId: -1), isNull);
    });

    test('answers null for AMS-HT, which has no number in this encoding', () {
      expect(amsLoadTrayId(amsId: 128, trayId: 0), isNull);
      expect(amsLoadTrayId(amsId: 135, trayId: 0), isNull);
    });

    test('answers null for a unit between the AMS and A2L windows', () {
      // Unit 5 would be 20..23 — inside neither range, so the server 400s.
      expect(amsLoadTrayId(amsId: 5, trayId: 0), isNull);
    });
  });
}
