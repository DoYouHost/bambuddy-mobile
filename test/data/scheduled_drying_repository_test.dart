import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/scheduled_drying.dart';
import 'package:bambuddy_mobile/data/scheduled_drying_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late ScheduledDryingRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    repo = ScheduledDryingRepository(dio, ServerVersionService(dio));
  });

  void replyVersion(String version) => adapter.onGet(
        '/api/v1/updates/version',
        (s) => s.reply(200, {'version': version, 'repo': 'x/y'}),
      );

  Map<String, dynamic> row({
    int id = 7,
    String status = 'pending',
    String? startAfter = '2026-09-04T21:00:00Z',
    String? waitingReason,
    String? errorMessage,
  }) =>
      {
        'id': id,
        'printer_id': 3,
        'ams_id': 1,
        'temp': 65,
        'duration_hours': 8,
        'filament': 'PETG',
        'rotate_tray': false,
        'start_after': startAfter,
        'status': status,
        'waiting_reason': waitingReason,
        'error_message': errorMessage,
        'created_at': '2026-09-03T10:00:00Z',
        'started_at': null,
        'completed_at': null,
      };

  group('list', () {
    test('parses a row, reading the start instant as UTC', () async {
      adapter.onGet(
        '/api/v1/scheduled-dryings',
        (s) => s.reply(200, [row()]),
      );

      final rows = await repo.list();

      expect(rows, hasLength(1));
      expect(rows.single.id, 7);
      expect(rows.single.printerId, 3);
      expect(rows.single.amsId, 1);
      expect(rows.single.temp, 65);
      expect(rows.single.durationHours, 8);
      expect(rows.single.filament, 'PETG');
      expect(rows.single.isPending, isTrue);
      // Local for display, but the same instant the server named.
      expect(rows.single.startAfter!.isUtc, isFalse);
      expect(rows.single.startAfter!.toUtc(), DateTime.utc(2026, 9, 4, 21));
    });

    test('a stamp without the Z is UTC too, not the phone\'s wall clock',
        () async {
      adapter.onGet(
        '/api/v1/scheduled-dryings',
        (s) => s.reply(200, [row(startAfter: '2026-09-04T21:00:00')]),
      );

      final rows = await repo.list();

      expect(rows.single.startAfter!.toUtc(), DateTime.utc(2026, 9, 4, 21));
    });

    test('a null start_after is "as soon as the printer is idle"', () async {
      adapter.onGet(
        '/api/v1/scheduled-dryings',
        (s) => s.reply(200, [row(startAfter: null)]),
      );

      expect((await repo.list()).single.startAfter, isNull);
    });

    test('filters by printer when asked', () async {
      adapter.onGet(
        '/api/v1/scheduled-dryings',
        (s) => s.reply(200, [row()]),
        queryParameters: {'printer_id': 3},
      );

      expect(await repo.list(printerId: 3), hasLength(1));
    });

    test('one malformed row does not empty the list', () async {
      adapter.onGet(
        '/api/v1/scheduled-dryings',
        (s) => s.reply(200, ['not-a-row', row()]),
      );

      expect(await repo.list(), hasLength(1));
    });

    test('a 404 answers with nothing rather than throwing at a card', () async {
      adapter.onGet(
        '/api/v1/scheduled-dryings',
        (s) => s.reply(404, {'detail': 'Not Found'}),
      );

      expect(await repo.list(), isEmpty);
    });

    test('a 403 answers the same way — the card has nothing to say either',
        () async {
      adapter.onGet(
        '/api/v1/scheduled-dryings',
        (s) => s.reply(403, {'detail': 'Missing required permissions'}),
      );

      expect(await repo.list(), isEmpty);
    });

    test('any other failure still surfaces', () async {
      adapter.onGet(
        '/api/v1/scheduled-dryings',
        (s) => s.reply(500, {'detail': 'boom'}),
      );

      expect(
        repo.list(),
        throwsA(isA<AppApiException>()
            .having((e) => e.statusCode, 'statusCode', 500)),
      );
    });
  });

  group('waiting reason', () {
    test('every token the scheduler writes has a name', () async {
      for (final reason in DryingWaitReason.values) {
        if (reason == DryingWaitReason.unknown) continue;
        adapter.onGet(
          '/api/v1/scheduled-dryings',
          (s) => s.reply(200, [row(waitingReason: reason.wire)]),
          queryParameters: {'printer_id': reason.index},
        );
        final rows = await repo.list(printerId: reason.index);
        expect(rows.single.waitingReason, reason, reason: reason.wire);
      }
    });

    test('a token this build has no wording for is not an error', () async {
      adapter.onGet(
        '/api/v1/scheduled-dryings',
        (s) => s.reply(200, [row(waitingReason: 'ams_on_fire')]),
      );

      expect((await repo.list()).single.waitingReason,
          DryingWaitReason.unknown);
    });

    test('no reason at all stays null', () async {
      adapter.onGet(
        '/api/v1/scheduled-dryings',
        (s) => s.reply(200, [row()]),
      );

      expect((await repo.list()).single.waitingReason, isNull);
    });
  });

  group('create', () {
    test('sends the start instant as naive UTC, which is what the column is',
        () async {
      Map<String, dynamic>? sent;
      adapter.onPost(
        '/api/v1/scheduled-dryings',
        (s) => s.reply(200, row()),
        data: Matchers.any,
      );
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        if (options.method == 'POST') {
          sent = options.data as Map<String, dynamic>;
        }
        handler.next(options);
      }));

      await repo.create(
        printerId: 3,
        amsId: 1,
        temp: 65,
        durationHours: 8,
        filament: 'PETG',
        startAfter: DateTime.utc(2026, 9, 4, 21).toLocal(),
      );

      expect(sent!['start_after'], '2026-09-04T21:00:00');
      expect(sent!['printer_id'], 3);
      expect(sent!['ams_id'], 1);
      expect(sent!['temp'], 65);
      expect(sent!['duration_hours'], 8);
      expect(sent!['filament'], 'PETG');
      expect(sent!['rotate_tray'], isFalse);
    });

    test('no instant means the key is left out, not sent as null', () async {
      Map<String, dynamic>? sent;
      adapter.onPost(
        '/api/v1/scheduled-dryings',
        (s) => s.reply(200, row(startAfter: null)),
        data: Matchers.any,
      );
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        if (options.method == 'POST') {
          sent = options.data as Map<String, dynamic>;
        }
        handler.next(options);
      }));

      await repo.create(printerId: 3, amsId: 0, temp: 45, durationHours: 4);

      expect(sent!.containsKey('start_after'), isFalse);
    });

    test('a refusal surfaces as the server worded it', () async {
      adapter.onPost(
        '/api/v1/scheduled-dryings',
        (s) => s.reply(400, {'detail': 'start_after must be in the future'}),
        data: Matchers.any,
      );

      expect(
        repo.create(
          printerId: 3,
          amsId: 0,
          temp: 45,
          durationHours: 4,
          startAfter: DateTime(2020),
        ),
        throwsA(isA<AppApiException>()
            .having((e) => e.statusCode, 'statusCode', 400)),
      );
    });
  });

  group('whether to offer scheduling at all', () {
    test('the version decides until a request has', () async {
      replyVersion('1.2.5.3');
      expect(await repo.supportsScheduling(), isFalse);

      final newer = ScheduledDryingRepository(dio, ServerVersionService(dio));
      adapter.onGet(
        '/api/v1/updates/version',
        (s) => s.reply(200, {'version': '1.2.6b1', 'repo': 'x/y'}),
      );
      expect(await newer.supportsScheduling(), isTrue);
    });

    test('an unknown version does not offer a form that would 404', () async {
      adapter.onGet(
        '/api/v1/updates/version',
        (s) => s.reply(500, {'detail': 'boom'}),
      );

      expect(await repo.supportsScheduling(), isFalse);
    });

    test('with no version service at all it stays off', () async {
      expect(
        await ScheduledDryingRepository(dio).supportsScheduling(),
        isFalse,
      );
    });

    test('a 404 outranks a version that claimed otherwise', () async {
      replyVersion('1.2.6b1');
      adapter.onGet(
        '/api/v1/scheduled-dryings',
        (s) => s.reply(404, {'detail': 'Not Found'}),
      );
      expect(await repo.supportsScheduling(), isTrue);

      await repo.list();

      expect(await repo.supportsScheduling(), isFalse);
    });

    test('a 403 hides it too, which no version could have said', () async {
      replyVersion('1.2.6b1');
      adapter.onGet(
        '/api/v1/scheduled-dryings',
        (s) => s.reply(403, {'detail': 'nope'}),
      );

      await repo.list();

      expect(await repo.supportsScheduling(), isFalse);
    });

    test('a listing that arrives outranks a version that said no', () async {
      replyVersion('1.2.5.3');
      adapter.onGet(
        '/api/v1/scheduled-dryings',
        (s) => s.reply(200, <Object>[]),
      );
      expect(await repo.supportsScheduling(), isFalse);

      await repo.list();

      expect(await repo.supportsScheduling(), isTrue);
    });

    test('a 500 says nothing about the route either way', () async {
      replyVersion('1.2.6b1');
      adapter.onGet(
        '/api/v1/scheduled-dryings',
        (s) => s.reply(500, {'detail': 'boom'}),
      );

      await expectLater(repo.list(), throwsA(isA<AppApiException>()));

      expect(await repo.supportsScheduling(), isTrue);
    });
  });

  test('cancel drops the row', () async {
    adapter.onDelete(
      '/api/v1/scheduled-dryings/7',
      (s) => s.reply(200, {'status': 'cancelled', 'id': 7}),
    );

    await expectLater(repo.cancel(7), completes);
  });
}
