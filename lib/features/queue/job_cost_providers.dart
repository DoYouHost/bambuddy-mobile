import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ams/job_cost.dart';
import '../../core/ams/slot_addressing.dart';
import '../../data/inventory_source.dart';
import '../../providers.dart';
import '../slicer/slice_providers.dart';
import 'queue_mapping_sheet.dart';

/// What a job is priced against: the file and plate it prints, the printer it is
/// aimed at, and the mapping the user has picked so far. The mapping is a string
/// because a list has no equality and the key would never match twice.
typedef JobCostKey = ({
  bool isArchive,
  int id,
  int plate,
  int printerId,
  String mapping,
});

String mappingKey(List<int>? mapping) => mapping?.join(',') ?? '';

/// The job's cost preview, or null where there is nothing to price against: the
/// printer reports no loaded slot, so there is no mapping. Native inventory only —
/// with Spoolman the server prices every job at the default (`_default_cost_per_kg`
/// is the only rate it uses there), and so does this.
final jobCostProvider = FutureProvider.autoDispose.family<JobCost?, JobCostKey>(
  (ref, key) async {
    final requirements = await ref.watch(
      printRequirementsProvider((
        isArchive: key.isArchive,
        id: key.id,
        plate: key.plate,
      )).future,
    );
    final mapping = await queueMappingToSend(
      requirements: requirements,
      printers: ref.watch(printersRepositoryProvider),
      printerId: key.printerId,
      startFrom: key.mapping.isEmpty
          ? null
          : [for (final n in key.mapping.split(',')) int.parse(n)],
      preferLowestSetting: ref.read(preferLowestFilamentProvider).valueOrNull,
    );
    final inventory = ref.watch(inventoryRepositoryProvider);
    final prices = <int, double>{};
    if (mapping != null &&
        await inventory.backend() == InventoryBackend.native) {
      for (final a in await inventory.fetchAssignments(
        printerId: key.printerId,
      )) {
        final price = a.spool?.costPerKg;
        if (price != null) {
          prices[globalTrayId(amsId: a.amsId, trayId: a.trayId)] = price;
        }
      }
    }
    return estimateJobCost(
      requirements: requirements,
      mapping: mapping,
      costPerKgByTray: prices,
      defaultCostPerKg: ref.watch(defaultFilamentCostProvider),
    );
  },
);
