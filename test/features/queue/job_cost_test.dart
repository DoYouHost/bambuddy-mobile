import 'package:bambuddy_mobile/core/ams/job_cost.dart';
import 'package:bambuddy_mobile/core/models/filament_requirement.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/inventory_repository.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/features/queue/job_cost_providers.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import 'queue_form_harness.dart';

const _red = FilamentRequirement(
  slotId: 1,
  type: 'PLA',
  color: '#FF0000',
  usedGrams: 100,
);
const _blue = FilamentRequirement(
  slotId: 2,
  type: 'PLA',
  color: '#0000FF',
  usedGrams: 50,
);

void main() {
  group('estimateJobCost', () {
    JobCost cost({
      List<FilamentRequirement> reqs = const [_red, _blue],
      List<int>? mapping = const [0, 1],
      Map<int, double> prices = const {},
      double fallback = 25,
    }) => estimateJobCost(
      requirements: reqs,
      mapping: mapping,
      costPerKgByTray: prices,
      defaultCostPerKg: fallback,
    );

    test('prices each filament at its own spool, else at the default', () {
      // 100 g at 40/kg, 50 g at the default 25/kg.
      final c = cost(prices: {0: 40});

      expect(c.total, closeTo(4 + 1.25, 1e-9));
      expect(c.anyPrice, isTrue);
    });

    test('a spool priced at nothing prices its filament at nothing', () {
      // `0 ?? default` is 0 in the web: a free spool is not the default rate.
      expect(cost(prices: {0: 0, 1: 0}).total, 0);
      expect(cost(prices: {0: 0, 1: 0}).anyPrice, isFalse);
    });

    test('a filament no tray matches costs nothing', () {
      expect(cost(mapping: const [0, -1]).total, closeTo(2.5, 1e-9));
      expect(cost(mapping: const [0]).total, closeTo(2.5, 1e-9));
    });

    test('a slot the plate does not use costs nothing', () {
      const unused = FilamentRequirement(
        slotId: 2,
        usedInPlate: false,
        usedGrams: 999,
      );

      expect(cost(reqs: const [_red, unused]).total, closeTo(2.5, 1e-9));
    });

    test('no mapping matches nothing, so there is no price either', () {
      final c = cost(mapping: null, prices: const {0: 40});

      expect(c.total, 0);
      expect(c.anyPrice, isTrue, reason: 'a priced spool still makes it a 0');
    });

    test('no default price and no spool prices makes no price at all', () {
      final c = cost(fallback: 0);

      expect(c.total, 0);
      expect(c.anyPrice, isFalse);
    });

    test('a filament with no weight adds nothing', () {
      const weightless = FilamentRequirement(slotId: 1);

      expect(cost(reqs: const [weightless], mapping: const [0]).total, 0);
    });
  });

  group('jobCostProvider', () {
    const status = PrinterStatus(
      id: 1,
      ams: [
        AmsUnit(
          id: 0,
          trays: [
            AmsTray(id: 0, trayType: 'PLA', trayColor: 'FF0000FF'),
            AmsTray(id: 1, trayType: 'PLA', trayColor: '0000FFFF'),
          ],
        ),
      ],
    );

    Future<JobCost?> read({
      required Map<String, dynamic> assignments,
      List<int>? mapping,
      List<FilamentRequirement> requirements = const [_red, _blue],
      InventoryBackend backend = InventoryBackend.native,
      Map<int, PrinterStatus> live = const {1: status},
    }) async {
      await setUpQueueForm();
      final dio = testDio();
      mockServer(dio).onGet(
        '/api/v1/inventory/assignments',
        (s) => s.reply(200, [if (assignments.isNotEmpty) assignments]),
        queryParameters: {'printer_id': 1},
      );
      final container = ProviderContainer(
        overrides: [
          noServerProfileOverride,
          ...queueFormOverrides(live: live),
          printRequirementsProvider.overrideWith(
            (ref, arg) async => requirements,
          ),
          inventoryRepositoryProvider.overrideWithValue(
            InventoryRepository(switch (backend) {
              InventoryBackend.native => NativeInventorySource(dio),
              InventoryBackend.spoolman => SpoolmanInventorySource(dio),
            }),
          ),
          serverSettingsOverride(const {'default_filament_cost': 10}),
        ],
      );
      addTearDown(container.dispose);
      final key = (
        isArchive: true,
        id: 7,
        plate: 1,
        printerId: 1,
        mapping: mappingKey(mapping),
      );
      container.listen(jobCostProvider(key), (_, _) {});
      return container.read(jobCostProvider(key).future);
    }

    Map<String, dynamic> assignment(int tray, double? price) => {
      'spool_id': 1,
      'printer_id': 1,
      'ams_id': 0,
      'tray_id': tray,
      'spool': {
        'id': 1,
        'material': 'PLA',
        'cost_per_kg': price,
        'label_weight': 1000,
      },
    };

    test(
      'prices the matched trays by their spools, the rest by the default',
      () async {
        final c = (await read(assignments: assignment(0, 40)))!;

        // red (100 g) sits on tray 0 at 40/kg; blue (50 g) on tray 1 at the 10/kg default.
        expect(c.total, closeTo(4 + 0.5, 1e-9));
        expect(c.anyPrice, isTrue);
      },
    );

    test(
      'with Spoolman every job is priced at the default, as the server does',
      () async {
        final c = (await read(
          assignments: assignment(0, 40),
          backend: InventoryBackend.spoolman,
        ))!;

        expect(c.total, closeTo(1.5, 1e-9));
        expect(c.anyPrice, isFalse);
      },
    );

    test(
      'a printer that reports no loaded slot costs nothing, as the web says N/A',
      () async {
        final c = (await read(
          assignments: assignment(0, 40),
          live: const {1: PrinterStatus(id: 1)},
        ))!;

        expect(c.total, 0);
        expect(c.anyPrice, isFalse);
      },
    );

    test('a plate that uses no filament has no preview', () async {
      expect(
        await read(assignments: assignment(0, 40), requirements: const []),
        isNull,
      );
    });
  });
}
