import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/project.dart';
import 'package:bambuddy_mobile/data/projects_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late ProjectsRepository repo;

  setUp(() {
    dio = testDio();
    adapter = DioAdapter(dio: dio);
    repo = ProjectsRepository(dio);
  });

  group('fileProgress', () {
    test('parses counters, tolerating a missing completed_count', () async {
      adapter.onGet(
        '/api/v1/projects/7/file-progress',
        (s) => s.reply(200, [
          {'file_id': 11, 'completed_count': 3},
          {'file_id': 12},
        ]),
      );

      final rows = await repo.fileProgress(7);

      expect(rows, hasLength(2));
      expect(rows!.first.completedCount, 3);
      expect(rows.last.completedCount, 0);
    });

    test('404 → null (server before 1.2.5.2, not an error)', () async {
      adapter.onGet(
        '/api/v1/projects/7/file-progress',
        (s) => s.reply(404, {'detail': 'Not Found'}),
      );

      expect(await repo.fileProgress(7), isNull);
    });

    test('500 is an error, not a missing feature', () async {
      adapter.onGet(
        '/api/v1/projects/7/file-progress',
        (s) => s.reply(500, {'detail': 'boom'}),
      );

      expect(repo.fileProgress(7), throwsA(isA<AppApiException>()));
    });
  });

  group('completeSetsFor', () {
    test('a complete set is the smallest print count across files', () {
      final done = completeSetsFor(
        const [1, 2, 3],
        const [
          ProjectFileProgress(fileId: 1, completedCount: 10),
          ProjectFileProgress(fileId: 2, completedCount: 2),
          ProjectFileProgress(fileId: 3, completedCount: 5),
        ],
      );
      expect(done, 2);
    });

    test('a file without an entry counts as zero', () {
      // The server returns only files that completed something — a missing
      // entry must not pretend a part is ready.
      final done = completeSetsFor(
        const [1, 2],
        const [ProjectFileProgress(fileId: 1, completedCount: 4)],
      );
      expect(done, 0);
    });

    test('a project without files has no complete sets', () {
      expect(completeSetsFor(const [], const []), 0);
    });

    test('every file printed the same number of times → that many sets', () {
      final done = completeSetsFor(
        const [1, 2],
        const [
          ProjectFileProgress(fileId: 1, completedCount: 3),
          ProjectFileProgress(fileId: 2, completedCount: 3),
        ],
      );
      expect(done, 3);
    });
  });

  group('target_sets in the body', () {
    test('omitted when unset (an old server does not get the field)', () {
      expect(
        const ProjectCreate(name: 'X').toMap().containsKey('target_sets'),
        isFalse,
      );
    });

    test('sent when set', () {
      expect(const ProjectUpdate(targetSets: 4).toMap()['target_sets'], 4);
    });
  });
}
