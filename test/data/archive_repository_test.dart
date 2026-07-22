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
}
