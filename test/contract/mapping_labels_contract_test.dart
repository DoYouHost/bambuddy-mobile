import 'package:bambuddy_mobile/core/ams/color_names.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/data/ams_slot_config_repository.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/data/printer_commands_repository.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// The names the filament mapping writes next to every slot and filament, read
/// where the web reads them: the colour catalogue, its by-material lookup, the
/// user's cloud preset names and the spools bound to each slot.
void main() {
  group('mapping labels contract', skip: contractSkipReason, () {
    late Dio dio;
    late AmsSlotConfigRepository slots;
    late PrintersRepository printers;

    setUpAll(() async {
      dio = await authenticatedDio();
      slots = AmsSlotConfigRepository(dio);
      printers = PrintersRepository(dio);
    });

    test('the colour catalogue names a hex', () async {
      final catalog = await slots.colorCatalog();
      expect(
        catalog.byHex,
        isNotEmpty,
        reason: 'the server seeds Bambu colours',
      );
      final (hex, name) = catalog.byHex.entries
          .map((e) => (e.key, e.value))
          .first;
      expect(catalog.nameOf(hex), name);
      expect(colorFamily(hex), isNotNull);
    });

    test('a hex the catalogue knows is named within a material', () async {
      final catalog = await slots.colorCatalog();
      final hex = catalog.byHex.keys.first;
      expect(await slots.colorByMaterial('#$hex', 'PLA Basic'), isNotNull);
      expect(await slots.colorByMaterial('#123457', null), isNull);
    });

    test('cloud preset names are empty without a cloud login', () async {
      expect(await slots.cloudFilamentNames(), isEmpty);
    });

    test('a bound spool gives its slot a name and grams', () async {
      // The seed loads PLA in AMS 0 slot 1 (global 0).
      final printerId =
          ((await dio.get<List<dynamic>>('/api/v1/printers/')).data!.first
                  as Map<String, dynamic>)['id']
              as int;
      final shelf = NativeInventorySource(dio);
      final spool = await shelf.createSpool(
        SpoolDraft(
          material: 'PLA',
          subtype: 'Basic',
          brand: 'Contract',
          labelWeight: 1000,
          weightUsed: 250,
        ),
      );
      addTearDown(() => shelf.deleteSpool(spool.id));
      await shelf.assignSpool(
        SpoolAssignmentDraft(
          spoolId: spool.id,
          printerId: printerId,
          amsId: 0,
          trayId: 0,
        ),
      );
      addTearDown(() => shelf.unassignSpool(printerId, 0, 0));

      final inventory = await printers.fetchInventoryRemain(printerId);
      expect(inventory.spools[0]?.name, 'Contract PLA Basic');
      expect(inventory.grams[0], 750);
    });

    test('a re-read is accepted for the seeded printer', () async {
      final printerId =
          ((await dio.get<List<dynamic>>('/api/v1/printers/')).data!.first
                  as Map<String, dynamic>)['id']
              as int;
      await expectLater(
        PrinterCommandsRepository(dio).refreshStatus(printerId),
        completes,
      );
    });
  });
}
