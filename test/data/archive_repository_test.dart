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

  test('reprint: wysyła POST /archives/82/reprint i kończy się bez wyjątku',
      () async {
    adapter.onPost(
      '/api/v1/archives/82/reprint',
      (server) => server.reply(200, null),
    );

    await repo.reprint(82, printerId: 1);
  });
}
