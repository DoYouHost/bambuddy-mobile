import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

/// Assigning a spool to a slot and taking it back off, on both inventory
/// backends. Both key the write on the slot triple; Spoolman takes a spool off
/// by its id, so the slot is resolved to one first (issue #5).
///
/// The assertions read the requests off an interceptor rather than trusting the
/// mock to match: a stub declared on the wrong method answers with an error
/// carrying no response at all, not a 404, so a route typo can pass unnoticed.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late RequestLog sent;

  setUp(() {
    dio = testDio();
    adapter = mockServer(dio);
    sent = captureRequests(dio);
  });

  group('native backend', () {
    test('assign posts the slot triple under spool_id', () async {
      adapter.onPost(
        '/api/v1/inventory/assignments',
        (s) => s.reply(200, {'id': 7}),
        data: Matchers.any,
      );

      await NativeInventorySource(dio).assignSpool(
        const SpoolAssignmentDraft(
          spoolId: 12,
          printerId: 1,
          amsId: 0,
          trayId: 2,
        ),
      );

      expect(sent.calls, ['POST /api/v1/inventory/assignments']);
      expect(sent.last.data, {
        'spool_id': 12,
        'printer_id': 1,
        'ams_id': 0,
        'tray_id': 2,
      });
    });

    test('a slot the server refuses surfaces as the error, not as success', () {
      adapter.onPost(
        '/api/v1/inventory/assignments',
        (s) => s.reply(409, {'detail': 'Slot already holds a spool'}),
        data: Matchers.any,
      );

      expect(
        () => NativeInventorySource(dio).assignSpool(
          const SpoolAssignmentDraft(
            spoolId: 12,
            printerId: 1,
            amsId: 0,
            trayId: 2,
          ),
        ),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
      );
    });

    test('unassign deletes by the printer, AMS and tray triple', () async {
      adapter.onDelete(
        '/api/v1/inventory/assignments/1/0/2',
        (s) => s.reply(200, {'status': 'ok'}),
      );

      await NativeInventorySource(dio).unassignSpool(1, 0, 2);

      expect(sent.calls, ['DELETE /api/v1/inventory/assignments/1/0/2']);
    });

    // An external spool is addressed as AMS 255 with the tray telling the two
    // sides of the holder apart, so it travels the same route as an AMS tray
    // rather than one of its own.
    test('unassign addresses an external spool as AMS 255', () async {
      adapter.onDelete(
        '/api/v1/inventory/assignments/2/255/1',
        (s) => s.reply(200, {'status': 'ok'}),
      );

      await NativeInventorySource(dio).unassignSpool(2, 255, 1);

      expect(sent.calls, ['DELETE /api/v1/inventory/assignments/2/255/1']);
    });
  });

  group('spoolman backend', () {
    const draft = SpoolAssignmentDraft(
      spoolId: 12,
      printerId: 1,
      amsId: 0,
      trayId: 2,
    );

    test('assign posts the slot triple, needing no tag', () async {
      adapter.onPost(
        '/api/v1/spoolman/inventory/slot-assignments',
        (s) => s.reply(200, {'id': 12}),
        data: Matchers.any,
      );

      await SpoolmanInventorySource(dio).assignSpool(draft);

      // The printer is never asked what the slot reads: a spool without RFID
      // is assigned the same way, as the web dialog does.
      expect(sent.calls, ['POST /api/v1/spoolman/inventory/slot-assignments']);
      expect(sent.last.data, {
        'spoolman_spool_id': 12,
        'printer_id': 1,
        'ams_id': 0,
        'tray_id': 2,
      });
    });

    test('an external spool is addressed as AMS 255', () async {
      adapter.onPost(
        '/api/v1/spoolman/inventory/slot-assignments',
        (s) => s.reply(200, {'id': 12}),
        data: Matchers.any,
      );

      await SpoolmanInventorySource(dio).assignSpool(
        const SpoolAssignmentDraft(
          spoolId: 12,
          printerId: 1,
          amsId: 255,
          trayId: 1,
        ),
      );

      expect(sent.last.data, containsPair('ams_id', 255));
      expect(sent.last.data, containsPair('tray_id', 1));
    });

    test('a slot the server refuses surfaces as the error', () {
      adapter.onPost(
        '/api/v1/spoolman/inventory/slot-assignments',
        (s) => s.reply(404, {'detail': 'Printer not found'}),
        data: Matchers.any,
      );

      expect(
        () => SpoolmanInventorySource(dio).assignSpool(draft),
        throwsA(isA<AppApiException>()),
      );
    });

    test('unassign asks only about the printer it is clearing', () async {
      adapter
        ..onGet(
          '/api/v1/spoolman/inventory/slot-assignments/all',
          (s) => s.reply(200, [
            {
              'spoolman_spool_id': 9,
              'printer_id': 1,
              'ams_id': 0,
              'tray_id': 2,
            },
          ]),
          queryParameters: {'printer_id': 1},
        )
        ..onDelete(
          '/api/v1/spoolman/inventory/slot-assignments/9',
          (s) => s.reply(200, {'id': 9}),
        );

      await SpoolmanInventorySource(dio).unassignSpool(1, 0, 2);

      expect(
        sent.calls.last,
        'DELETE /api/v1/spoolman/inventory/slot-assignments/9',
      );
    });

    // A row whose spool id did not parse arrives as -1, which the route
    // refuses.
    test('a ledger row with an unparseable spool id is left alone', () async {
      adapter.onGet(
        '/api/v1/spoolman/inventory/slot-assignments/all',
        (s) => s.reply(200, [
          {'printer_id': 1, 'ams_id': 0, 'tray_id': 2},
        ]),
      );

      await SpoolmanInventorySource(dio).unassignSpool(1, 0, 2);

      expect(sent.calls, hasLength(1));
    });

    test('unassign removes the spool the slot ledger holds there', () async {
      adapter
        ..onGet(
          '/api/v1/spoolman/inventory/slot-assignments/all',
          (s) => s.reply(200, [
            {
              'spoolman_spool_id': 5,
              'printer_id': 1,
              'ams_id': 0,
              'tray_id': 1,
            },
            {
              'spoolman_spool_id': 9,
              'printer_id': 1,
              'ams_id': 0,
              'tray_id': 2,
            },
          ]),
        )
        ..onDelete(
          '/api/v1/spoolman/inventory/slot-assignments/9',
          (s) => s.reply(200, {'id': 9}),
        );

      await SpoolmanInventorySource(dio).unassignSpool(1, 0, 2);

      expect(sent.calls, [
        'GET /api/v1/spoolman/inventory/slot-assignments/all',
        'DELETE /api/v1/spoolman/inventory/slot-assignments/9',
      ]);
    });

    test('an empty slot removes nothing', () async {
      adapter.onGet(
        '/api/v1/spoolman/inventory/slot-assignments/all',
        (s) => s.reply(200, const []),
      );

      await SpoolmanInventorySource(dio).unassignSpool(1, 0, 3);

      expect(sent.calls, [
        'GET /api/v1/spoolman/inventory/slot-assignments/all',
      ]);
    });
  });
}
