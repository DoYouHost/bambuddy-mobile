import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

void main() {
  group('queue contract', skip: contractSkipReason, () {
    late Dio dio;
    late QueueRepository queue;

    setUpAll(() async {
      dio = await authenticatedDio();
      queue = QueueRepository(dio);
    });

    test('Endpoints.queue requires trailing slash', () {
      expect(Endpoints.queue, endsWith('/'));
    });

    test('GET /queue/ decodes list into QueueItem', () async {
      final items = await queue.fetch();

      expect(items, isA<List<QueueItem>>());
      if (items.isNotEmpty) {
        final item = items.first;
        expect(item.id, greaterThan(0));
        expect(item.position, greaterThanOrEqualTo(0));
        expect(item.status, isNotNull);
        expect(item.status, isNot(equals(QueueItemStatusKind.unknown)));
      }
    });

    test('fetchActive filters for pending and printing jobs', () async {
      final active = await queue.fetchActive();

      expect(active, isA<List<QueueItem>>());
      for (final item in active) {
        expect(
          item.status,
          anyOf(QueueItemStatusKind.pending, QueueItemStatusKind.printing),
        );
      }
    });

    test('reorder endpoint responds with valid status code', () async {
      final items = await queue.fetch();
      if (items.isEmpty) return;

      final item = items.first;

      // Reorder with the current single ID preserves order
      await expectLater(
        queue.reorder([(id: item.id, position: 0)]),
        completes,
      );
    });
  });
}
