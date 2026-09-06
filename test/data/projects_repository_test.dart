import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/project.dart';
import 'package:bambuddy_mobile/data/projects_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late ProjectsRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    repo = ProjectsRepository(dio);
  });

  group('fileProgress', () {
    test('parsuje liczniki, tolerując brak completed_count', () async {
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

    test('404 → null (serwer sprzed 1.2.5.2, nie błąd)', () async {
      adapter.onGet(
        '/api/v1/projects/7/file-progress',
        (s) => s.reply(404, {'detail': 'Not Found'}),
      );

      expect(await repo.fileProgress(7), isNull);
    });

    test('500 to błąd, nie brak funkcji', () async {
      adapter.onGet(
        '/api/v1/projects/7/file-progress',
        (s) => s.reply(500, {'detail': 'boom'}),
      );

      expect(repo.fileProgress(7), throwsA(isA<AppApiException>()));
    });
  });

  group('completeSetsFor', () {
    test('komplet to najmniejsza liczba wydruków po plikach', () {
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

    test('plik bez wpisu liczy się jako zero', () {
      // Serwer zwraca tylko pliki, które cokolwiek ukończyły — brak wpisu nie
      // może udawać, że część jest gotowa.
      final done = completeSetsFor(
        const [1, 2],
        const [ProjectFileProgress(fileId: 1, completedCount: 4)],
      );
      expect(done, 0);
    });

    test('projekt bez plików nie ma kompletów', () {
      expect(completeSetsFor(const [], const []), 0);
    });

    test('każdy plik wydrukowany po tyle samo → tyle kompletów', () {
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

  group('target_sets w body', () {
    test('pominięte, gdy nieustawione (stary serwer nie dostaje pola)', () {
      expect(
        const ProjectCreate(name: 'X').toMap().containsKey('target_sets'),
        isFalse,
      );
    });

    test('wysyłane, gdy ustawione', () {
      expect(const ProjectUpdate(targetSets: 4).toMap()['target_sets'], 4);
    });
  });
}
