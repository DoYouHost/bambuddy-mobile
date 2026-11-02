import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/calibration_option.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

/// `PATCH /queue/bulk` and `POST /queue/printer/{id}/resume`: the two queue
/// routes the web uses and the app did not. Both answer 200 for work that was
/// partly or wholly not done, so what the counts say is the contract.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late QueueRepository repo;

  setUp(() {
    dio = testDio();
    adapter = mockServer(dio);
    repo = QueueRepository(dio);
  });

  group('bulkUpdate', () {
    test('sends the ids and only the keys that were changed', () async {
      adapter.onPatch(
        '/api/v1/queue/bulk',
        (server) => server.reply(200, {'updated_count': 2, 'skipped_count': 0}),
        data: {
          'item_ids': [4, 9],
          'timelapse': true,
          'vibration_cali': false,
        },
      );
      final sent = captureRequests(dio);

      final result = await repo.bulkUpdate([
        4,
        9,
      ], const QueueBulkChanges(timelapse: true, vibrationCali: false));

      expect(sent.calls, ['PATCH /api/v1/queue/bulk']);
      expect(result, (updated: 2, skipped: 0));
    });

    test('an untouched printer is absent, null unassigns, an id assigns', () {
      expect(
        const QueueBulkChanges(timelapse: true).toJson(triState: true),
        isNot(contains('printer_id')),
        reason: 'a printer key that is present moves every selected item',
      );
      expect(const QueueBulkChanges(printerId: null).toJson(triState: true), {
        'printer_id': null,
      }, reason: 'null is how the route takes an item off its printer');
      expect(const QueueBulkChanges(printerId: 7).toJson(triState: true), {
        'printer_id': 7,
      });
    });

    test('isEmpty: no change at all, and an unassign is a change', () {
      expect(const QueueBulkChanges().isEmpty, isTrue);
      expect(const QueueBulkChanges(printerId: null).isEmpty, isFalse);
      expect(const QueueBulkChanges(useAms: false).isEmpty, isFalse);
    });

    test('calibration: on and off are booleans, auto is a string', () {
      expect(
        const QueueBulkChanges(
          bedLevelling: CalibrationOption.on,
          flowCali: CalibrationOption.off,
          nozzleOffsetCali: CalibrationOption.auto,
        ).toJson(triState: true),
        {
          'bed_levelling': true,
          'flow_cali': false,
          'nozzle_offset_cali': 'auto',
        },
      );
    });

    test('calibration: auto is left out where the server cannot store it', () {
      // A boolean here would rewrite `auto` as plain on-or-off on every
      // selected item, none of which the user looked at.
      expect(
        const QueueBulkChanges(
          bedLevelling: CalibrationOption.auto,
          timelapse: true,
        ).toJson(triState: false),
        {'timelapse': true},
      );
    });

    test('skipped items are counted, not hidden', () async {
      adapter.onPatch(
        '/api/v1/queue/bulk',
        (server) => server.reply(200, {'updated_count': 1, 'skipped_count': 3}),
        data: {
          'item_ids': [1, 2, 3, 4],
          'manual_start': false,
        },
      );

      final result = await repo.bulkUpdate([
        1,
        2,
        3,
        4,
      ], const QueueBulkChanges(manualStart: false));

      expect(result, (updated: 1, skipped: 3));
    });

    test(
      'a body without counts reads as nothing done, not as a crash',
      () async {
        adapter.onPatch(
          '/api/v1/queue/bulk',
          (server) => server.reply(200, null),
          data: Matchers.any,
        );

        expect(
          await repo.bulkUpdate([1], const QueueBulkChanges(useAms: true)),
          (updated: 0, skipped: 0),
        );
      },
    );

    test('keeps the detail of a 400 and tells a 403 apart', () async {
      adapter
        ..onPatch(
          '/api/v1/queue/bulk',
          (server) => server.reply(400, {'detail': 'Printer not found'}),
          data: {
            'item_ids': [1],
            'printer_id': 99,
          },
        )
        ..onPatch(
          '/api/v1/queue/bulk',
          (server) => server.reply(403, {'detail': 'Permission denied'}),
          data: {
            'item_ids': [1],
            'timelapse': true,
          },
        );

      final refused = await _failureOf(
        () => repo.bulkUpdate([1], const QueueBulkChanges(printerId: 99)),
      );
      final forbidden = await _failureOf(
        () => repo.bulkUpdate([1], const QueueBulkChanges(timelapse: true)),
      );

      expect(refused.detail, 'Printer not found');
      expect(forbidden.code, AppErrorCode.forbidden);
    });
  });

  group('resumeAfterFailure', () {
    test('posts to the printer and reads both counts', () async {
      adapter.onPost(
        '/api/v1/queue/printer/3/resume',
        (server) => server.reply(200, {'acknowledged': 1, 'restored': 4}),
      );
      final sent = captureRequests(dio);

      final result = await repo.resumeAfterFailure(3);

      expect(sent.calls, ['POST /api/v1/queue/printer/3/resume']);
      expect(result, (acknowledged: 1, restored: 4));
    });

    test(
      'a printer with no gate answers zeros, which is not a failure',
      () async {
        adapter.onPost(
          '/api/v1/queue/printer/3/resume',
          (server) => server.reply(200, {'acknowledged': 0, 'restored': 0}),
        );

        expect(await repo.resumeAfterFailure(3), (
          acknowledged: 0,
          restored: 0,
        ));
      },
    );

    test('a printer that is gone is a 404, not a crash', () async {
      adapter.onPost(
        '/api/v1/queue/printer/8/resume',
        (server) => server.reply(404, {'detail': 'Printer not found'}),
      );

      final error = await _failureOf(() => repo.resumeAfterFailure(8));

      expect(error.statusCode, 404);
    });

    test('a 403 is a refusal, not an outage', () async {
      adapter.onPost(
        '/api/v1/queue/printer/3/resume',
        (server) => server.reply(403, {'detail': 'Permission denied'}),
      );

      final error = await _failureOf(() => repo.resumeAfterFailure(3));

      expect(error.code, AppErrorCode.forbidden);
    });
  });
}

Future<AppApiException> _failureOf(Future<Object?> Function() send) async {
  try {
    await send();
  } on AppApiException catch (e) {
    return e;
  }
  fail('expected the route to be refused');
}
