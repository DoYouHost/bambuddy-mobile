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
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    repo = QueueRepository(dio);
  });

  test('fetch: parsuje listę, id i statusKind są poprawne', () async {
    adapter.onGet(
      '/api/v1/queue/',
      (server) => server.reply(200, [readFixture('queue_item.json')]),
    );

    final items = await repo.fetch();

    expect(items, hasLength(1));
    expect(items.first.id, 78);
    expect(items.first.statusKind, QueueItemStatusKind.printing);
  });

  test('reorder: wysyła POST i kończy się bez wyjątku', () async {
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
    // Brak wyjątku = sukces.
  });

  test('delete: wysyła DELETE /queue/78 i kończy się bez wyjątku', () async {
    adapter.onDelete(
      '/api/v1/queue/78',
      (server) => server.reply(200, null),
    );

    await repo.delete(78);
  });

  test('start: wysyła POST /queue/78/start i kończy się bez wyjątku', () async {
    adapter.onPost(
      '/api/v1/queue/78/start',
      (server) => server.reply(200, null),
    );

    await repo.start(78);
  });

  test('cancel: wysyła POST /queue/78/cancel i kończy się bez wyjątku',
      () async {
    adapter.onPost(
      '/api/v1/queue/78/cancel',
      (server) => server.reply(200, null),
    );

    await repo.cancel(78);
  });

  test('addFromArchive: wysyła POST /queue/ i kończy się bez wyjątku',
      () async {
    adapter.onPost(
      '/api/v1/queue/',
      (server) => server.reply(200, null),
      data: {'archive_id': 77, 'printer_id': 1, 'quantity': 1},
    );

    await repo.addFromArchive(77, printerId: 1);
  });
}
