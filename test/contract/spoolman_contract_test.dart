import 'package:bambuddy_mobile/core/models/api_key.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/data/api_keys_repository.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
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
      try {
        for (final id in keyIds) {
          await dio
              .delete<dynamic>(
                '/api/v1/api-keys/$id',
                options: Options(validateStatus: (_) => true),
              )
              .catchError(
                (Object _) =>
                    Response<dynamic>(requestOptions: RequestOptions()),
              );
        }
      } finally {
        // Every other contract test reads the built-in inventory. Unread, the
        // setting was never changed either.
        if (settingsBefore case final before?) {
          await putSpoolman({
            'spoolman_enabled': before['spoolman_enabled'] ?? 'false',
            'spoolman_url': before['spoolman_url'] ?? '',
          });
        }
      }
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
      // Removed by the test that made it, while Spoolman is still on: the
      // Spoolman routes refuse once the last test switches it off.
      addTearDown(() => source.deleteSpool(spool.id));
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
      addTearDown(() => source.unassignSpool(printerId, 0, 3));
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
      addTearDown(() => source.unassignSpool(printerId, 0, 2));
      expect((await slotsOf(spool.id)).map((a) => (a.amsId, a.trayId)), [
        (0, 2),
      ]);
    });

    test(
      'a tray reading a tag gets a spool the shelf finds by that tag',
      skip: brokerSkipReason,
      () async {
        // What the printer card leans on: the server links a tagged spool on
        // its own at the AMS sync (`spoolman.py::sync_ams_tray`), and the shelf
        // the app reads carries the tag back out of Spoolman's `extra.tag`.
        final printer =
            ((await dio.get<List<dynamic>>('/api/v1/printers/')).data!.first
                as Map<String, dynamic>);
        final serial = printer['serial_number'] as String;
        final uuid = 'C0FFEE${stamp.toRadixString(16).padLeft(26, '0')}'
            .substring(0, 32)
            .toUpperCase();
        Map<String, Object?> amsWith(List<Map<String, Object?>> extra) => {
          'ams': {
            'ams': [
              {
                'id': 0,
                'tray': [
                  {
                    'id': 0,
                    'tray_type': 'PLA',
                    'tray_color': 'FF0000FF',
                    'tray_info_idx': 'GFL99',
                    'tray_sub_brands': 'PLA Basic',
                  },
                  {
                    'id': 1,
                    'tray_type': 'PLA',
                    'tray_color': '00FF00FF',
                    'tray_info_idx': 'GFL99',
                    'tray_sub_brands': 'PLA Basic',
                  },
                  ...extra,
                ],
              },
            ],
            'ams_exist_bits': '1',
          },
        };
        await publishReport(
          serial,
          amsWith([
            {
              'id': 3,
              'tray_type': 'PETG',
              'tray_color': '0000FFFF',
              'tray_info_idx': 'GFG00',
              'tray_sub_brands': 'PETG Basic',
              'tray_weight': '1000',
              'remain': 80,
              'tray_uuid': uuid,
              'tag_uid': '0102030405060708',
            },
          ]),
        );

        // The server makes the spool, so it is found by its tag to be removed —
        // also when the wait below gives up after the server made it anyway.
        // Read raw, so the cleanup does not lean on the parser under test.
        // Teardowns run last-first: the tray goes back to the seeded ones
        // before the spool is removed, so no sync can make it again.
        addTearDown(() async {
          final rows = (await dio.get<List<dynamic>>(
            '/api/v1/spoolman/inventory/spools',
            queryParameters: {'include_archived': true},
          )).data!.cast<Map<String, dynamic>>();
          for (final row in rows) {
            if ('${row['tray_uuid']}'.toUpperCase() == uuid) {
              final id = row['id'] as int;
              await dio.delete<dynamic>(
                '/api/v1/spoolman/inventory/slot-assignments/$id',
                options: Options(validateStatus: (_) => true),
              );
              await source.deleteSpool(id);
            }
          }
        });
        addTearDown(() => publishReport(serial, amsWith(const [])));
        final spool = await pollUntil(
          'a Spoolman spool carrying tray $uuid',
          () async => InventoryState(
            spools: await source.fetchSpools(),
          ).spoolForTag(trayUuid: uuid),
          within: const Duration(seconds: 30),
        );

        expect(spool.material, 'PETG');
        // The sync also pins it to the slot — the card shows a tagged slot
        // from that row, as the web does (#1457).
        expect((await slotsOf(spool.id)).map((a) => (a.amsId, a.trayId)), [
          (0, 3),
        ]);
      },
    );

    test('switched off, the server is the built-in inventory again', () async {
      // Last on purpose: nothing after it needs Spoolman, and tearDownAll puts
      // back whatever the server had.
      await putSpoolman({'spoolman_enabled': 'false'});

      expect(await detectInventoryBackend(dio), InventoryBackend.native);
    });
  });
}
