import 'package:bambuddy_mobile/core/models/api_key.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/data/api_keys_repository.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// The inventory on a server switched to Spoolman (issue #5): the app has to
/// notice the switch from the server's own answer, and then read, assign and
/// clear spools through the Spoolman routes — on slots without RFID too, which
/// is what the reporter has.
void main() {
  group('spoolman contract', skip: spoolmanSkipReason, () {
    late Dio dio;
    late SpoolmanInventorySource source;
    late int printerId;
    Map<String, dynamic>? settingsBefore;
    final spoolIds = <int>[];
    final keyIds = <int>[];
    final stamp = DateTime.now().millisecondsSinceEpoch;

    Future<void> putSpoolman(Map<String, dynamic> settings) =>
        dio.put<dynamic>('/api/v1/settings/spoolman', data: settings);

    setUpAll(() async {
      dio = await authenticatedDio();
      settingsBefore = (await dio.get<Map<String, dynamic>>(
        '/api/v1/settings/spoolman',
      )).data;
      await putSpoolman({
        'spoolman_enabled': 'true',
        'spoolman_url': contractSpoolmanUrl,
      });
      source = SpoolmanInventorySource(dio);
      final printers = (await dio.get<List<dynamic>>(
        '/api/v1/printers/',
      )).data!;
      printerId = (printers.first as Map<String, dynamic>)['id'] as int;
    });

    tearDownAll(() async {
      final quiet = Options(validateStatus: (_) => true);
      for (final id in spoolIds) {
        await dio.delete<dynamic>(
          '/api/v1/spoolman/inventory/slot-assignments/$id',
          options: quiet,
        );
        await dio.delete<dynamic>(
          '/api/v1/spoolman/inventory/spools/$id',
          options: quiet,
        );
      }
      for (final id in keyIds) {
        await dio.delete<dynamic>('/api/v1/api-keys/$id', options: quiet);
      }
      // Every other contract test reads the built-in inventory.
      await putSpoolman({
        'spoolman_enabled': settingsBefore?['spoolman_enabled'] ?? 'false',
        'spoolman_url': settingsBefore?['spoolman_url'] ?? '',
      });
    });

    Future<Spool> newSpool() async {
      final spool = await source.createSpool(
        SpoolDraft(
          material: 'PLA',
          brand: 'Contract $stamp',
          labelWeight: 1000,
          weightUsed: 300,
        ),
      );
      spoolIds.add(spool.id);
      return spool;
    }

    Future<List<SpoolAssignment>> slotsOf(int spoolId) async =>
        (await source.fetchAssignments(
          printerId: printerId,
        )).where((a) => a.spoolId == spoolId).toList();

    test('the server is recognised as running Spoolman', () async {
      expect(await detectInventoryBackend(dio), InventoryBackend.spoolman);
    });

    test(
      'a spool created through the app reads back with its weight',
      () async {
        final spool = await newSpool();

        final listed = (await source.fetchSpools()).singleWhere(
          (s) => s.id == spool.id,
        );
        expect(listed.material, 'PLA');
        expect(listed.labelWeight, 1000);
        expect(listed.remainingWeight, 700);
      },
    );

    test('a slot without RFID takes a spool and gives it back', () async {
      // The seeded printer reports no tag on any tray — the reporter's case.
      final spool = await newSpool();
      final draft = SpoolAssignmentDraft(
        spoolId: spool.id,
        printerId: printerId,
        amsId: 0,
        trayId: 3,
      );

      await source.assignSpool(draft);
      expect((await slotsOf(spool.id)).map((a) => (a.amsId, a.trayId)), [
        (0, 3),
      ]);

      await source.unassignSpool(printerId, 0, 3);
      expect(await slotsOf(spool.id), isEmpty);
    });

    test('an API key with manage-inventory can assign by slot', () async {
      final keys = ApiKeysRepository(dio);
      final created = await keys.create(
        const ApiKeyCreateInput(
          name: 'contract: spoolman',
          scopes: {ApiKeyScope.readStatus, ApiKeyScope.manageInventory},
        ),
      );
      keyIds.add(created.apiKey.id);
      await pollUntil(
        'key ${created.apiKey.id} to be committed',
        () async => (await keys.list()).any((k) => k.id == created.apiKey.id)
            ? true
            : null,
        within: const Duration(seconds: 10),
        every: const Duration(milliseconds: 100),
      );
      final keyed = Dio(BaseOptions(baseUrl: contractBaseUrl))
        ..options.headers['X-API-Key'] = created.key;
      final spool = await newSpool();

      expect(await detectInventoryBackend(keyed), InventoryBackend.spoolman);
      await SpoolmanInventorySource(keyed).assignSpool(
        SpoolAssignmentDraft(
          spoolId: spool.id,
          printerId: printerId,
          amsId: 0,
          trayId: 2,
        ),
      );
      expect((await slotsOf(spool.id)).map((a) => (a.amsId, a.trayId)), [
        (0, 2),
      ]);
      await source.unassignSpool(printerId, 0, 2);
    });

    test('switched off, the server is the built-in inventory again', () async {
      await putSpoolman({'spoolman_enabled': 'false'});
      addTearDown(
        () => putSpoolman({
          'spoolman_enabled': 'true',
          'spoolman_url': contractSpoolmanUrl,
        }),
      );

      expect(await detectInventoryBackend(dio), InventoryBackend.native);
    });
  });
}
