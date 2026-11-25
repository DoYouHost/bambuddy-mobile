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
      expect(
        name(bare, s: spool, p: preset, subBrandFirst: true),
        'Generic PETG',
      );
      expect(name(bare, s: spool, subBrandFirst: true), 'eSun PETG');
      expect(name(bare, subBrandFirst: true), 'PETG');
      expect(
        name(bare, filamentName: 'Bambu PETG HF', subBrandFirst: true),
        'Bambu PETG HF',
      );
    });

    test('a blank server name counts as none', () {
      expect(name(tray, filamentName: ''), 'PETG HF');
      expect(name(bare, filamentName: '   '), 'PETG');
    });
  });
}
