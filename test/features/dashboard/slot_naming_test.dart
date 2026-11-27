import 'package:bambuddy_mobile/core/models/ams_filament_preset.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/ams/color_names.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/printer_card.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  const tray = AmsTray(
    trayType: 'PETG',
    traySubBrands: 'PETG HF',
    trayInfoIdx: 'GFG02',
    trayColor: '2F6FB3FF',
  );
  const bare = AmsTray(
    trayType: 'PETG',
    trayInfoIdx: 'GFG02',
    trayColor: '2F6FB3FF',
  );
  const spool = Spool(id: 1, material: 'PETG', brand: 'eSun');
  const preset = SlotPreset(
    amsId: 0,
    trayId: 0,
    presetId: 'P123',
    presetName: 'Generic PETG @BBL X1C',
  );

  String name(
    AmsTray t, {
    Spool? s,
    SlotPreset? p,
    String? filamentName,
    bool subBrandFirst = false,
  }) => slotNaming(
    pl,
    ColorCatalog.empty,
    t,
    s,
    p,
    filamentName: filamentName,
    subBrandFirst: subBrandFirst,
  ).name;

  group('slotNaming name chain', () {
    test('without a server name it is the sub-brand, then the type', () {
      expect(name(tray), 'PETG HF');
      expect(name(bare), 'PETG');
    });

    test('the server name goes before the sub-brand and the type', () {
      expect(name(tray, filamentName: 'Bambu PETG HF'), 'Bambu PETG HF');
      expect(name(bare, filamentName: 'Bambu PETG HF'), 'Bambu PETG HF');
    });

    test('a spool assigned to the slot goes before the server name', () {
      expect(name(bare, s: spool, filamentName: 'Bambu PETG HF'), 'eSun PETG');
    });

    test('a preset that describes the tray goes before both', () {
      expect(
        name(bare, s: spool, p: preset, filamentName: 'Bambu PETG HF'),
        'Generic PETG',
      );
    });

    test('the sub-brand goes before the preset and the spool when asked', () {
      expect(name(tray, s: spool, p: preset, subBrandFirst: true), 'PETG HF');
    });

    test('without a sub-brand the tile chain falls back like the row', () {
      // Each name has its own variant, so the order shows through the brand cut.
      const cf = SlotPreset(
        amsId: 0,
        trayId: 0,
        presetId: 'P123',
        presetName: 'Generic PETG CF @BBL X1C',
      );
      const hs = Spool(id: 2, material: 'PETG', subtype: 'HS', brand: 'eSun');
      expect(name(bare, s: hs, p: cf, subBrandFirst: true), 'PETG CF');
      expect(name(bare, s: hs, subBrandFirst: true), 'PETG HS');
      expect(name(bare, subBrandFirst: true), 'PETG');
      expect(
        name(bare, filamentName: 'Bambu PETG HF', subBrandFirst: true),
        'PETG HF',
      );
    });

    test('the tile chain reads from the material on, whatever the brand', () {
      AmsTray named(String type, String sub) =>
          AmsTray(trayType: type, traySubBrands: sub, trayInfoIdx: 'GFX');
      final cases = {
        ('PLA', 'Bambu PLA Matte'): 'PLA Matte',
        ('ABS', 'Bambu ABS'): 'ABS',
        ('PETG', 'Bambu PETG HF'): 'PETG HF',
        ('PETG', 'Professional Lab PETG'): 'PETG',
        ('PLA', 'eSun PLA+'): 'PLA+',
        ('PLA', 'PLA Basic'): 'PLA Basic',
      };
      for (final MapEntry(key: (type, sub), value: shown) in cases.entries) {
        expect(name(named(type, sub), subBrandFirst: true), shown, reason: sub);
        expect(name(named(type, sub)), sub, reason: 'the row keeps the brand');
      }
    });

    test('fromMaterial reads whole words only and keeps a support name', () {
      // A brand that merely starts with the type's letters is not the type.
      expect(fromMaterial('Plastspaw PLA Matte', 'PLA'), 'PLA Matte');
      expect(fromMaterial('3D Plastics PLA Matte', 'PLA'), 'PLA Matte');
      expect(fromMaterial('Formfutura Platinum PLA', 'PLA'), 'PLA');
      expect(fromMaterial('Panchroma PA6-CF', 'PA'), 'PA6-CF');
      // "Support for PLA" is not PLA.
      expect(
        fromMaterial('Bambu Support for PLA', 'PLA'),
        'Bambu Support for PLA',
      );
      expect(fromMaterial('Support for ABS', 'ABS'), 'Support for ABS');
      expect(fromMaterial('Bambu Forza PLA', 'PLA'), 'PLA');
    });

    test(
      'fromMaterial matches a hyphen in the type to a space or a hyphen',
      () {
        expect(fromMaterial('eSun PETG CF', 'PETG-CF'), 'PETG CF');
        expect(fromMaterial('Bambu PLA-CF', 'PLA-CF'), 'PLA-CF');
        expect(fromMaterial('Bambu PLA CF', 'PLA-CF'), 'PLA CF');
      },
    );

    test('a spool named by its own material is not a displaced spool', () {
      const hs = Spool(id: 2, material: 'PETG', subtype: 'HS', brand: 'eSun');
      final naming = slotNaming(
        pl,
        ColorCatalog.empty,
        bare,
        hs,
        null,
        subBrandFirst: true,
      );
      expect(naming.name, 'PETG HS');
      expect(naming.spool, isNull);
    });

    test('a spool that reads like the cut name is not said twice', () {
      const matte = AmsTray(
        trayType: 'PLA',
        traySubBrands: 'Bambu PLA Matte',
        trayInfoIdx: 'GFA01',
      );
      const plain = Spool(id: 1, material: 'PLA', subtype: 'Matte');
      final naming = slotNaming(
        pl,
        ColorCatalog.empty,
        matte,
        plain,
        null,
        subBrandFirst: true,
      );
      expect(naming.name, 'PLA Matte');
      expect(naming.spool, isNull);
    });

    test('fromMaterial keeps a name it cannot read the material from', () {
      expect(fromMaterial('Bambu PLA Matte', ''), 'Bambu PLA Matte');
      expect(fromMaterial('Bambu PLA Matte', null), 'Bambu PLA Matte');
      expect(fromMaterial('Generic filament', 'PETG'), 'Generic filament');
      expect(
        fromMaterial('Bambu Support for PLA', 'PLA-S'),
        'Bambu Support for PLA',
      );
      // The type only counts at the start of a word.
      expect(fromMaterial('Bambu SUPLA Matte', 'PLA'), 'Bambu SUPLA Matte');
      expect(fromMaterial('PLA', 'PLA'), 'PLA');
      expect(fromMaterial('', 'PLA'), '');
    });

    test('a blank server name counts as none', () {
      expect(name(tray, filamentName: ''), 'PETG HF');
      expect(name(bare, filamentName: '   '), 'PETG');
    });
  });
}
