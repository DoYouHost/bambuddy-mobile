import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/data/print_log_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

/// What the print log's wire contract has to keep doing.
///
/// Two of these are about a server that answers 200 and does something else
/// than asked: below 1.2.6 `sort_by` is an unknown query param FastAPI drops in
/// silence, and `cost` / `energy_*` are simply absent from the response. Both
/// read as "nothing to show" on the screen, so the repository is the last place
/// that can tell them apart from a real empty value.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late List<RequestOptions> sent;

  const listPath = '/api/v1/print-log/';
  const versionPath = '/api/v1/updates/version';

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    sent = [];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      sent.add(options);
      handler.next(options);
    }));
  });

  PrintLogRepository repo() =>
      PrintLogRepository(dio, ServerVersionService(dio));

  void replyVersion(String version) => adapter.onGet(
        versionPath,
        (s) => s.reply(200, {'version': version, 'repo': 'maziggy/bambuddy'}),
      );

  /// A row as a 1.2.6 server sends it — every field populated, so a test that
  /// blanks one is saying something.
  Map<String, dynamic> row({
    int id = 7,
    String status = 'failed',
    Object? failureReason = 'cloggedNozzle',
  }) =>
      <String, dynamic>{
        'id': id,
        'archive_id': 82,
        'print_name': 'Y Splitter Connector',
        'printer_name': 'P1S',
        'printer_id': 1,
        'status': status,
        'started_at': '2026-08-01T10:00:00',
        'completed_at': '2026-08-01T11:30:00',
        'duration_seconds': 5400,
        'filament_type': 'PLA',
        'filament_color': '#00AE42',
        'filament_used_grams': 42.5,
        'cost': 1.23,
        'energy_kwh': 0.42,
        'energy_cost': 0.19,
        'failure_reason': failureReason,
        'thumbnail_path': 'data/thumbs/7.png',
        'created_by_id': 2,
        'created_by_username': 'zosia',
        'created_at': '2026-08-01T09:59:00',
      };

  Map<String, dynamic> page(List<Object> items, {int? total}) =>
      {'items': items, 'total': total ?? items.length};

  Map<String, dynamic> lastQuery() => sent.last.queryParameters;

  group('list', () {
    test('every filter goes out under the name the server takes', () async {
      replyVersion('1.2.5.2');
      adapter.onGet(listPath, (s) => s.reply(200, page([row()])));

      await repo().list(
        search: 'splitter',
        printerId: 3,
        status: 'failed',
        createdByUsername: 'zosia',
        limit: 25,
        offset: 50,
      );

      expect(lastQuery(), {
        'search': 'splitter',
        'printer_id': 3,
        'status': 'failed',
        'created_by_username': 'zosia',
        'limit': 25,
        'offset': 50,
      });
    });

    test('an empty search is left out rather than sent as an empty match',
        () async {
      replyVersion('1.2.5.2');
      adapter.onGet(listPath, (s) => s.reply(200, page([])));

      await repo().list(search: '');

      expect(lastQuery().containsKey('search'), isFalse);
    });

    test('a date range goes out as a naive UTC instant', () async {
      replyVersion('1.2.5.2');
      adapter.onGet(listPath, (s) => s.reply(200, page([])));

      // Built from UTC so the expectation holds wherever the test runs: the
      // point is that the local instant is converted, and that no `Z` is
      // appended — the columns are naive, and a tz-aware bind param compares
      // against them differently per database.
      await repo().list(
        dateFrom: DateTime.utc(2026, 8, 1, 22).toLocal(),
        dateTo: DateTime.utc(2026, 8, 31, 21, 59, 59).toLocal(),
      );

      expect(lastQuery()['date_from'], '2026-08-01T22:00:00');
      expect(lastQuery()['date_to'], '2026-08-31T21:59:59');
    });

    test('parses the page and keeps the server total, not the row count',
        () async {
      replyVersion('1.2.5.2');
      adapter.onGet(
        listPath,
        (s) => s.reply(200, page([row(), row(id: 8)], total: 137)),
      );

      final result = await repo().list();

      expect(result.items.map((e) => e.id), [7, 8]);
      expect(result.total, 137, reason: 'load-more depends on it');
      expect(result.items.first.printerName, 'P1S');
      expect(result.items.first.energyKwh, 0.42);
    });

    test('a malformed row drops itself, not the page', () async {
      replyVersion('1.2.5.2');
      adapter.onGet(
        listPath,
        (s) => s.reply(200, page(['not an object', row(id: 9)])),
      );

      final result = await repo().list();

      expect(result.items.map((e) => e.id), [9]);
    });

    test('a pre-1.2.6 row without cost/energy parses as null, not zero',
        () async {
      // The fields are absent, which is what that server sends for every row.
      // Coercing them to 0 would print "0.00 kWh" against a run that drew
      // power — a wrong number reads as a measurement, a blank reads as one.
      replyVersion('1.2.5.2');
      final legacy = row()
        ..remove('cost')
        ..remove('energy_kwh')
        ..remove('energy_cost');
      adapter.onGet(listPath, (s) => s.reply(200, page([legacy])));

      final entry = (await repo().list()).items.single;

      expect(entry.cost, isNull);
      expect(entry.energyKwh, isNull);
      expect(entry.energyCost, isNull);
    });

    test('a legacy translated failure reason survives parsing', () async {
      // Older web builds saved the label instead of the key, and the
      // archive-side PATCH that mirrors this field validates nothing.
      replyVersion('1.2.5.2');
      adapter.onGet(
        listPath,
        (s) => s.reply(200, page([row(failureReason: 'Zapchana dysza')])),
      );

      final entry = (await repo().list()).items.single;

      expect(entry.failureReason, 'Zapchana dysza');
    });

    test('an orphan row — archive deleted — still parses', () async {
      replyVersion('1.2.5.2');
      final orphan = row()..['archive_id'] = null;
      adapter.onGet(listPath, (s) => s.reply(200, page([orphan])));

      final entry = (await repo().list()).items.single;

      expect(entry.isOrphan, isTrue);
    });

    test('sort is dropped on a server that would ignore it', () async {
      replyVersion('1.2.5.2');
      adapter.onGet(listPath, (s) => s.reply(200, page([])));

      await repo().list(sort: PrintLogSort.cost, descending: false);

      expect(lastQuery().containsKey('sort_by'), isFalse);
      expect(lastQuery().containsKey('sort_dir'), isFalse);
    });

    test('sort is sent from 1.2.6', () async {
      replyVersion('1.2.6b1');
      adapter.onGet(listPath, (s) => s.reply(200, page([])));

      await repo().list(sort: PrintLogSort.cost, descending: false);

      expect(lastQuery()['sort_by'], 'cost');
      expect(lastQuery()['sort_dir'], 'asc');
    });

    test('an unreadable version is treated as the older contract', () async {
      adapter.onGet(versionPath, (s) => s.reply(500, {'detail': 'boom'}));
      adapter.onGet(listPath, (s) => s.reply(200, page([])));

      final r = repo();

      expect(await r.supportsCostEnergy(), isFalse);
      await r.list(sort: PrintLogSort.date);
      expect(lastQuery().containsKey('sort_by'), isFalse);
    });
  });

  group('updateEntry', () {
    test('sends only the field that was touched', () async {
      adapter.onPatch(
        '/api/v1/print-log/7',
        (s) => s.reply(200, row(failureReason: 'layerShift')),
        data: {'failure_reason': 'layerShift'},
      );

      final updated = await repo().updateEntry(7, failureReason: 'layerShift');

      expect(sent.last.data, {'failure_reason': 'layerShift'});
      expect(updated.failureReason, 'layerShift');
    });

    test('an untouched status is absent, so a legacy `aborted` row keeps it',
        () async {
      // The PATCH vocabulary has no `aborted`, and the server applies
      // exclude_unset: not naming the field is the only way to leave it alone.
      adapter.onPatch(
        '/api/v1/print-log/7',
        (s) => s.reply(200, row(status: 'aborted', failureReason: 'warping')),
        data: {'failure_reason': 'warping'},
      );

      final updated = await repo().updateEntry(7, failureReason: 'warping');

      expect(sent.last.data.containsKey('status'), isFalse);
      expect(updated.status, 'aborted');
    });

    test('clearing the classification sends an empty string', () async {
      // Not null: the server reads `''` as "unset it" and stores NULL, while an
      // absent field means "leave it as it is".
      adapter.onPatch(
        '/api/v1/print-log/7',
        (s) => s.reply(200, row(failureReason: null)),
        data: {'failure_reason': ''},
      );

      final updated = await repo().updateEntry(7, clearFailureReason: true);

      expect(sent.last.data, {'failure_reason': ''});
      expect(updated.failureReason, isNull);
    });

    test('a status change goes out on its own', () async {
      adapter.onPatch(
        '/api/v1/print-log/7',
        (s) => s.reply(200, row(status: 'completed')),
        data: {'status': 'completed'},
      );

      await repo().updateEntry(7, status: 'completed');

      expect(sent.last.data, {'status': 'completed'});
    });

    test('a rejected value keeps the wording that says which one', () async {
      // Only reachable if our vocabulary drifts from the server's, which is
      // exactly when the reader needs the server's own sentence.
      adapter.onPatch(
        '/api/v1/print-log/7',
        (s) => s.reply(400, {'detail': "Unknown failure_reason: 'oops'"}),
        data: {'failure_reason': 'oops'},
      );

      await expectLater(
        repo().updateEntry(7, failureReason: 'oops'),
        throwsA(isA<ApiException>().having(
          (e) => e.detail,
          'detail',
          "Unknown failure_reason: 'oops'",
        )),
      );
    });

    test('a server older than 0.2.4.6 has no editor route at all', () async {
      adapter.onPatch(
        '/api/v1/print-log/7',
        (s) => s.reply(405, {'detail': 'Method Not Allowed'}),
        data: {'status': 'completed'},
      );

      await expectLater(
        repo().updateEntry(7, status: 'completed'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 405)),
      );
    });

    test('a key without can_manage_archives is refused, and it says so',
        () async {
      adapter.onPatch(
        '/api/v1/print-log/7',
        (s) => s.reply(403, {
          'detail': "API key does not have 'can_manage_archives' permission",
        }),
        data: {'status': 'completed'},
      );

      await expectLater(
        repo().updateEntry(7, status: 'completed'),
        throwsA(isA<AuthException>()
            .having((e) => e.code, 'code', AppErrorCode.forbidden)
            .having((e) => e.detail, 'detail', contains('can_manage_archives'))),
      );
    });
  });

  group('delete', () {
    test('one row goes by id', () async {
      adapter.onDelete(
        '/api/v1/print-log/7',
        (s) => s.reply(200, {'status': 'deleted', 'id': 7}),
      );

      await repo().deleteEntry(7);

      expect(sent.last.path, '/api/v1/print-log/7');
    });

    test('clearing the log answers how many rows went', () async {
      adapter.onDelete(listPath, (s) => s.reply(200, {'deleted': 137}));

      expect(await repo().clearAll(), 137);
      expect(sent.last.queryParameters, isEmpty,
          reason: 'the route takes no filters — it wipes everything');
    });
  });
}
