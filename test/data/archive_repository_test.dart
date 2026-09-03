import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/no_3mf_warning.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late ArchiveRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    repo = ArchiveRepository(dio);
  });

  test('list: parsuje listę, id i displayName są poprawne', () async {
    adapter.onGet(
      '/api/v1/archives/',
      (server) => server.reply(200, [readFixture('archive.json')]),
    );

    final archives = await repo.list();

    expect(archives, hasLength(1));
    expect(archives.first.id, 82);
    expect(archives.first.displayName, 'The Smoothy - Y Splitter Connector');
  });

  test('byId: GET /archives/82 zwraca pojedynczy wpis ze zdjęciami', () async {
    final withPhoto = {
      ...readFixture('archive.json') as Map<String, dynamic>,
      'photos': ['finish_20260815_120000_ab12cd34.jpg'],
    };
    adapter.onGet(
      '/api/v1/archives/82',
      (server) => server.reply(200, withPhoto),
    );

    final archive = await repo.byId(82);

    expect(archive.id, 82);
    expect(archive.photos, ['finish_20260815_120000_ab12cd34.jpg']);
    expect(archive.hasPhotos, isTrue);
  });

  test('search: parsuje listę wyników wyszukiwania', () async {
    adapter.onGet(
      '/api/v1/archives/search',
      (server) => server.reply(200, [readFixture('archive.json')]),
    );

    final archives = await repo.search('smoothy');

    expect(archives, hasLength(1));
  });

  test('toggleFavorite: POST /archives/82/favorite zwraca zaktualizowany wpis',
      () async {
    final favorited = {
      ...readFixture('archive.json') as Map<String, dynamic>,
      'is_favorite': true,
    };
    adapter.onPost(
      '/api/v1/archives/82/favorite',
      (server) => server.reply(200, favorited),
    );

    final archive = await repo.toggleFavorite(82);

    expect(archive.id, 82);
    expect(archive.isFavorite, isTrue);
  });

  test('delete: wysyła DELETE /archives/82 z purge_stats=false domyślnie',
      () async {
    adapter.onDelete(
      '/api/v1/archives/82',
      (server) => server.reply(200, null),
      queryParameters: {'purge_stats': false},
    );

    await repo.delete(82);
  });

  test('delete: purgeStats=true ustawia purge_stats=true w query', () async {
    adapter.onDelete(
      '/api/v1/archives/82',
      (server) => server.reply(200, null),
      queryParameters: {'purge_stats': true},
    );

    await repo.delete(82, purgeStats: true);
  });

  test('purgePreview: parsuje count/total_bytes i przekazuje próg', () async {
    adapter.onGet(
      '/api/v1/archives/purge/preview',
      (server) => server.reply(200, {
        'count': 12,
        'total_bytes': 2048,
        'sample_filenames': ['a.3mf', 'b.3mf'],
        'older_than_days': 90,
      }),
      queryParameters: {'older_than_days': 90, 'purge_stats': false},
    );

    final preview = await repo.purgePreview(olderThanDays: 90);

    expect(preview.count, 12);
    expect(preview.totalBytes, 2048);
    expect(preview.sampleFilenames, ['a.3mf', 'b.3mf']);
    expect(preview.olderThanDays, 90);
  });

  test('purge: POST z older_than_days/purge_stats zwraca deleted', () async {
    adapter.onPost(
      '/api/v1/archives/purge',
      (server) => server.reply(200, {'deleted': 7, 'purge_stats': true}),
      data: {'older_than_days': 30, 'purge_stats': true},
    );

    final deleted = await repo.purge(olderThanDays: 30, purgeStats: true);

    expect(deleted, 7);
  });

  group('setFilamentGrams', () {
    Map<String, dynamic> archiveWith(Object? grams) => {
          ...readFixture('archive.json') as Map<String, dynamic>,
          'filament_used_grams': grams,
        };

    test('sends the weight and reads back the stored one', () async {
      adapter.onPatch(
        '/api/v1/archives/82',
        (server) => server.reply(200, archiveWith(42.0)),
        data: {'filament_used_grams': 42.0},
      );

      final result = await repo.setFilamentGrams(82, 42.0);

      expect(result.archive.filamentUsedGrams, 42.0);
      expect(result.applied, isTrue);
    });

    // The case the whole return type exists for. A server older than the field
    // still has the route and still answers 200 — its request model just drops
    // the key it cannot name — so the archive comes back with the weight it had
    // and the status code says nothing at all.
    test('a server that drops the key answers 200 and changes nothing',
        () async {
      adapter.onPatch(
        '/api/v1/archives/82',
        (server) => server.reply(200, archiveWith(17.1)),
        data: {'filament_used_grams': 42.0},
      );

      final result = await repo.setFilamentGrams(82, 42.0);

      expect(result.applied, isFalse);
      expect(result.archive.filamentUsedGrams, 17.1,
          reason: 'the row the user is looking at, not the one they asked for');
    });

    // A present null, never an omitted key: the server applies `exclude_unset`,
    // so leaving it out means "do not touch this column" and would clear
    // nothing.
    test('clearing sends the key with a null', () async {
      adapter.onPatch(
        '/api/v1/archives/82',
        (server) => server.reply(200, archiveWith(null)),
        data: {'filament_used_grams': null},
      );

      final result = await repo.setFilamentGrams(82, null);

      expect(result.archive.filamentUsedGrams, isNull);
      expect(result.applied, isTrue);
    });

    test('a clear an old server ignored is not reported as done', () async {
      adapter.onPatch(
        '/api/v1/archives/82',
        (server) => server.reply(200, archiveWith(17.1)),
        data: {'filament_used_grams': null},
      );

      expect((await repo.setFilamentGrams(82, null)).applied, isFalse);
    });

    // Why the comparison has a tolerance: the figure goes out as JSON, through
    // a float column and back, and a difference in the fourth decimal is the
    // same weight. The case it must not swallow is a whole typed number apart.
    test('a float round trip is still the weight that was sent', () async {
      adapter.onPatch(
        '/api/v1/archives/82',
        (server) => server.reply(200, archiveWith(42.30000000000001)),
        data: {'filament_used_grams': 42.3},
      );

      expect((await repo.setFilamentGrams(82, 42.3)).applied, isTrue);
    });

    // The field checks the server's own bounds before sending, so a refusal
    // here means the two drifted apart — and then the server's sentence is
    // worth more than ours.
    test('a refused weight keeps what the server said', () async {
      adapter.onPatch(
        '/api/v1/archives/82',
        (server) => server.reply(422, {
          'detail': [
            {'msg': 'Input should be less than or equal to 100000'},
          ],
        }),
        data: {'filament_used_grams': 200000.0},
      );

      await expectLater(
        repo.setFilamentGrams(82, 200000.0),
        throwsA(isA<ApiException>().having((e) => e.detail, 'detail',
            contains('less than or equal to 100000'))),
      );
    });
  });

  group('plates', () {
    test('reads the plate rows of a multi-plate archive', () async {
      adapter.onGet(
        '/api/v1/archives/82/plates',
        (server) => server.reply(200, {
          'archive_id': 82,
          'filename': 'multi.gcode.3mf',
          'plates': [
            {'index': 1, 'name': 'Left', 'has_thumbnail': true,
              'thumbnail_url': '/api/v1/archives/82/plate-thumbnail/1'},
            {'index': 2, 'name': 'Right', 'has_thumbnail': false},
          ],
          'is_multi_plate': true,
          'has_gcode': true,
        }),
      );

      final plates = await repo.plates(82);

      expect(plates.isMultiPlate, isTrue);
      expect(plates.plates.map((p) => p.index), [1, 2]);
      expect(plates.byIndex(1)?.thumbnailPath,
          '/api/v1/archives/82/plate-thumbnail/1');
    });

    // One request, both answers: the slice screen's "as designed" gate used to
    // ask the same route a second time through the slicer repository.
    test('the same read carries what the 3MF was prepared with', () async {
      adapter.onGet(
        '/api/v1/archives/82/plates',
        (server) => server.reply(200, {
          'plates': [
            {'index': 1, 'has_thumbnail': false},
          ],
          'embedded_printer': 'Bambu Lab X2D 0.6 nozzle',
          'embedded_process': '0.30mm Standard @BBL X2D 0.6 nozzle',
          'design_overrides': [],
        }),
      );

      final plates = await repo.plates(82);

      expect(plates.embedded.printer, 'Bambu Lab X2D 0.6 nozzle');
      expect(plates.embedded.isAvailable, isTrue);
    });

    // A server older than the route, an archive whose file is gone, a plain
    // .gcode that was never a 3MF: three causes, one correct answer — there is
    // no plate to pick, so the form must look exactly as it did before.
    test('a 404 leaves no plate to choose instead of throwing', () async {
      adapter.onGet(
        '/api/v1/archives/82/plates',
        (server) => server.reply(404, {'detail': 'Not Found'}),
      );

      final plates = await repo.plates(82);

      expect(plates.plates, isEmpty);
      expect(plates.isMultiPlate, isFalse);
    });
  });

  group('no3mfWarning', () {
    test('reads the flag and the reason', () async {
      adapter.onGet(
        '/api/v1/archives/no-3mf-warning',
        (server) =>
            server.reply(200, {'has_fallback': true, 'reason': 'internal_storage'}),
      );

      final warning = await repo.no3mfWarning();

      expect(warning.hasFallback, isTrue);
      expect(warning.reason, No3mfReason.internalStorage);
    });

    // A 401 is the session ending, which the app has to act on; a 403 is one
    // route the account cannot have. Only the first may reach the UI.
    test('an expired session still bubbles up', () async {
      adapter.onGet(
        '/api/v1/archives/no-3mf-warning',
        (server) => server.reply(401, {'detail': 'Not authenticated'}),
      );

      await expectLater(repo.no3mfWarning(), throwsA(isA<AuthException>()));
    });

    test('an unreachable route means no nudge, not an error', () async {
      adapter.onGet(
        '/api/v1/archives/no-3mf-warning',
        (server) => server.reply(403, {'detail': 'Forbidden'}),
      );

      final warning = await repo.no3mfWarning();

      expect(warning.hasFallback, isFalse);
    });
  });
}
