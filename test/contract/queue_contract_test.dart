import 'dart:math';

import 'package:bambuddy_mobile/core/ams/filament_mapping.dart';
import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
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
        expect(remain.grams, isA<Map<int, double>>());
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
            inventoryByTrayId: remain.grams,
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

    test('a save without ams_mapping keeps the stored one', () async {
      // What the edit form relies on when the printer reports no loaded slot:
      // like the web, it sends no mapping then, and that must not clear it.
      // On a printer job — a model job keeps no mapping at all (#3239).
      final printerId =
          ((await dio.get<List<dynamic>>('/api/v1/printers/')).data!.first
                  as Map<String, dynamic>)['id']
              as int;
      final item = (await queue.fetch()).firstWhere(
        (i) => i.libraryFileId != null,
      );
      addTearDown(
        () => queue.updateItem(
          item.id,
          printerId: item.printerId,
          targetModel: item.targetModel,
          amsMapping: item.amsMapping,
        ),
      );
      await queue.updateItem(item.id, printerId: printerId, targetModel: null);

      await queue.setAmsMapping(item.id, [1]);
      await queue.updateItem(item.id, manualStart: item.manualStart);
      final kept = (await queue.fetch()).firstWhere((i) => i.id == item.id);
      expect(kept.amsMapping, [1]);
    });

    test('a printer job keeps its changed slots, null clears them', () async {
      // What the edit form sends for one printer (`printerOverridesForPlate`
      // on the web). The server narrows the list to the slots the plate
      // prints, so the slot comes from the plate's own requirements.
      final printerId =
          ((await dio.get<List<dynamic>>('/api/v1/printers/')).data!.first
                  as Map<String, dynamic>)['id']
              as int;
      final item = (await queue.fetch()).firstWhere(
        (i) => i.libraryFileId != null,
      );
      final slot = (await SlicerRepository(dio).filamentRequirements(
        id: item.libraryFileId!,
        isArchive: false,
        fullSlots: false,
      )).first.slotId;
      addTearDown(
        () => queue.updateItem(
          item.id,
          printerId: item.printerId,
          targetModel: item.targetModel,
          filamentOverrides: item.filamentOverrides,
        ),
      );

      await queue.updateItem(
        item.id,
        printerId: printerId,
        targetModel: null,
        filamentOverrides: [
          {
            'slot_id': slot,
            'type': 'PETG',
            'color': '#00FF00',
            'color_name': 'Green',
            'tray_info_idx': 'GFG00',
            'force_color_match': true,
          },
        ],
      );
      final kept = (await queue.fetch()).firstWhere((i) => i.id == item.id);
      expect(kept.filamentOverrides?.single['force_color_match'], isTrue);
      // The stored variant comes back for the next edit to keep.
      expect(kept.filamentOverrides?.single['tray_info_idx'], 'GFG00');

      await queue.updateItem(item.id, filamentOverrides: null);
      final cleared = (await queue.fetch()).firstWhere((i) => i.id == item.id);
      expect(cleared.filamentOverrides, isNull);
    });

    test('a rack pick comes back keyed by group, null clears it', () async {
      // What the mapping's rack picker writes (#1784): every group once one is
      // picked, as `{group: position}` with the keys stringified on the wire.
      final printerId =
          ((await dio.get<List<dynamic>>('/api/v1/printers/')).data!.first
                  as Map<String, dynamic>)['id']
              as int;
      final item = (await queue.fetch()).firstWhere(
        (i) => i.libraryFileId != null,
      );
      addTearDown(
        () => queue.updateItem(
          item.id,
          printerId: item.printerId,
          targetModel: item.targetModel,
          nozzleRackChoice: item.nozzleRackChoice,
        ),
      );

      await queue.updateItem(
        item.id,
        printerId: printerId,
        targetModel: null,
        nozzleRackChoice: const {1: 3, 2: 3},
      );
      final kept = (await queue.fetch()).firstWhere((i) => i.id == item.id);
      // Two groups on one position is stored as sent: refusing it is the
      // dispatcher's job, and the picker leaves it to that, as the web does.
      expect(kept.nozzleRackChoice, {1: 3, 2: 3});

      await queue.updateItem(item.id, nozzleRackChoice: null);
      final cleared = (await queue.fetch()).firstWhere((i) => i.id == item.id);
      expect(cleared.nozzleRackChoice, isNull);
    });

    test(
      'a cancelled item reaches the history, and leaves it on delete',
      () async {
        final file = (await LibraryRepository(
          dio,
        ).listFiles()).firstWhere((f) => f.filename == 'contract-probe.3mf');
        final before = {for (final i in await queue.fetch()) i.id};
        await queue.addFromLibraryFile(
          file.id,
          options: const QueueCreateOptions(manualStart: true),
        );
        final id = (await queue.fetch())
            .firstWhere((i) => !before.contains(i.id))
            .id;

        await queue.cancel(id);
        final history = await queue.fetchHistory();
        final cancelled = history.singleWhere((i) => i.id == id);
        expect(cancelled.statusKind, QueueItemStatusKind.cancelled);
        // The row's "added by"; the contract user queued it.
        expect(cancelled.createdByUsername, isNotEmpty);
        expect(
          history.every(
            (i) => const {
              QueueItemStatusKind.completed,
              QueueItemStatusKind.failed,
              QueueItemStatusKind.skipped,
              QueueItemStatusKind.cancelled,
            }.contains(i.statusKind),
          ),
          isTrue,
        );

        expect(await queue.delete(id), isTrue);
        expect((await queue.fetchHistory()).any((i) => i.id == id), isFalse);
      },
    );
  });
}
