import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/data/announcements_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  final dio = testDio();
  final server = mockServer(dio);
  final repo = AnnouncementsRepository(dio);

  test('reads the inbox', () async {
    server.onGet(
      '/api/v1/announcements',
      (s) => s.reply(200, {
        'visible': true,
        'announcements': [
          {
            'id': 'a1',
            'level': 'important',
            'texts': {
              'en': {'title': 'T', 'body': 'B'},
            },
          },
        ],
      }),
    );
    final feed = await repo.fetch();
    expect(feed.visible, isTrue);
    expect(feed.items.single.id, 'a1');
  });

  test('a server without the route has no inbox', () async {
    server.onGet(
      '/api/v1/announcements',
      (s) => s.reply(404, {'detail': 'Not Found'}),
    );
    expect((await repo.fetch()).visible, isFalse);
  });

  test('a server error is still an error', () async {
    server.onGet('/api/v1/announcements', (s) => s.reply(500, null));
    await expectLater(repo.fetch(), throwsA(isA<AppApiException>()));
  });

  test('marks one read by its id', () async {
    final log = captureRequests(dio);
    server.onPost('/api/v1/announcements/a1/read', (s) => s.reply(204, null));
    await repo.markRead('a1');
    expect(log.calls, ['POST /api/v1/announcements/a1/read']);
  });
}
