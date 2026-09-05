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
    test('assign refuses loudly and sends nothing', () async {
      await expectLater(
        SpoolmanInventorySource(dio).assignSpool(
          const SpoolAssignmentDraft(
            spoolId: 12,
            printerId: 1,
            amsId: 0,
            trayId: 2,
          ),
        ),
        throwsUnsupportedError,
      );

      expect(calls, isEmpty);
    });

    test('unassign refuses loudly and sends nothing', () async {
      await expectLater(
        SpoolmanInventorySource(dio).unassignSpool(1, 0, 2),
        throwsUnsupportedError,
      );

      expect(calls, isEmpty);
    });
  });
}
