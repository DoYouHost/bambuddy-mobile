import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

/// `POST …/spools/from-slot` on both inventory backends. They differ in more
/// than the path: the native route answers with the spool, Spoolman with
/// `{success, spool_id}`, and only the caller's id survives either way.
void main() {
  late Dio dio;
  late DioAdapter adapter;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
  });

  Object? capturedBody;
  void captureBody() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          capturedBody = o.data;
          h.next(o);
        },
      ),
    );
  }

  group('native backend', () {
    test('sends the slot triple and reads the new spool id', () async {
      adapter.onPost(
        '/api/v1/inventory/spools/from-slot',
        (s) => s.reply(200, {'id': 42, 'material': 'PLA'}),
        data: Matchers.any,
      );
      captureBody();

      final id = await NativeInventorySource(
        dio,
      ).createSpoolFromSlot(printerId: 3, amsId: 1, trayId: 2);

      expect(id, 42);
      expect(capturedBody, {'printer_id': 3, 'ams_id': 1, 'tray_id': 2});
    });

    test('a slot without a readable tag surfaces as the server 400', () {
      adapter.onPost(
        '/api/v1/inventory/spools/from-slot',
        (s) => s.reply(400, {'detail': 'Slot has no RFID tag'}),
        data: Matchers.any,
      );

      expect(
        () => NativeInventorySource(
          dio,
        ).createSpoolFromSlot(printerId: 1, amsId: 0, trayId: 0),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 400)),
      );
    });

    test('a 404 keeps its detail, so a missing route reads apart from an '
        'offline printer', () async {
      adapter.onPost(
        '/api/v1/inventory/spools/from-slot',
        (s) => s.reply(404, {'detail': 'Not Found'}),
        data: Matchers.any,
      );
      final source = NativeInventorySource(dio);

      await expectLater(
        () => source.createSpoolFromSlot(printerId: 1, amsId: 0, trayId: 0),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 404)
              .having((e) => e.detail, 'detail', 'Not Found'),
        ),
      );

      adapter.onPost(
        '/api/v1/inventory/spools/from-slot',
        (s) => s.reply(404, {
          'detail': 'Printer not connected or no state available',
        }),
        data: Matchers.any,
      );

      await expectLater(
        () => source.createSpoolFromSlot(printerId: 1, amsId: 0, trayId: 0),
        throwsA(
          isA<ApiException>().having(
            (e) => e.detail,
            'detail',
            'Printer not connected or no state available',
          ),
        ),
      );
    });

    test(
      'a spool created without an id in the body is still a success',
      () async {
        adapter.onPost(
          '/api/v1/inventory/spools/from-slot',
          (s) => s.reply(200, {'material': 'PLA'}),
          data: Matchers.any,
        );

        expect(
          await NativeInventorySource(
            dio,
          ).createSpoolFromSlot(printerId: 1, amsId: 0, trayId: 0),
          isNull,
        );
      },
    );
  });

  group('Spoolman backend', () {
    test('posts to /spoolman/spools/from-slot and reads spool_id', () async {
      adapter.onPost(
        '/api/v1/spoolman/spools/from-slot',
        (s) => s.reply(200, {'success': true, 'spool_id': 7}),
        data: Matchers.any,
      );
      captureBody();

      final id = await SpoolmanInventorySource(
        dio,
      ).createSpoolFromSlot(printerId: 2, amsId: 255, trayId: 1);

      expect(id, 7);
      expect(capturedBody, {'printer_id': 2, 'ams_id': 255, 'tray_id': 1});
    });

    test('the API-key refusal arrives as forbidden, not as a bad response', () {
      // `filaments:update` is outside the API-key scope allowlist, so a keyed
      // session gets this on every attempt whatever the key's scopes.
      adapter.onPost(
        '/api/v1/spoolman/spools/from-slot',
        (s) => s.reply(403, {
          'detail': 'API keys cannot be used for administrative operations',
        }),
        data: Matchers.any,
      );

      expect(
        () => SpoolmanInventorySource(
          dio,
        ).createSpoolFromSlot(printerId: 1, amsId: 0, trayId: 0),
        throwsA(
          isA<AuthException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.forbidden,
          ),
        ),
      );
    });
  });
}
