import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/calibration_option.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late QueueRepository repo;

  setUp(() {
    dio = testDio();
    adapter = DioAdapter(dio: dio);
    repo = QueueRepository(dio);
  });

  test('fetch: parses list, id and statusKind are correct', () async {
    adapter.onGet(
      '/api/v1/queue/',
      (server) => server.reply(200, [readFixture('queue_item.json')]),
    );

    final items = await repo.fetch();

    expect(items, hasLength(1));
    expect(items.first.id, 78);
    expect(items.first.statusKind, QueueItemStatusKind.printing);
  });

  test('fetch: real server response parses in full', () async {
    // Fixture captured from a live bambuddy (see test/fixtures/README.md).
    // This is a tripwire on the contract: when the server changes the type of
    // a field the generated `fromJson` throws hard on, `parseJsonList` will
    // silently drop records and the queue screen will go empty with no error.
    final payload = readFixture('queue_list.json') as List<dynamic>;
    adapter.onGet('/api/v1/queue/', (server) => server.reply(200, payload));

    final items = await repo.fetch();

    expect(
      items,
      hasLength(payload.length),
      reason: 'not a single record may drop during parsing',
    );
    expect(items.map((i) => i.id), payload.map((r) => (r as Map)['id']));
  });

  test('fetch: 1.2.5 server response does not drop a single record', () async {
    // This is the empty screen from the report: three calibration fields came
    // in as strings, the generated cast to bool threw on EVERY record and the
    // list came out empty with a 200 status.
    final payload = readFixture('queue_list_tristate.json') as List<dynamic>;
    adapter.onGet('/api/v1/queue/', (server) => server.reply(200, payload));

    final items = await repo.fetch();

    expect(items, hasLength(payload.length));
    expect(items.map((i) => i.bedLevelling), [
      CalibrationOption.off,
      CalibrationOption.auto,
    ]);
    expect(items.map((i) => i.nozzleOffsetCali), [
      CalibrationOption.auto,
      CalibrationOption.off,
    ]);
    expect(
      items.where((i) => i.isActive),
      hasLength(2),
      reason: 'pending + printing — the queue screen has something to show',
    );
  });

  test('fetch: non-AMS items and odd names pass through without loss', () async {
    final payload = readFixture('queue_list.json') as List<dynamic>;
    adapter.onGet('/api/v1/queue/', (server) => server.reply(200, payload));

    final items = await repo.fetch();
    final fromLibrary = items.firstWhere((i) => i.libraryFileId != null);
    final external = items.firstWhere(
      (i) => i.amsMapping?.contains(254) ?? false,
    );
    final scheduled = items.firstWhere((i) => i.scheduledTime != null);

    expect(fromLibrary.libraryFileName, endsWith('.gcode.3mf'));
    expect(external.amsMapping, contains(254));
    expect(scheduled.scheduledTime, isA<DateTime>());
    // The server also returns names with broken encoding — must not crash anything.
    expect(items.map((i) => i.displayName), isNot(contains(isNull)));
  });

  test('fetch: history does not land in the active queue', () async {
    // This whole response is finished items (completed/cancelled/failed) —
    // exactly what looks like an "empty queue" on screen, and that's
    // correct: only pending/scheduled/printing/paused are active.
    final payload = readFixture('queue_list.json') as List<dynamic>;
    adapter.onGet('/api/v1/queue/', (server) => server.reply(200, payload));

    final items = await repo.fetch();

    expect(items.where((i) => i.isActive), isEmpty);
    expect(
      items.map((i) => i.statusKind).toSet(),
      {
        QueueItemStatusKind.completed,
        QueueItemStatusKind.cancelled,
        QueueItemStatusKind.failed,
      },
      reason: 'no status from this response may land in unknown',
    );
  });

  group('fetchActive', () {
    /// Two filtered requests instead of one for everything — matching on
    /// `queryParameters` is the point of the test here, not decoration.
    void mockStatus(String status, List<dynamic> reply) => adapter.onGet(
      '/api/v1/queue/',
      (server) => server.reply(200, reply),
      queryParameters: {'status': status},
    );

    Map<String, dynamic> item(int id, String status) => {
      'id': id,
      'position': 1,
      'status': status,
    };

    test(
      'asks separately for pending and printing, merges responses',
      () async {
        mockStatus('pending', [item(2, 'pending'), item(3, 'pending')]);
        mockStatus('printing', [item(1, 'printing')]);

        final items = await repo.fetchActive();

        expect(items.map((i) => i.id).toSet(), {1, 2, 3});
        expect(
          items.where((i) => i.statusKind == QueueItemStatusKind.printing),
          hasLength(1),
        );
      },
    );

    test(
      'an item that moved between responses appears once, as printing',
      () async {
        // Race built into two requests: the scheduler started 7 after the
        // pending list had been built.
        mockStatus('pending', [item(7, 'pending')]);
        mockStatus('printing', [item(7, 'printing')]);

        final items = await repo.fetchActive();

        expect(items, hasLength(1));
        expect(items.single.statusKind, QueueItemStatusKind.printing);
      },
    );

    test('an empty queue is an empty list, not an error', () async {
      mockStatus('pending', const []);
      mockStatus('printing', const []);

      expect(await repo.fetchActive(), isEmpty);
    });

    test('an error from either request does not get lost', () async {
      // The screen must show an error, not "empty queue" — that's the
      // difference between "server did not answer" and "nothing to print".
      mockStatus('pending', const []);
      adapter.onGet(
        '/api/v1/queue/',
        (server) => server.reply(500, {'detail': 'boom'}),
        queryParameters: {'status': 'printing'},
      );

      await expectLater(repo.fetchActive(), throwsA(isA<AppApiException>()));
    });
  });

  test('reorder: sends POST and completes without exception', () async {
    adapter.onPost(
      '/api/v1/queue/reorder',
      (server) => server.reply(200, null),
      data: {
        'items': [
          {'id': 78, 'position': 1},
          {'id': 79, 'position': 2},
        ],
      },
    );

    await repo.reorder([(id: 78, position: 1), (id: 79, position: 2)]);
    // No exception = success.
  });

  test(
    'delete: sends DELETE /queue/78 and completes without exception',
    () async {
      adapter.onDelete('/api/v1/queue/78', (server) => server.reply(200, null));

      await repo.delete(78);
    },
  );

  test(
    'start: sends POST /queue/78/start and completes without exception',
    () async {
      adapter.onPost(
        '/api/v1/queue/78/start',
        (server) => server.reply(200, null),
      );

      await repo.start(78);
    },
  );

  test(
    'cancel: sends POST /queue/78/cancel and completes without exception',
    () async {
      adapter.onPost(
        '/api/v1/queue/78/cancel',
        (server) => server.reply(200, null),
      );

      await repo.cancel(78);
    },
  );

  test(
    'addFromArchive: sends POST /queue/ and completes without exception',
    () async {
      adapter.onPost(
        '/api/v1/queue/',
        (server) => server.reply(200, null),
        data: {'archive_id': 77, 'printer_id': 1, 'quantity': 1},
      );

      await repo.addFromArchive(77, printerId: 1);
    },
  );

  test(
    'addFromArchive with insertAtTop: adds insert_at_top=true (reprint)',
    () async {
      adapter.onPost(
        '/api/v1/queue/',
        (server) => server.reply(200, null),
        data: {
          'archive_id': 77,
          'printer_id': 1,
          'quantity': 1,
          'insert_at_top': true,
        },
      );

      await repo.addFromArchive(77, printerId: 1, insertAtTop: true);
    },
  );

  test('addFromArchive with options: full config goes with the POST', () async {
    // The heart of the race fix: the item is created already configured, so
    // the scheduler has no way to grab it mid-setup.
    adapter.onPost(
      '/api/v1/queue/',
      (server) => server.reply(200, null),
      data: {
        'archive_id': 77,
        'printer_id': 1,
        'quantity': 1,
        'ams_mapping': [2, -1],
        'manual_start': true,
        'require_previous_success': false,
        'auto_off_after': false,
        'bed_levelling': true,
        'flow_cali': false,
        'vibration_cali': true,
        'layer_inspect': false,
        'timelapse': false,
        'preheat_override': 'inherit',
      },
    );

    await repo.addFromArchive(
      77,
      printerId: 1,
      options: const QueueCreateOptions(
        amsMapping: [2, -1],
        manualStart: true,
        requirePreviousSuccess: false,
        autoOffAfter: false,
        bedLevelling: CalibrationOption.on,
        flowCali: CalibrationOption.off,
        vibrationCali: true,
        layerInspect: false,
        timelapse: false,
        preheatOverride: 'inherit',
      ),
    );
  });

  test(
    'addFromLibraryFile with schedule: scheduled_time and target model',
    () async {
      adapter.onPost(
        '/api/v1/queue/',
        (server) => server.reply(200, null),
        data: {
          'library_file_id': 12,
          'quantity': 1,
          'target_model': 'X2D',
          'target_location': 'Garage',
          'scheduled_time': '2026-07-28T20:00:00.000Z',
        },
      );

      await repo.addFromLibraryFile(
        12,
        options: const QueueCreateOptions(
          targetModel: 'X2D',
          targetLocation: 'Garage',
          scheduledTime: '2026-07-28T20:00:00.000Z',
        ),
      );
    },
  );

  group('calibrations on save', () {
    /// Repository asking the stubbed server for its version.
    QueueRepository repoFor(String version) {
      adapter.onGet(
        '/api/v1/updates/version',
        (server) => server.reply(200, {'version': version, 'repo': 'x/y'}),
      );
      return QueueRepository(dio, ServerVersionService(dio));
    }

    test('on/off always as boolean — even on server 1.2.5', () async {
      adapter.onPost(
        '/api/v1/queue/',
        (server) => server.reply(200, null),
        data: {
          'archive_id': 77,
          'quantity': 1,
          'bed_levelling': true,
          'flow_cali': false,
        },
      );

      await repoFor('1.2.5.1').addFromArchive(
        77,
        options: const QueueCreateOptions(
          bedLevelling: CalibrationOption.on,
          flowCali: CalibrationOption.off,
        ),
      );
    });

    test('auto goes as a string to a server that can handle it', () async {
      adapter.onPost(
        '/api/v1/queue/',
        (server) => server.reply(200, null),
        data: {'archive_id': 77, 'quantity': 1, 'bed_levelling': 'auto'},
      );

      await repoFor('1.2.5.1').addFromArchive(
        77,
        options: const QueueCreateOptions(bedLevelling: CalibrationOption.auto),
      );
    });

    test(
      'creating: auto on an old server goes the way the form showed it',
      () async {
        // `auto` only lands here as a choice remembered from a newer server. The
        // old one has nowhere to store it, and the form then shows a two-state
        // toggle in the ON position — so ON must go out. Omitting the key would
        // hand the decision to the server, whose default for `flow_cali` is
        // `false`, so the screen would say one thing while saving another.
        adapter.onPost(
          '/api/v1/queue/',
          (server) => server.reply(200, null),
          data: {
            'archive_id': 77,
            'quantity': 1,
            'bed_levelling': true,
            'flow_cali': true,
          },
        );

        await repoFor('0.2.4.9').addFromArchive(
          77,
          options: const QueueCreateOptions(
            bedLevelling: CalibrationOption.auto,
            flowCali: CalibrationOption.auto,
          ),
        );
      },
    );

    test('editing: auto on an old server still drops from the body', () async {
      // Opposite of creating: here there IS a stored value to protect.
      // Sending a boolean would overwrite the user's auto with on/off on a
      // field they may not have touched.
      adapter.onPatch(
        '/api/v1/queue/9',
        (server) => server.reply(200, null),
        data: {'flow_cali': false},
      );

      await repoFor('0.2.4.9').updateItem(
        9,
        bedLevelling: CalibrationOption.auto,
        flowCali: CalibrationOption.off,
      );
    });

    test('unknown version behaves like an older one', () async {
      adapter.onGet(
        '/api/v1/updates/version',
        (server) => server.reply(500, null),
      );
      adapter.onPatch(
        '/api/v1/queue/9',
        (server) => server.reply(200, null),
        data: {'bed_levelling': true},
      );

      await QueueRepository(dio, ServerVersionService(dio)).updateItem(
        9,
        bedLevelling: CalibrationOption.on,
        nozzleOffsetCali: CalibrationOption.auto,
      );
    });

    test('our server 0.2.5b2: booleans confirmed by a live query', () async {
      // Verified 2026-07-30 by curling our own server: `.[0].bed_levelling`
      // returns `true`. So 0.2.5b2 is BEFORE the tri-state change — the
      // version number gave the same answer, but by coincidence, not proof.
      final repo = repoFor('0.2.5b2');
      adapter.onGet(
        '/api/v1/queue/',
        (server) => server.reply(200, [
          {'id': 1, 'position': 1, 'status': 'pending', 'bed_levelling': true},
        ]),
      );
      await repo.fetch();

      expect(await repo.supportsTriStateCalibration(), isFalse);
    });

    test('what the server actually sent beats the version number', () async {
      // Same version number, but if the server were sending strings —
      // observation should win. Gating by number is formally undecidable here:
      // 0.2.5b2 is a beta of the same cycle that shipped as 1.2.5, and sorts
      // below it in every ordering.
      final repo = repoFor('0.2.5b2');
      expect(
        await repo.supportsTriStateCalibration(),
        isFalse,
        reason: 'before seeing anything — be cautious',
      );

      adapter.onGet(
        '/api/v1/queue/',
        (server) => server.reply(200, [
          {
            'id': 1,
            'position': 1,
            'status': 'pending',
            'bed_levelling': 'auto',
          },
        ]),
      );
      await repo.fetch();

      expect(
        await repo.supportsTriStateCalibration(),
        isTrue,
        reason: 'strings in the response are proof, not a hint',
      );
    });

    test('booleans in the response keep us on the old shape', () async {
      // Opposite direction: the server calls itself 1.2.5, but if it were
      // sending booleans, observation should win too — we won't send it a string.
      final repo = repoFor('1.2.5.1');
      adapter.onGet(
        '/api/v1/queue/',
        (server) => server.reply(200, [
          {'id': 1, 'position': 1, 'status': 'pending', 'bed_levelling': true},
        ]),
      );
      await repo.fetch();

      expect(await repo.supportsTriStateCalibration(), isFalse);
    });

    test('a response without calibration fields settles nothing', () async {
      final repo = repoFor('1.2.5.1');
      adapter.onGet(
        '/api/v1/queue/',
        (server) => server.reply(200, [
          {'id': 1, 'position': 1, 'status': 'pending'},
        ]),
      );
      await repo.fetch();

      expect(
        await repo.supportsTriStateCalibration(),
        isTrue,
        reason: 'no observation → version decides',
      );
    });

    test('after observation, auto goes out to server 0.2.5b2', () async {
      final repo = repoFor('0.2.5b2');
      adapter
        ..onGet(
          '/api/v1/queue/',
          (server) => server.reply(200, [
            {
              'id': 1,
              'position': 1,
              'status': 'pending',
              'nozzle_offset_cali': 'auto',
            },
          ]),
        )
        ..onPatch(
          '/api/v1/queue/9',
          (server) => server.reply(200, null),
          data: {'bed_levelling': 'auto'},
        );

      await repo.fetch();
      await repo.updateItem(9, bedLevelling: CalibrationOption.auto);
    });

    test(
      'also works without a version service — reading calls have none',
      () async {
        adapter.onPatch(
          '/api/v1/queue/9',
          (server) => server.reply(200, null),
          data: {'flow_cali': false},
        );

        await QueueRepository(dio).updateItem(
          9,
          flowCali: CalibrationOption.off,
          bedLevelling: CalibrationOption.auto,
        );
      },
    );
  });

  test('empty options add nothing to the body', () async {
    // Null in [QueueCreateOptions] means "unset" — the key must NOT go out,
    // because there is nothing to clear on creation, and the server has its
    // own defaults.
    adapter.onPost(
      '/api/v1/queue/',
      (server) => server.reply(200, null),
      data: {'archive_id': 77, 'printer_id': 1, 'quantity': 1},
    );

    await repo.addFromArchive(
      77,
      printerId: 1,
      options: const QueueCreateOptions(),
    );
  });

  group('addCrossModel (#671)', () {
    test('sends variants in order and WITHOUT printer_id', () async {
      // The server rejects printer_id together with variants outright — naming
      // a printer defeats the point of offering alternatives.
      adapter.onPost(
        '/api/v1/queue/',
        (s) => s.reply(200, {'id': 1}),
        data: {
          'variants': [
            {'library_file_id': 7},
            {'library_file_id': 8},
          ],
          'quantity': 1,
        },
      );

      await repo.addCrossModel([7, 8]);
    });
  });
}
