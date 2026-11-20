import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/print_log_entry.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:bambuddy_mobile/features/archive/archive_calendar_data.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late ArchiveRepository repo;
  late RequestLog sent;
  const path = '/api/v1/archives/prints';

  setUp(() {
    dio = testDio();
    adapter = mockServer(dio);
    sent = captureRequests(dio);
    repo = ArchiveRepository(dio, ServerVersionService(dio));
  });

  Map<String, dynamic> q(
    String from,
    String to, {
    int offset = 0,
    int? printer,
  }) => {
    'date_from': from,
    'date_to': to,
    'printer_id': ?printer,
    'limit': 500,
    'offset': offset,
  };

  Map<String, dynamic> run(int id) => {
    'id': id,
    'archive_id': 1,
    'status': 'completed',
    'created_at': '2026-11-02T10:00:00',
  };

  group('printsBetween', () {
    test('asks for the calendar days and reads every page', () async {
      adapter
        ..onGet(
          path,
          (s) => s.reply(200, {
            'items': [for (var i = 0; i < 500; i++) run(i)],
            'total': 503,
          }),
          queryParameters: q('2026-11-01', '2026-11-30'),
        )
        ..onGet(
          path,
          (s) => s.reply(200, {
            'items': [for (var i = 500; i < 503; i++) run(i)],
            'total': 503,
          }),
          queryParameters: q('2026-11-01', '2026-11-30', offset: 500),
        );

      final rows = await repo.printsBetween(
        DateTime(2026, 11),
        DateTime(2026, 11, 30),
      );

      expect(rows, hasLength(503));
      expect(sent.requests.first.queryParameters, {
        'date_from': '2026-11-01',
        'date_to': '2026-11-30',
        'limit': 500,
        'offset': 0,
      });
      expect(sent.requests.last.queryParameters['offset'], 500);
      expect(await repo.printsCapability.supported, isTrue);
    });

    test('names the printer when the list is filtered by one', () async {
      adapter.onGet(
        path,
        (s) => s.reply(200, {'items': [], 'total': 0}),
        queryParameters: q('2026-02-01', '2026-02-28', printer: 4),
      );

      await repo.printsBetween(
        DateTime(2026, 2),
        DateTime(2026, 2, 28),
        printerId: 4,
      );

      expect(sent.requests.single.queryParameters['printer_id'], 4);
    });

    test(
      'an older server\'s 422 is no route, and is not asked again',
      () async {
        adapter.onGet(
          path,
          (s) => s.reply(422, {'detail': []}),
          queryParameters: q('2026-11-01', '2026-11-30'),
        );

        expect(
          await repo.printsBetween(DateTime(2026, 11), DateTime(2026, 11, 30)),
          isNull,
        );
        expect(
          await repo.printsBetween(DateTime(2026, 10), DateTime(2026, 10, 31)),
          isNull,
        );
        expect(sent.requests, hasLength(1));
        expect(await repo.printsCapability.supported, isFalse);
      },
    );

    test('a server error is still an error', () {
      adapter.onGet(
        path,
        (s) => s.reply(500, {'detail': 'boom'}),
        queryParameters: q('2026-11-01', '2026-11-30'),
      );

      expect(
        () => repo.printsBetween(DateTime(2026, 11), DateTime(2026, 11, 30)),
        throwsA(isA<AppApiException>()),
      );
    });
  });

  group('calendarPrints', () {
    Archive archive(
      int id, {
      String status = 'completed',
      int runCount = 1,
      DateTime? completedAt,
    }) => Archive(
      id: id,
      filename: 'a$id.3mf',
      status: status,
      runCount: runCount,
      completedAt: completedAt,
      createdAt: DateTime.utc(2026, 11, 1),
      filamentColor: '#000000',
    );

    PrintLogEntry entry(int id, int archiveId, DateTime ended) => PrintLogEntry(
      id: id,
      archiveId: archiveId,
      status: 'completed',
      createdAt: ended,
      completedAt: ended,
    );

    test('a file printed three times shows three times', () {
      final prints = calendarPrints(
        [archive(1, runCount: 3)],
        [
          entry(1, 1, DateTime(2026, 11, 3, 12)),
          entry(2, 1, DateTime(2026, 11, 1, 12)),
          entry(3, 1, DateTime(2026, 11, 3, 18)),
        ],
        2026,
        11,
      );

      expect(prints.map((p) => p.runId), [2, 1, 3], reason: 'oldest first');
    });

    test('a run whose archive the filters hid is left out', () {
      final prints = calendarPrints(
        [archive(1)],
        [entry(1, 2, DateTime(2026, 11, 3))],
        2026,
        11,
      );

      expect(prints, isEmpty);
    });

    test('an archive without logged runs stands for its one print', () {
      final prints = calendarPrints(
        [
          archive(1, runCount: 0, completedAt: DateTime(2026, 11, 5)),
          archive(2, runCount: 0, status: 'printing'),
          archive(3, runCount: 0, status: 'archived'),
        ],
        const [],
        2026,
        11,
      );

      expect(prints.single.archive.id, 1);
      expect(prints.single.runId, isNull);
    });

    test('without the route every printed archive stands for one print', () {
      final prints = calendarPrints(
        [archive(1, runCount: 4, completedAt: DateTime(2026, 11, 5))],
        null,
        2026,
        11,
      );

      expect(prints.single.archive.id, 1);
    });

    test('only the month asked for, by local day', () {
      final prints = calendarPrints(
        [archive(1, runCount: 2)],
        [
          entry(1, 1, DateTime(2026, 10, 31, 23)),
          entry(2, 1, DateTime(2026, 12, 1)),
        ],
        2026,
        11,
      );

      expect(prints, isEmpty);
    });
  });
}
