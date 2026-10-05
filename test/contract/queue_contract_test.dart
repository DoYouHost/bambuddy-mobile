import 'package:bambuddy_mobile/core/ams/slot_addressing.dart';
import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/features/queue/queue_mapping_sheet.dart';
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
        expect(item.statusKind, isNot(equals(QueueItemStatusKind.unknown)));
      }
    });

    test('fetchActive filters for pending and printing jobs', () async {
      final active = await queue.fetchActive();

      expect(active, isA<List<QueueItem>>());
      for (final item in active) {
        expect(
          item.statusKind,
          anyOf(QueueItemStatusKind.pending, QueueItemStatusKind.printing),
        );
      }
    });

    test('reorder endpoint responds with valid status code', () async {
      final items = await queue.fetch();
      if (items.isEmpty) return;

      final item = items.first;

      // Reorder with the current single ID preserves order
      await expectLater(queue.reorder([(id: item.id, position: 0)]), completes);
    });

    test(
      'the mapping offers exactly the loaded slots of the live status',
      () async {
        // Nothing from the inventory: the web has no other source.
        final printers = (await dio.get<List<dynamic>>(
          '/api/v1/printers/',
        )).data!;
        final printerId = (printers.first as Map<String, dynamic>)['id'] as int;
        final status = await PrintersRepository(dio).fetchStatus(printerId);
        final loaded = [
          for (final unit in status?.ams ?? const [])
            for (final tray in unit.trays ?? const [])
              if (tray.trayType?.isNotEmpty ?? false)
                globalTrayId(amsId: unit.id ?? 0, trayId: tray.id ?? 0),
          for (final ext in status?.externalSpools ?? const [])
            if (ext.trayType?.isNotEmpty ?? false) ext.id ?? externalTrayIdBase,
        ];
        expect(loaded, isNotEmpty, reason: 'the seed loads two PLA slots');

        final container = contractContainer(dio);
        container.listen(printerTraysProvider(printerId), (_, _) {});
        final trays = await container.read(
          printerTraysProvider(printerId).future,
        );

        expect([for (final t in trays) t.global], loaded);
      },
    );
  });
}
