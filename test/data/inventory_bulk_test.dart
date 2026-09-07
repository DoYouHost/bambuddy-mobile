import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/inventory_bulk.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

/// The five bulk routes on both inventory backends, plus the per-spool
/// reset-counter rename. The backends share the request bodies and disagree
/// about the answers: native lists the ids it could not act on, Spoolman
/// reports per-spool errors.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late RequestLog sent;

  setUp(() {
    dio = testDio();
    adapter = DioAdapter(dio: dio);
    sent = captureRequests(dio);
  });

  group('native backend', () {
    test('bulk-update sends the ids and the patch, reads the tally', () async {
      adapter.onPost(
        '/api/v1/inventory/spools/bulk-update',
        (s) => s.reply(200, {
          'updated': 2,
          'not_found': [9],
        }),
        data: Matchers.any,
      );

      final outcome = await NativeInventorySource(dio).bulkUpdate([
        1,
        2,
        9,
      ], const SpoolBulkPatch(brand: 'Bambu', category: 'spare'));

      expect(sent.requests.single.data, {
        'ids': [1, 2, 9],
        'update': {'brand': 'Bambu', 'category': 'spare'},
      });
      expect(outcome.ok, 2);
      expect(outcome.failed, 1);
      expect(outcome.notFound, [9]);
    });

    test('bulk-archive reports already-archived rows as skipped', () async {
      adapter.onPost(
        '/api/v1/inventory/spools/bulk-archive',
        (s) => s.reply(200, {
          'archived': 1,
          'already_archived': [2],
          'not_found': [],
        }),
        data: Matchers.any,
      );

      final outcome = await NativeInventorySource(dio).bulkArchive([1, 2]);

      expect(sent.requests.single.data, {
        'ids': [1, 2],
      });
      expect((outcome.ok, outcome.skipped, outcome.failed), (1, 1, 0));
      expect(outcome.isComplete, isTrue);
    });

    test('bulk-restore reads its own counter names', () async {
      adapter.onPost(
        '/api/v1/inventory/spools/bulk-restore',
        (s) => s.reply(200, {
          'restored': 2,
          'already_active': [3],
        }),
        data: Matchers.any,
      );

      final outcome = await NativeInventorySource(dio).bulkRestore([1, 2, 3]);

      expect((outcome.ok, outcome.skipped), (2, 1));
    });

    test('bulk-delete counts the unknown ids as failures', () async {
      adapter.onPost(
        '/api/v1/inventory/spools/bulk-delete',
        (s) => s.reply(200, {
          'deleted': 1,
          'not_found': [7, 8],
        }),
        data: Matchers.any,
      );

      final outcome = await NativeInventorySource(dio).bulkDelete([1, 7, 8]);

      expect((outcome.ok, outcome.failed), (1, 2));
    });

    test('the reset route is keyed on spool_ids, not ids', () async {
      adapter.onPost(
        '/api/v1/inventory/spools/reset-consumed-counter-bulk',
        (s) => s.reply(200, {'reset': 2}),
        data: Matchers.any,
      );

      final outcome = await NativeInventorySource(
        dio,
      ).bulkResetUsage([1, 2, 3]);

      expect(sent.requests.single.data, {
        'spool_ids': [1, 2, 3],
      });
      // Three asked for, two reset: the route reports no failures of its own,
      // so the gap is the only thing that says what did not happen.
      expect((outcome.ok, outcome.failed), (2, 1));
    });
  });

  group('Spoolman backend', () {
    test('per-spool errors become the failure count', () async {
      adapter.onPost(
        '/api/v1/spoolman/inventory/spools/bulk-delete',
        (s) => s.reply(200, {
          'deleted': 1,
          'errors': [
            {'id': 2, 'status': 404, 'detail': 'not found'},
          ],
        }),
        data: Matchers.any,
      );

      final outcome = await SpoolmanInventorySource(dio).bulkDelete([1, 2]);

      expect((outcome.ok, outcome.failed), (1, 1));
      expect(outcome.notFound, isEmpty);
    });

    test(
      'bulk-update sends only the fields Spoolman has a column for',
      () async {
        adapter.onPost(
          '/api/v1/spoolman/inventory/spools/bulk-update',
          (s) => s.reply(200, {'updated': 1, 'errors': []}),
          data: Matchers.any,
        );

        await SpoolmanInventorySource(dio).bulkUpdate([
          1,
        ], const SpoolBulkPatch(brand: 'Bambu', lowStockThresholdPct: 20));

        expect(sent.requests.single.data, {
          'ids': [1],
          'update': {'brand': 'Bambu'},
        });
      },
    );

    test('an edit of native-only fields never leaves the phone', () async {
      // The route answers 400 to an empty `update`, and there is nothing to
      // apply — so the request is not worth sending.
      final outcome = await SpoolmanInventorySource(
        dio,
      ).bulkUpdate([1, 2], const SpoolBulkPatch(category: 'spare'));

      expect(sent.requests, isEmpty);
      expect(outcome.ok, 0);
      expect(outcome.isComplete, isTrue);
    });
  });

  group('chunking', () {
    test(
      'a selection over the server cap is split and the tallies add up',
      () async {
        // One reply per request, so the tally can only reach 2 by summing both
        // chunks — which is the thing under test.
        adapter.onPost(
          '/api/v1/inventory/spools/bulk-archive',
          (s) => s.reply(200, {'archived': 1}),
          data: Matchers.any,
        );

        final ids = [for (var i = 1; i <= 501; i++) i];
        final outcome = await NativeInventorySource(dio).bulkArchive(ids);

        expect(sent.requests.length, 2);
        expect((sent.requests[0].data as Map)['ids'], hasLength(500));
        expect((sent.requests[1].data as Map)['ids'], [501]);
        expect(outcome.ok, 2);
      },
    );

    test(
      'a refusal part-way through keeps what the earlier chunks did',
      () async {
        // The server has already archived those rows. Throwing here would report
        // the whole selection as failed while hundreds of spools had moved.
        adapter.onPost(
          '/api/v1/inventory/spools/bulk-archive',
          (s) => s.reply(200, {'archived': 500}),
          data: Matchers.any,
        );
        var calls = 0;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              calls++;
              if (calls < 2) return h.next(o);
              h.reject(
                DioException(
                  requestOptions: o,
                  response: Response(requestOptions: o, statusCode: 403),
                  type: DioExceptionType.badResponse,
                ),
              );
            },
          ),
        );

        final outcome = await NativeInventorySource(
          dio,
        ).bulkArchive([for (var i = 1; i <= 501; i++) i]);

        expect(outcome.ok, 500);
        expect(outcome.failed, 1, reason: 'the chunk that never took effect');
      },
    );

    test('a refusal on the first chunk still reaches the caller', () async {
      // Nothing has happened yet, so the error itself is the useful answer —
      // it carries "no permission", and a 404 tells the caller to fall back.
      adapter.onPost(
        '/api/v1/inventory/spools/bulk-archive',
        (s) => s.reply(403, {'detail': 'forbidden'}),
        data: Matchers.any,
      );

      await expectLater(
        NativeInventorySource(
          dio,
        ).bulkArchive([for (var i = 1; i <= 501; i++) i]),
        throwsA(isA<AppApiException>()),
      );
    });

    test('an empty selection sends nothing at all', () async {
      final outcome = await NativeInventorySource(dio).bulkDelete([]);

      expect(sent.requests, isEmpty);
      expect(outcome.ok, 0);
    });
  });

  group('a server without the bulk routes', () {
    test('surfaces its 404 so the caller can fall back per spool', () async {
      adapter.onPost(
        '/api/v1/inventory/spools/bulk-archive',
        (s) => s.reply(404, {'detail': 'Not Found'}),
        data: Matchers.any,
      );

      await expectLater(
        NativeInventorySource(dio).bulkArchive([1, 2]),
        throwsA(
          isA<AppApiException>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });
  });

  group('reset-consumed-counter rename', () {
    const current = '/api/v1/inventory/spools/5/reset-consumed-counter';
    const legacy = '/api/v1/inventory/spools/5/reset-usage';

    test('the current path is the one tried first', () async {
      adapter.onPost(
        current,
        (s) => s.reply(200, {'id': 5}),
        data: Matchers.any,
      );

      await NativeInventorySource(dio).resetUsage(5);

      expect(sent.paths, [current]);
    });

    test('a server older than the rename gets the old path', () async {
      adapter
        ..onPost(
          current,
          (s) => s.reply(404, {'detail': 'Not Found'}),
          data: Matchers.any,
        )
        ..onPost(legacy, (s) => s.reply(200, {'id': 5}), data: Matchers.any);

      await NativeInventorySource(dio).resetUsage(5);

      expect(sent.paths, [current, legacy]);
    });

    test('any other refusal is passed on, not retried elsewhere', () async {
      adapter.onPost(
        current,
        (s) => s.reply(403, {'detail': 'forbidden'}),
        data: Matchers.any,
      );

      await expectLater(
        NativeInventorySource(dio).resetUsage(5),
        throwsA(isA<AppApiException>()),
      );
      expect(sent.paths, [current]);
    });

    test('Spoolman follows the same order', () async {
      const spoolmanCurrent =
          '/api/v1/spoolman/inventory/spools/5/reset-consumed-counter';
      const spoolmanLegacy = '/api/v1/spoolman/inventory/spools/5/reset-usage';
      adapter
        ..onPost(
          spoolmanCurrent,
          (s) => s.reply(404, {'detail': 'Not Found'}),
          data: Matchers.any,
        )
        ..onPost(spoolmanLegacy, (s) => s.reply(200, {}), data: Matchers.any);

      await SpoolmanInventorySource(dio).resetUsage(5);

      expect(sent.paths, [spoolmanCurrent, spoolmanLegacy]);
    });
  });
}
