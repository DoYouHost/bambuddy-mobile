import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/data/external_links_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  final dio = testDio();
  final server = mockServer(dio);
  final repo = ExternalLinksRepository(dio);

  test('reads the links in the order the server sends them', () async {
    server.onGet(
      '/api/v1/external-links/',
      (s) => s.reply(200, [
        {'id': 2, 'name': 'B', 'url': 'http://b.lan', 'badge_count': 4},
        {'id': 1, 'name': 'A', 'url': 'http://a.lan', 'badge_count': null},
      ]),
    );
    final links = await repo.fetch();
    expect(links.map((l) => l.id), [2, 1]);
    expect(links.map((l) => l.badge), [4, 0]);
  });

  test('an empty list is no links', () async {
    server.onGet('/api/v1/external-links/', (s) => s.reply(200, <dynamic>[]));
    expect(await repo.fetch(), isEmpty);
  });

  test('a row that is not an object is dropped, not fatal', () async {
    server.onGet(
      '/api/v1/external-links/',
      (s) => s.reply(200, [
        'junk',
        {'id': 1, 'name': 'A', 'url': 'http://a.lan'},
      ]),
    );
    expect((await repo.fetch()).single.id, 1);
  });

  test('a server without the route has no links', () async {
    server.onGet(
      '/api/v1/external-links/',
      (s) => s.reply(404, {'detail': 'Not Found'}),
    );
    expect(await repo.fetch(), isEmpty);
  });

  test('a session the server refuses has no links', () async {
    server.onGet(
      '/api/v1/external-links/',
      (s) => s.reply(403, {'detail': 'Forbidden'}),
    );
    expect(await repo.fetch(), isEmpty);
  });

  test('a server error is still an error', () async {
    server.onGet('/api/v1/external-links/', (s) => s.reply(500, null));
    await expectLater(repo.fetch(), throwsA(isA<AppApiException>()));
  });
}
