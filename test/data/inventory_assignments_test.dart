import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

/// Assigning a spool to a slot and taking it back off, on both inventory
/// backends. Only the native one writes here; Spoolman refuses by design, and
/// that refusal is pinned so it cannot decay into a silent no-op — which is
/// what "assigning does nothing" looked like from the outside (issue #5).
///
/// The assertions read the requests off an interceptor rather than trusting the
/// mock to match: a stub declared on the wrong method answers with an error
/// carrying no response at all, not a 404, so a route typo can pass unnoticed.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late List<String> calls;
  late List<Object?> bodies;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    calls = [];
    bodies = [];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      calls.add('${o.method} ${o.path}');
      bodies.add(o.data);
      h.next(o);
    }));
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

      expect(calls, ['POST /api/v1/inventory/assignments']);
      expect(bodies.single, {
        'spool_id': 12,
        'printer_id': 1,
        'ams_id': 0,
        'tray_id': 2,
      });
    });

    test('a slot the server refuses surfaces as the error, not as success',
        () {
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

      expect(calls, ['DELETE /api/v1/inventory/assignments/1/0/2']);
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

      expect(calls, ['DELETE /api/v1/inventory/assignments/2/255/1']);
    });
  });

  group('spoolman backend', () {
    const draft = SpoolAssignmentDraft(
      spoolId: 12,
      printerId: 1,
      amsId: 0,
      trayId: 2,
    );

    /// A status whose AMS 0 holds one tray at slot 2, carrying whichever half
    /// of the RFID identity the test is about.
    void printerStatusWith({String? trayUuid, String? tagUid}) {
      adapter.onGet(
        '/api/v1/printers/1/status',
        (s) => s.reply(200, {
          'id': 1,
          'ams': [
            {
              'id': 0,
              'tray': [
                {'id': 2, 'tray_uuid': trayUuid, 'tag_uid': tagUid},
              ],
            },
          ],
        }),
      );
    }

    test('links the spool to the tag the slot reads, carrying the triple',
        () async {
      printerStatusWith(trayUuid: '0123456789ABCDEF0123456789ABCDEF');
      adapter.onPost(
        '/api/v1/spoolman/spools/12/link',
        (s) => s.reply(200, {'success': true}),
        data: Matchers.any,
      );

      await SpoolmanInventorySource(dio).assignSpool(draft);

      expect(calls, [
        'GET /api/v1/printers/1/status',
        'POST /api/v1/spoolman/spools/12/link',
      ]);
      expect(bodies.last, {
        'tray_uuid': '0123456789ABCDEF0123456789ABCDEF',
        'printer_id': 1,
        'ams_id': 0,
        'tray_id': 2,
      });
    });

    // Only the UUID survives a re-spool, so it wins wherever both are present —
    // the same precedence the server applies when matching a spool by tag.
    test('prefers the tray UUID when the slot reports both', () async {
      printerStatusWith(
        trayUuid: '0123456789ABCDEF0123456789ABCDEF',
        tagUid: 'FEDCBA9876543210',
      );
      adapter.onPost(
        '/api/v1/spoolman/spools/12/link',
        (s) => s.reply(200, {'success': true}),
        data: Matchers.any,
      );

      await SpoolmanInventorySource(dio).assignSpool(draft);

      expect(
        bodies.last,
        containsPair('tray_uuid', '0123456789ABCDEF0123456789ABCDEF'),
      );
      expect(bodies.last, isNot(contains('tag_uid')));
    });

    test('falls back to the tag UID when there is no UUID', () async {
      printerStatusWith(tagUid: 'FEDCBA9876543210');
      adapter.onPost(
        '/api/v1/spoolman/spools/12/link',
        (s) => s.reply(200, {'success': true}),
        data: Matchers.any,
      );

      await SpoolmanInventorySource(dio).assignSpool(draft);

      expect(bodies.last, containsPair('tag_uid', 'FEDCBA9876543210'));
    });

    test('an external spool is read off vt_tray by its global id', () async {
      adapter
        ..onGet(
          '/api/v1/printers/1/status',
          (s) => s.reply(200, {
            'id': 1,
            'vt_tray': [
              {'id': 254, 'tray_uuid': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'},
              {'id': 255, 'tray_uuid': 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'},
            ],
          }),
        )
        ..onPost(
          '/api/v1/spoolman/spools/12/link',
          (s) => s.reply(200, {'success': true}),
          data: Matchers.any,
        );

      // Ext-R: local (255, 1), global 255.
      await SpoolmanInventorySource(dio).assignSpool(
        const SpoolAssignmentDraft(
          spoolId: 12,
          printerId: 1,
          amsId: 255,
          trayId: 1,
        ),
      );

      expect(
        bodies.last,
        containsPair('tray_uuid', 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'),
      );
    });

    // A bare 400 from the server would reach the user as "error 400". The slot
    // is checked here so the refusal can say what is actually wrong with it.
    test('a slot with no readable tag is refused before anything is written',
        () async {
      printerStatusWith();

      await expectLater(
        SpoolmanInventorySource(dio).assignSpool(draft),
        throwsA(isA<ApiException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.slotTagUnreadable,
        )),
      );

      expect(calls, ['GET /api/v1/printers/1/status']);
    });

    test('unassign unlinks the spool the slot ledger holds there', () async {
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
        ..onPost(
          '/api/v1/spoolman/spools/9/unlink',
          (s) => s.reply(200, {'success': true}),
        );

      await SpoolmanInventorySource(dio).unassignSpool(1, 0, 2);

      expect(calls, [
        'GET /api/v1/spoolman/inventory/slot-assignments/all',
        'POST /api/v1/spoolman/spools/9/unlink',
      ]);
    });

    test('an empty slot unlinks nothing', () async {
      adapter.onGet(
        '/api/v1/spoolman/inventory/slot-assignments/all',
        (s) => s.reply(200, const []),
      );

      await SpoolmanInventorySource(dio).unassignSpool(1, 0, 3);

      expect(calls, ['GET /api/v1/spoolman/inventory/slot-assignments/all']);
    });
  });
}
