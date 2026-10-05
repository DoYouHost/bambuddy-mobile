import 'dart:math';

import 'package:bambuddy_mobile/core/ams/filament_mapping.dart';
import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/data/slicer_repository.dart';
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
      'the seeded print maps onto the seeded printer as the web maps it',
      () async {
        // The whole path the mapping sheet takes, against the server's own
        // answers: the plate's used filaments (no full_slots), the live slots,
        // the grams the "prefer lowest" sort reads and the setting itself.
        final printers = PrintersRepository(dio);
        final printerId =
            ((await dio.get<List<dynamic>>('/api/v1/printers/')).data!.first
                    as Map<String, dynamic>)['id']
                as int;
        final item = (await queue.fetch()).firstWhere(
          (i) => i.libraryFileId != null,
        );

        final requirements = await SlicerRepository(dio).filamentRequirements(
          id: item.libraryFileId!,
          isArchive: false,
          fullSlots: false,
        );
        expect(requirements, isNotEmpty);
        for (final r in requirements) {
          expect(r.slotId, greaterThan(0));
          expect(
            r.trayInfoIdx,
            isNotNull,
            reason: 'tray_info_idx is always sent',
          );
        }

        final status = await printers.fetchStatus(printerId);
        final loaded = buildLoadedFilaments(status);
        expect(
          [for (final f in loaded) f.globalTrayId],
          [0, 1],
          reason: 'the seed loads red and green PLA in AMS 0',
        );

        final remain = await printers.fetchInventoryRemain(printerId);
        expect(remain, isA<Map<int, double>>());
        final settings = (await dio.get<Map<String, dynamic>>(
          '/api/v1/settings/',
        )).data!;
        expect(settings['prefer_lowest_filament'], isA<bool?>());

        final mapping = buildAmsMapping(
          buildFilamentComparison(
            requirements,
            loaded,
            const {},
            preferLowest: effectivePreferLowest(
              settings['prefer_lowest_filament'] as bool?,
              status?.amsFilamentBackup,
            ),
            inventoryByTrayId: remain,
            ftsActive: status?.filaSwitch?.installed ?? false,
          ),
        );
        expect(
          mapping,
          hasLength(requirements.map((r) => r.slotId).reduce(max)),
        );
        for (final global in mapping!) {
          expect(global == -1 || global == 0 || global == 1, isTrue);
        }
      },
    );
  });
}
