import 'package:bambuddy_mobile/core/models/loaded_spools.dart';
import 'package:bambuddy_mobile/core/models/slicer_preset.dart';
import 'package:bambuddy_mobile/core/slicer/loaded_spool_match.dart';
import 'package:bambuddy_mobile/core/slicer/preset_compatibility.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ported case for case from the web's `sliceLoadedSpools.test.ts` (#3172),
/// so both clients map a loaded spool to the same profile.
void main() {
  const models = {
    'Bambu Lab X1 Carbon': 'X1C',
    'Bambu Lab H2D': 'H2D',
    'Bambu Lab A1 Mini': 'A1 Mini',
    'Bambu Lab A1 mini': 'A1 Mini',
  };
  const h2d = 'Bambu Lab H2D 0.4 nozzle';

  SlicerPreset std(String name, String type) => SlicerPreset(
    source: 'standard',
    id: name,
    name: name,
    filamentType: type,
  );

  final standardFilaments = [
    std('Bambu PLA Basic @BBL X1C', 'PLA'),
    std('Bambu PLA Basic @BBL H2D', 'PLA'),
    std('Generic PETG @BBL H2D', 'PETG'),
    std('Generic PLA @BBL H2D', 'PLA'),
  ];

  LoadedSpoolTray tray({
    int amsId = 0,
    int trayId = 0,
    String? trayType = 'PLA',
    String? subBrands,
    String? trayInfoIdx,
    LoadedSpoolPreset? saved,
  }) => LoadedSpoolTray(
    amsId: amsId,
    trayId: trayId,
    trayType: trayType,
    traySubBrands: subBrands,
    trayColor: 'FF0000FF',
    trayInfoIdx: trayInfoIdx,
    exists: true,
    savedPreset: saved,
  );

  String? match(
    LoadedSpoolTray t,
    List<SlicerPreset> filaments, [
    String? printer = h2d,
  ]) {
    final hit = matchSlotPreset(
      t,
      filaments: filaments,
      index: buildFilamentNameIndex(filaments),
      selectedPrinterName: printer,
      registry: models,
    );
    return hit == null ? null : presetKey(hit);
  }

  group('printerPresetModel', () {
    test('reads the model from a Bambu printer profile', () {
      expect(
        printerPresetModel('Bambu Lab X1 Carbon 0.4 nozzle', models),
        'X1C',
      );
      expect(printerPresetModel('# Bambu Lab H2D 0.6 nozzle', models), 'H2D');
      expect(
        printerPresetModel('Bambu Lab A1 mini 0.2 nozzle', models),
        'A1 Mini',
      );
    });

    test('keeps an unknown Bambu model as written and gives up on others', () {
      expect(printerPresetModel('Bambu Lab Q9 0.4 nozzle', models), 'Q9');
      expect(printerPresetModel('My farm printer', models), isNull);
      expect(printerPresetModel(null, models), isNull);
    });
  });

  group('isConnectedModelPreset', () {
    SlicerPreset printer(String name) =>
        SlicerPreset(source: 'standard', id: name, name: name);

    test('keeps online models at every nozzle size and drops the rest', () {
      const online = ['H2D'];
      expect(
        isConnectedModelPreset(
          printer('Bambu Lab H2D 0.4 nozzle'),
          online,
          models,
        ),
        isTrue,
      );
      expect(
        isConnectedModelPreset(
          printer('Bambu Lab H2D 0.8 nozzle'),
          online,
          models,
        ),
        isTrue,
      );
      expect(
        isConnectedModelPreset(
          printer('Bambu Lab X1 Carbon 0.4 nozzle'),
          online,
          models,
        ),
        isFalse,
      );
    });

    test('never hides a profile whose model it cannot read', () {
      expect(
        isConnectedModelPreset(printer('My farm printer'), const [
          'H2D',
        ], models),
        isTrue,
      );
    });

    test('understands the short A1 Mini code', () {
      expect(
        isConnectedModelPreset(printer('Bambu Lab A1 mini 0.4 nozzle'), const [
          'A1M',
        ], models),
        isTrue,
      );
    });

    test('the auto-pick prefers the 0.4 nozzle of an online model', () {
      final picked = pickConnectedPrinterPreset(
        [
          printer('Bambu Lab X1 Carbon 0.4 nozzle'),
          printer('Bambu Lab H2D 0.6 nozzle'),
          printer('Bambu Lab H2D 0.4 nozzle'),
        ],
        const ['H2D'],
        models,
      );
      expect(picked?.name, 'Bambu Lab H2D 0.4 nozzle');
    });
  });

  test('presetBaseName drops the clone prefix and the printer suffix', () {
    expect(presetBaseName('# Bambu PLA Basic @BBL X1C'), 'bambu pla basic');
    expect(presetBaseName('SUNLU TPU @Bambu Lab H2D 0.4 nozzle'), 'sunlu tpu');
    expect(presetBaseName('Overture  PLA'), 'overture pla');
  });

  group('matchSlotPreset', () {
    test('takes the saved profile by id when it fits the printer', () {
      const local = SlicerPreset(
        source: 'local',
        id: '7',
        name: 'Overture PLA Matte',
      );
      final t = tray(
        saved: const LoadedSpoolPreset(
          presetId: 'local_7',
          presetName: 'Overture PLA Matte',
          presetSource: 'local',
        ),
      );
      expect(match(t, const [local]), 'local:7');
    });

    test('finds the selected printer\'s copy of a profile saved for another '
        'model', () {
      final filaments = [
        const SlicerPreset(
          source: 'cloud',
          id: 'GFSA00',
          name: 'Bambu PLA Basic @BBL X1C',
          filamentType: 'PLA',
        ),
        ...standardFilaments,
      ];
      final t = tray(
        trayInfoIdx: 'GFA00',
        saved: const LoadedSpoolPreset(
          presetId: 'GFSA00',
          presetName: 'Bambu PLA Basic',
          presetSource: 'cloud',
        ),
      );
      expect(match(t, filaments), 'standard:Bambu PLA Basic @BBL H2D');
      expect(
        match(t, filaments, 'Bambu Lab X1 Carbon 0.4 nozzle'),
        'cloud:GFSA00',
        reason: 'on an X1C the saved profile itself fits',
      );
    });

    test('names a Bambu spool nobody configured from its brand text', () {
      final t = tray(trayInfoIdx: 'GFA00', subBrands: 'PLA Basic');
      expect(match(t, standardFilaments), 'standard:Bambu PLA Basic @BBL H2D');
    });

    test('does not put "Bambu" in front of a third-party spool', () {
      final t = tray(trayInfoIdx: 'P4d64437', subBrands: 'PLA Basic');
      expect(match(t, standardFilaments), isNull);
    });

    test('uses the generic profile for a spool with no brand text', () {
      expect(
        match(tray(trayType: 'PETG', trayInfoIdx: 'GFG99'), standardFilaments),
        'standard:Generic PETG @BBL H2D',
      );
    });

    test('ignores a saved profile the slot was reconfigured away from', () {
      final filaments = [
        const SlicerPreset(
          source: 'local',
          id: '7',
          name: 'Overture PLA Matte',
        ),
        ...standardFilaments,
      ];
      final t = tray(
        trayInfoIdx: 'GFL99',
        saved: const LoadedSpoolPreset(
          presetId: 'local_7',
          presetName: 'Overture PLA Matte',
          presetSource: 'local',
          trayInfoIdx: 'GFL05',
        ),
      );
      expect(match(t, filaments), 'standard:Generic PLA @BBL H2D');
    });

    test('skips a same-named profile that states another material', () {
      expect(
        match(tray(trayType: 'PLA'), [std('Generic PLA @BBL H2D', 'PETG')]),
        isNull,
      );
    });

    test('matches nothing for an empty or unidentified slot', () {
      expect(match(tray(trayType: null), standardFilaments), isNull);
    });
  });

  group('printersOfModel and matchedFilamentKeys', () {
    final printers = [
      LoadedSpoolPrinter(
        id: 1,
        name: 'H2D one',
        model: 'H2D',
        ams: [
          LoadedSpoolUnit(
            id: 0,
            isAmsHt: false,
            trays: [
              tray(trayInfoIdx: 'GFA00', subBrands: 'PLA Basic'),
              tray(trayId: 1, trayType: null),
            ],
          ),
        ],
        external: [tray(amsId: 255, trayType: 'PETG', trayInfoIdx: 'GFG99')],
        externalHolders: 2,
      ),
      const LoadedSpoolPrinter(id: 2, name: 'X1C', model: 'X1C'),
    ];

    test('narrows to the selected model, and keeps all when unknown', () {
      expect(printersOfModel(printers, 'H2D').map((p) => p.id), [1]);
      expect(printersOfModel(printers, null).map((p) => p.id), [1, 2]);
    });

    test('collects the profiles of every loaded spool', () {
      final keys = matchedFilamentKeys(
        printers,
        filaments: standardFilaments,
        index: buildFilamentNameIndex(standardFilaments),
        selectedPrinterName: h2d,
        registry: models,
      );
      expect(keys.toList()..sort(), [
        'standard:Bambu PLA Basic @BBL H2D',
        'standard:Generic PETG @BBL H2D',
      ]);
    });
  });

  test('trayColourHex drops the alpha byte', () {
    LoadedSpoolTray coloured(String? c) =>
        LoadedSpoolTray(amsId: 0, trayId: 0, trayColor: c);
    expect(trayColourHex(coloured('ff8800FF')), '#FF8800');
    expect(trayColourHex(coloured(null)), isNull);
    expect(trayColourHex(coloured('zz')), isNull);
  });

  group('presetCompatibility', () {
    PresetFit fit(String name, {List<String>? compat}) => presetCompatibility(
      SlicerPreset(
        source: 'cloud',
        id: name,
        name: name,
        compatiblePrinters: compat,
      ),
      h2d,
      models,
    );

    test('reads both tag shapes, nozzle included', () {
      expect(fit('Bambu PLA Basic @BBL H2D'), PresetFit.match);
      expect(fit('Bambu PLA Basic @BBL X1C'), PresetFit.mismatch);
      expect(fit('Bambu PLA Basic @BBL H2D 0.6 nozzle'), PresetFit.mismatch);
      expect(
        fit('SUNLU TPU @Bambu Lab H2D 0.4 nozzle (Custom)'),
        PresetFit.match,
      );
    });

    test('a nozzle-only tag can rule out but never prove', () {
      expect(fit('Overture PLA @0.6'), PresetFit.mismatch);
      expect(fit('Overture PLA @0.4'), PresetFit.unknown);
      expect(fit('PLA @2026'), PresetFit.unknown);
    });

    test('an imported list decides, clone prefix ignored', () {
      expect(
        fit('Mine', compat: ['# Bambu Lab H2D 0.4 nozzle']),
        PresetFit.match,
      );
      expect(
        fit('Mine', compat: ['Bambu Lab X1 Carbon 0.4 nozzle']),
        PresetFit.mismatch,
      );
    });

    test('no tag, no answer', () {
      expect(fit('My own PLA'), PresetFit.unknown);
    });
  });

  test('slotPresetDescribesTray follows a Bambu id to its filament', () {
    expect(slotPresetDescribesTray('GFSA00', 'GFA00', null), isTrue);
    expect(slotPresetDescribesTray('GFSA00', 'GFL99', null), isFalse);
    expect(slotPresetDescribesTray('local_7', 'GFL99', 'GFL99'), isTrue);
    expect(slotPresetDescribesTray('local_7', 'GFL99', 'GFL05'), isFalse);
    expect(slotPresetDescribesTray('local_7', null, null), isTrue);
  });

  test('a spool the firmware sees but cannot name is unidentified', () {
    expect(
      const LoadedSpoolTray(amsId: 0, trayId: 0, exists: true).isUnidentified,
      isTrue,
    );
    expect(
      const LoadedSpoolTray(amsId: 0, trayId: 0, exists: false).isUnidentified,
      isFalse,
    );
    expect(
      const LoadedSpoolTray(amsId: 0, trayId: 0, state: 10).isUnidentified,
      isFalse,
    );
  });
}
