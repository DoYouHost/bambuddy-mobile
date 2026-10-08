import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// Emptying a field in the spool form has to remove it on the server. A null in
/// [SpoolDraft] means "leave it", so the form names what it emptied in
/// `clears`, and each backend has its own dialect for it: the built-in route
/// stores an explicit null, Spoolman clears `subtype` and `note` on an empty
/// string and `storage_location` on null, and cannot clear the rest at all.
void main() {
  final stamp = DateTime.now().millisecondsSinceEpoch;

  group('clearing a field, built-in inventory', skip: contractSkipReason, () {
    late Dio dio;
    late NativeInventorySource source;
    final spoolIds = <int>[];

    setUpAll(() async {
      dio = await authenticatedDio();
      source = NativeInventorySource(dio);
    });

    tearDownAll(() async {
      final quiet = Options(validateStatus: (_) => true);
      for (final id in spoolIds) {
        await dio.delete<dynamic>(Endpoints.inventorySpool(id), options: quiet);
      }
    });

    Future<Spool> reread(int id) async => (await source.fetchSpools(
      includeArchived: true,
    )).firstWhere((s) => s.id == id);

    test('every field the form can blank is removed', () async {
      final created = await source.createSpool(
        SpoolDraft(
          material: 'PLA-Clear-$stamp',
          subtype: 'HF',
          brand: 'Clear',
          colorName: 'Teal',
          extraColors: 'FF0000,00FF00',
          note: 'dry box',
          category: 'cat',
          storageLocation: 'ClearShelf$stamp',
          costPerKg: 20.5,
          lowStockThresholdPct: 15,
          slicerFilament: 'GFA00',
          slicerFilamentName: 'Bambu PLA',
          labelWeight: 1000,
        ),
      );
      spoolIds.add(created.id);
      final stored = await reread(created.id);
      expect(stored.subtype, 'HF');
      expect(stored.note, 'dry box');
      expect(stored.costPerKg, 20.5);

      final draft = SpoolDraft(
        material: stored.material,
        labelWeight: 1000,
      ).clearing(stored);
      expect(
        draft.clears,
        containsAll(['subtype', 'brand', 'note', 'category']),
      );
      await source.updateSpool(created.id, draft);

      final after = await reread(created.id);
      expect(after.subtype, isNull);
      expect(after.brand, isNull);
      expect(after.colorName, isNull);
      expect(after.extraColors, isNull);
      expect(after.note, isNull);
      expect(after.category, isNull);
      expect(after.storageLocation, isNull);
      expect(after.costPerKg, isNull);
      expect(after.lowStockThresholdPct, isNull);
      expect(after.slicerFilament, isNull);
      expect(after.slicerFilamentName, isNull);
      expect(after.material, stored.material, reason: 'the rest is untouched');
      expect(after.labelWeight, 1000);
    });

    test('the material number clears too, where the server has one', () async {
      final created = await source.createSpool(
        SpoolDraft(
          material: 'PLA-ClearNo-$stamp',
          materialNumber: 'CLR-$stamp',
        ),
      );
      spoolIds.add(created.id);
      if (!created.materialNumberReported) {
        markTestSkipped('server predates the material number');
        return;
      }
      final stored = await reread(created.id);
      expect(stored.materialNumber, 'CLR-$stamp');

      await source.updateSpool(
        created.id,
        SpoolDraft(material: stored.material).clearing(stored),
      );
      expect((await reread(created.id)).materialNumber, isNull);
    });

    test('a draft that clears nothing changes nothing', () async {
      final created = await source.createSpool(
        SpoolDraft(
          material: 'PLA-Keep-$stamp',
          note: 'keep me',
          storageLocation: 'KeepShelf$stamp',
        ),
      );
      spoolIds.add(created.id);
      final stored = await reread(created.id);

      await source.updateSpool(
        created.id,
        SpoolDraft.fromSpool(stored).clearing(stored),
      );
      final after = await reread(created.id);
      expect(after.note, 'keep me');
      expect(after.storageLocation, 'KeepShelf$stamp');
    });
  });

  group('clearing a field, Spoolman', skip: spoolmanSkipReason, () {
    late Dio dio;
    late SpoolmanInventorySource source;
    Map<String, dynamic>? settingsBefore;

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
    });

    tearDownAll(() async {
      if (settingsBefore case final before?) {
        await putSpoolman({
          'spoolman_enabled': before['spoolman_enabled'] ?? 'false',
          'spoolman_url': before['spoolman_url'] ?? '',
        });
      }
    });

    test('subtype, note and location are removed', () async {
      final created = await source.createSpool(
        SpoolDraft(
          material: 'PLA',
          brand: 'Clear $stamp',
          subtype: 'HF',
          note: 'dry box',
          storageLocation: 'ClearShelf$stamp',
          labelWeight: 1000,
        ),
      );
      addTearDown(() => source.deleteSpool(created.id));
      Future<Spool> reread() async =>
          (await source.fetchSpools()).firstWhere((s) => s.id == created.id);
      final stored = await reread();
      expect(stored.subtype, 'HF');
      expect(stored.note, 'dry box');
      expect(stored.storageLocation, 'ClearShelf$stamp');

      await source.updateSpool(
        created.id,
        SpoolDraft(
          material: stored.material,
          brand: stored.brand,
          labelWeight: 1000,
        ).clearing(stored),
      );

      final after = await reread();
      expect(after.subtype, isNull);
      expect(after.note, isNull);
      expect(after.storageLocation, isNull);
      expect(after.brand, stored.brand, reason: 'brand was kept in the draft');
    });

    test('the slicer preset is removed with an empty string', () async {
      final created = await source.createSpool(
        SpoolDraft(material: 'PLA', brand: 'Preset $stamp', labelWeight: 1000),
      );
      addTearDown(() => source.deleteSpool(created.id));
      Future<Map<String, dynamic>> raw() async =>
          ((await dio.get<List<dynamic>>(Endpoints.spoolmanSpools)).data!)
              .cast<Map<String, dynamic>>()
              .firstWhere((x) => x['id'] == created.id);
      // The draft cannot set a preset on Spoolman, only the web client can;
      // write it the way that does.
      await dio.patch<dynamic>(
        Endpoints.spoolmanSpool(created.id),
        data: {'slicer_filament': 'GFA00', 'slicer_filament_name': 'Bambu PLA'},
      );
      expect((await raw())['slicer_filament'], 'GFA00');

      // Spool.fromSpoolman does not read the preset, so a stored spool that
      // holds one is built by hand: the point is what the draft puts on the
      // wire.
      const held = Spool(
        id: 0,
        material: 'PLA',
        slicerFilament: 'GFA00',
        slicerFilamentName: 'Bambu PLA',
      );
      await source.updateSpool(
        created.id,
        SpoolDraft(
          material: 'PLA',
          brand: 'Preset $stamp',
          labelWeight: 1000,
        ).clearing(held),
      );

      final after = await raw();
      expect(after['slicer_filament'], isNull);
      expect(after['slicer_filament_name'], isNot('Bambu PLA'));
    });

    test(
      'a clear Spoolman cannot do is not sent, and breaks nothing',
      () async {
        final created = await source.createSpool(
          SpoolDraft(
            material: 'PLA',
            brand: 'Keep $stamp',
            costPerKg: 20.5,
            labelWeight: 1000,
          ),
        );
        addTearDown(() => source.deleteSpool(created.id));
        final stored = (await source.fetchSpools()).firstWhere(
          (s) => s.id == created.id,
        );

        final draft = SpoolDraft(
          material: stored.material,
          labelWeight: 1000,
        ).clearing(stored);
        expect(draft.clears, containsAll(['brand', 'cost_per_kg']));
        expect(draft.toSpoolmanJson().containsKey('brand'), isFalse);
        expect(draft.toSpoolmanJson().containsKey('cost_per_kg'), isFalse);
        await source.updateSpool(created.id, draft);

        final after = (await source.fetchSpools()).firstWhere(
          (s) => s.id == created.id,
        );
        expect(after.brand, stored.brand);
        expect(after.costPerKg, 20.5);
      },
    );
  });
}
