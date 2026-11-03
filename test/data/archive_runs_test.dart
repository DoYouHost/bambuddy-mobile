import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:bambuddy_mobile/data/print_log_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late ArchiveRepository repo;
  late RequestLog sent;
  const runsPath = '/api/v1/archives/5/runs';

  setUp(() {
    dio = testDio();
    adapter = mockServer(dio);
    sent = captureRequests(dio);
    repo = ArchiveRepository(dio, ServerVersionService(dio));
  });

  void replyVersion(String version) => adapter.onGet(
    '/api/v1/updates/version',
    (s) => s.reply(200, {'version': version, 'repo': 'x/y'}),
  );

  // A run as 1.3.1 sends it; an older server sends the keys up to
  // `user_verdict` and none of the per-print ones.
  Map<String, dynamic> run(int id, [Map<String, dynamic> extra = const {}]) => {
    'id': id,
    'archive_id': 5,
    'status': 'completed',
    'created_at': '2026-11-01T10:00:00',
    'user_verdict': null,
    ...extra,
  };

  Map<String, dynamic> newRun(
    int id, [
    Map<String, dynamic> extra = const {},
  ]) => run(id, {
    'plate_id': null,
    'notes': null,
    'photos': null,
    'timelapse_path': null,
    'user_verdict_source': null,
    'confirm_requested': null,
    'duration_unmeasured': null,
    'estimate_seconds': null,
    'estimate_grams': null,
    ...extra,
  });

  group('runs', () {
    test('reads each print with its own fields', () async {
      adapter.onGet(
        runsPath,
        (s) => s.reply(200, {
          'items': [
            newRun(2, {
              'plate_id': 2,
              'user_verdict': 'reject',
              'user_verdict_source': 'plate_clear',
              'confirm_requested': true,
              'duration_unmeasured': true,
              'notes': 'Warped corner',
              'photos': ['finish_2.jpg'],
              'timelapse_path': 'archive/5/runs/2/timelapse.mp4',
              'estimate_seconds': 3600,
              'estimate_grams': 25.5,
            }),
            newRun(1),
          ],
          'total': 2,
        }),
      );

      final rows = await repo.runs(5);

      expect(rows.map((r) => r.id), [2, 1]);
      final first = rows.first;
      expect(first.plateId, 2);
      expect(first.userVerdict, PrintVerdict.reject);
      expect(first.userVerdictSource, 'plate_clear');
      expect(first.durationUnmeasured, isTrue);
      expect(first.notes, 'Warped corner');
      expect(first.photos, ['finish_2.jpg']);
      expect(first.timelapsePath, isNotNull);
      expect(first.estimateSeconds, 3600);
      expect(first.estimateGrams, 25.5);
      // Null photos is a print logged before prints kept their own: it shares
      // the archive's, which an empty list would not.
      expect(rows.last.photos, isNull);
    });

    test('a print that asked and got no answer awaits a verdict', () async {
      adapter.onGet(
        runsPath,
        (s) => s.reply(200, {
          'items': [
            newRun(1, {'confirm_requested': true}),
            newRun(2, {'confirm_requested': true, 'status': 'failed'}),
            newRun(3, {'confirm_requested': true, 'user_verdict': 'good'}),
          ],
          'total': 3,
        }),
      );

      final rows = await repo.runs(5);

      expect(rows.map((r) => r.awaitsVerdict), [true, false, false]);
    });

    test('a malformed body reads as no prints', () async {
      adapter.onGet(runsPath, (s) => s.reply(200, {'items': 'nope'}));

      expect(await repo.runs(5), isEmpty);
    });
  });

  group('runsCapability', () {
    test('a row with the per-print keys settles it on', () async {
      replyVersion('1.2.5');
      adapter.onGet(
        runsPath,
        (s) => s.reply(200, {
          'items': [newRun(1)],
          'total': 1,
        }),
      );

      await repo.runs(5);

      expect(await repo.runsCapability.supported, isTrue);
    });

    test('a row without them settles it off', () async {
      replyVersion('1.3.1');
      adapter.onGet(
        runsPath,
        (s) => s.reply(200, {
          'items': [run(1)],
          'total': 1,
        }),
      );

      await repo.runs(5);

      expect(await repo.runsCapability.supported, isFalse);
    });

    test('an archive with no prints leaves it to the version', () async {
      replyVersion('1.2.5.7');
      adapter.onGet(runsPath, (s) => s.reply(200, {'items': [], 'total': 0}));

      await repo.runs(5);

      expect(await repo.runsCapability.supported, isFalse);
    });
  });

  group('setVerdict', () {
    Map<String, dynamic>? sentBody() => sent.last.data as Map<String, dynamic>?;

    void replyArchive() => adapter.onPatch(
      '/api/v1/archives/5',
      (s) => s.reply(200, {
        'id': 5,
        'filename': 'a.3mf',
        'status': 'completed',
        'confirm_requested': true,
        'user_verdict': 'good',
      }),
      data: Matchers.any,
    );

    test('names the print it is for', () async {
      replyArchive();

      await repo.setVerdict(5, PrintVerdict.good, runId: 9);

      expect(sentBody(), containsPair('run_id', 9));
    });

    test('without a print it sends no run_id', () async {
      replyArchive();

      await repo.setVerdict(5, PrintVerdict.good);

      expect(sentBody()!.containsKey('run_id'), isFalse);
    });
  });

  group('print note', () {
    late PrintLogRepository log;

    setUp(() => log = PrintLogRepository(dio, ServerVersionService(dio)));

    void replyEntry() => adapter.onPatch(
      '/api/v1/print-log/9',
      (s) => s.reply(200, newRun(9, {'notes': 'ok'})),
      data: Matchers.any,
    );

    test('sends the note and nothing else', () async {
      replyEntry();

      final entry = await log.updateEntry(9, notes: 'ok');

      expect(sent.last.data, {'notes': 'ok'});
      expect(entry.notes, 'ok');
    });

    test('an empty note is sent as one, which clears it', () async {
      replyEntry();

      await log.updateEntry(9, notes: '');

      expect(sent.last.data, {'notes': ''});
    });
  });
}
