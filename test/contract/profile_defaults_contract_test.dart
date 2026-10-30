import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/api/server_version_service.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/profile_default.dart';
import 'package:bambuddy_mobile/core/models/spool_preset_override.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/data/profile_defaults_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// Profile defaults (server #1326): saved per product, laid over every spool the
/// server creates, listed, applied to the stock and deleted — and, on a server
/// without them, the app learns so from the 404 rather than from a version.
void main() {
  group('profile defaults contract', skip: contractSkipReason, () {
    late Dio dio;
    late ProfileDefaultsRepository defaults;
    late NativeInventorySource source;
    late bool hasRoutes;
    late int printerId;
    final defaultIds = <int>[];
    final spoolIds = <int>[];
    final stamp = DateTime.now().millisecondsSinceEpoch;

    ProfileProduct product(String tag, {String colour = ''}) => ProfileProduct(
      brand: 'Contract',
      material: 'PD-$tag-$stamp',
      colorName: colour,
    );

    Future<ProfileDefault> save(ProfileDefaultDraft draft) async {
      final saved = await defaults.save(draft);
      defaultIds.add(saved.id);
      return saved;
    }

    Future<Spool> createSpool(ProfileProduct p) async {
      final spool = await source.createSpool(
        SpoolDraft(
          material: p.material,
          brand: p.brand,
          colorName: p.colorName.isEmpty ? null : p.colorName,
          labelWeight: 1000,
        ),
      );
      spoolIds.add(spool.id);
      return spool;
    }

    setUpAll(() async {
      dio = await authenticatedDio();
      source = NativeInventorySource(dio);
      defaults = ProfileDefaultsRepository(
        dio,
        () async => InventoryBackend.native,
        ServerVersionService(dio),
      );
      final probe = await dio.get<dynamic>(
        Endpoints.inventoryProfileDefaults,
        options: Options(validateStatus: (_) => true),
      );
      hasRoutes = probe.statusCode == 200;
      final printers = (await dio.get<List<dynamic>>(Endpoints.printers)).data!;
      printerId = (printers.first as Map<String, dynamic>)['id'] as int;
    });

    tearDownAll(() async {
      final quiet = Options(validateStatus: (_) => true);
      for (final id in spoolIds) {
        await dio.delete<dynamic>(Endpoints.inventorySpool(id), options: quiet);
      }
      for (final id in defaultIds) {
        await dio.delete<dynamic>(
          Endpoints.inventoryProfileDefault(id),
          options: quiet,
        );
      }
    });

    test('a server without the routes hides the feature on its 404', () async {
      if (hasRoutes) {
        markTestSkipped('server has profile defaults');
        return;
      }
      expect(await defaults.list(), isEmpty);
      expect(defaults.capability.observedAnswer, isFalse);
      expect(
        await defaults.resolve(const ProfileProduct(material: 'PLA')),
        isNull,
      );
    });

    test(
      'a product with no default resolves to null, a list is a list',
      () async {
        if (!hasRoutes) {
          markTestSkipped('server has no profile defaults');
          return;
        }
        expect(await defaults.resolve(product('none')), isNull);
        expect(await defaults.list(), isA<List<ProfileDefault>>());
        expect(defaults.capability.observedAnswer, isTrue);
      },
    );

    test('a saved default is listed, resolved and replaced as a whole, '
        'K profiles resent untouched', () async {
      if (!hasRoutes) {
        markTestSkipped('server has no profile defaults');
        return;
      }
      final p = product('save');
      final first = await save(
        ProfileDefaultDraft(
          product: p,
          slicerFilament: 'GFA00',
          slicerFilamentName: 'Bambu PLA Basic',
          presets: const [
            SpoolPresetOverride(
              printerModel: 'X1C',
              slicerFilament: 'GFA00_X1C',
              slicerFilamentName: 'Bambu PLA Basic @BBL X1C',
            ),
          ],
          kProfiles: [
            {
              'printer_id': printerId,
              'extruder': 0,
              'nozzle_diameter': '0.4',
              'k_value': 0.025,
              'name': 'Contract K',
            },
          ],
        ),
      );
      expect(first.product.matchKey, p.matchKey);
      expect(first.slicerFilament, 'GFA00');
      expect(first.presets.single.printerModel, 'X1C');
      expect(first.kProfiles.single['k_value'], 0.025);

      final resolved = await defaults.resolve(p);
      expect(resolved!.slicerFilament, 'GFA00');
      expect(resolved.presets.single.slicerFilament, 'GFA00_X1C');

      // What the form does: edit the presets, send back the K profiles it read.
      final again = await defaults.save(
        ProfileDefaultDraft(
          product: ProfileProduct(
            brand: ' contract ',
            material: p.material.toLowerCase(),
          ),
          slicerFilament: 'GFA05',
          slicerFilamentName: 'Bambu PLA Silk',
          kProfiles: first.kProfiles,
        ),
      );
      expect(again.id, first.id);
      expect(again.slicerFilament, 'GFA05');
      expect(again.presets, isEmpty, reason: 'the body replaces the presets');
      expect(again.kProfiles.single['k_value'], 0.025);
      expect(
        (await defaults.list()).where((d) => d.id == first.id),
        hasLength(1),
      );
    });

    test('a K profile left out of the body is deleted — the reason the app '
        'sends them back', () async {
      if (!hasRoutes) {
        markTestSkipped('server has no profile defaults');
        return;
      }
      final p = product('drop');
      await save(
        ProfileDefaultDraft(
          product: p,
          slicerFilament: 'GFA00',
          kProfiles: [
            {'printer_id': printerId, 'k_value': 0.03},
          ],
        ),
      );

      final wiped = await defaults.save(
        ProfileDefaultDraft(product: p, slicerFilament: 'GFA00'),
      );

      expect(wiped.kProfiles, isEmpty);
    });

    test('the colour row is laid over the all-colours one', () async {
      if (!hasRoutes) {
        markTestSkipped('server has no profile defaults');
        return;
      }
      final all = product('layer');
      final red = product('layer', colour: 'Red');
      await save(
        ProfileDefaultDraft(
          product: all,
          slicerFilament: 'ALL',
          presets: const [
            SpoolPresetOverride(printerModel: 'X1C', slicerFilament: 'ALL_X1C'),
            SpoolPresetOverride(printerModel: 'P1S', slicerFilament: 'ALL_P1S'),
          ],
        ),
      );
      await save(
        ProfileDefaultDraft(
          product: red,
          slicerFilament: 'RED',
          presets: const [
            SpoolPresetOverride(printerModel: 'X1C', slicerFilament: 'RED_X1C'),
          ],
        ),
      );

      final forRed = await defaults.resolve(red);
      final forBlue = await defaults.resolve(
        ProfileProduct(
          brand: all.brand,
          material: all.material,
          colorName: 'Blue',
        ),
      );

      expect(forRed!.slicerFilament, 'RED');
      expect(
        {for (final p in forRed.presets) p.printerModel: p.slicerFilament},
        {'X1C': 'RED_X1C', 'P1S': 'ALL_P1S'},
      );
      expect(forBlue!.slicerFilament, 'ALL');
      expect(forBlue.presets.map((p) => p.slicerFilament), contains('ALL_X1C'));
    });

    test('the server lays a default on a spool it creates, and keeps the '
        'preset of one that names its own', () async {
      if (!hasRoutes) {
        markTestSkipped('server has no profile defaults');
        return;
      }
      final p = product('create');
      await save(
        ProfileDefaultDraft(
          product: p,
          slicerFilament: 'GFA00',
          slicerFilamentName: 'Bambu PLA Basic',
          presets: const [
            SpoolPresetOverride(
              printerModel: 'H2D',
              slicerFilament: 'GFA00_H2D',
            ),
          ],
        ),
      );

      final started = await createSpool(p);
      final own = await source.createSpool(
        SpoolDraft(
          material: p.material,
          brand: p.brand,
          slicerFilament: 'GFA05',
          labelWeight: 1000,
        ),
      );
      spoolIds.add(own.id);

      final rows = {for (final s in await source.fetchSpools()) s.id: s};
      expect(rows[started.id]!.slicerFilament, 'GFA00');
      expect(
        (await source.fetchPresetOverrides(started.id)).single.printerModel,
        'H2D',
      );
      expect(rows[own.id]!.slicerFilament, 'GFA05');
    });

    test('apply fills what stock lacks once, and a second apply changes '
        'nothing', () async {
      if (!hasRoutes) {
        markTestSkipped('server has no profile defaults');
        return;
      }
      final p = product('apply');
      final stock = await createSpool(p);
      final saved = await save(
        ProfileDefaultDraft(
          product: p,
          slicerFilament: 'GFA00',
          presets: const [
            SpoolPresetOverride(
              printerModel: 'X1C',
              slicerFilament: 'GFA00_X1C',
            ),
          ],
        ),
      );

      expect(await defaults.apply(saved.id), 1);
      expect(await defaults.apply(saved.id), 0);

      expect(
        (await source.fetchPresetOverrides(stock.id)).single.printerModel,
        'X1C',
      );
    });

    test('a save without a material is refused, a delete is a 404 the '
        'second time', () async {
      if (!hasRoutes) {
        markTestSkipped('server has no profile defaults');
        return;
      }
      await expectLater(
        defaults.save(
          const ProfileDefaultDraft(product: ProfileProduct(material: '')),
        ),
        throwsA(
          isA<AppApiException>().having((e) => e.statusCode, 'status', 422),
        ),
      );

      final saved = await defaults.save(
        ProfileDefaultDraft(product: product('delete')),
      );
      await defaults.delete(saved.id);
      expect((await defaults.list()).where((d) => d.id == saved.id), isEmpty);
      await expectLater(
        defaults.delete(saved.id),
        throwsA(
          isA<AppApiException>().having((e) => e.statusCode, 'status', 404),
        ),
      );
      // A deleted row's 404 says nothing about the route family.
      expect(defaults.capability.observedAnswer, isNot(isFalse));
    });
  });
}
