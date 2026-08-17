import 'package:bambuddy_mobile/core/ams/filament_preset_catalog.dart';
import 'package:bambuddy_mobile/core/models/ams_filament_preset.dart';
import 'package:flutter_test/flutter_test.dart';

const _models = <String, String>{
  'Bambu Lab X1 Carbon': 'X1C',
  'Bambu Lab A1': 'A1',
  'Bambu Lab A1 Mini': 'A1 Mini',
  'Bambu Lab H2D': 'H2D',
};

AmsFilamentPreset _cloud(String id, String name, {bool isUser = false}) =>
    AmsFilamentPreset(
      source: AmsPresetSource.cloud,
      id: id,
      name: name,
      isUser: isUser,
    );

AmsFilamentPreset _local(String id, String name, {List<String>? compatible}) =>
    AmsFilamentPreset(
      source: AmsPresetSource.local,
      id: id,
      name: name,
      compatiblePrinters: compatible,
    );

AmsFilamentPreset _builtin(String id, String name) =>
    AmsFilamentPreset(source: AmsPresetSource.builtin, id: id, name: name);

void main() {
  test('orders imported presets first, then cloud, then the built-in table',
      () {
    final list = filamentPresetCatalog(
      builtin: [_builtin('GFA00', 'Bambu ABS')],
      cloud: [_cloud('GFSL05', 'Bambu PLA Basic')],
      local: [_local('7', 'My PETG')],
    );

    expect(list.map((p) => p.pickerId),
        ['local_7', 'GFSL05', 'builtin_GFA00']);
  });

  test('sorts a user cloud preset above the ones Bambu ships', () {
    final list = filamentPresetCatalog(cloud: [
      _cloud('GFSL05', 'Bambu PLA Basic'),
      _cloud('PFUS123', 'A custom PLA', isUser: true),
    ]);

    expect(list.first.name, 'A custom PLA');
  });

  test('drops a built-in entry the cloud already offers', () {
    // The cloud lists setting ids ("GFSA00"), the built-in table filament ids
    // ("GFA00"). Comparing only one spelling shows the same filament twice.
    final list = filamentPresetCatalog(
      cloud: [_cloud('GFSA00', 'Bambu ABS')],
      builtin: [_builtin('GFA00', 'Bambu ABS'), _builtin('GFB99', 'Generic')],
    );

    expect(list.map((p) => p.pickerId), ['GFSA00', 'builtin_GFB99']);
  });

  test('a hidden cloud preset does not take its built-in twin with it', () {
    // Otherwise filtering the H2D's PETG out for an X1C removes generic PETG
    // as well, and the material cannot be picked at all.
    final list = filamentPresetCatalog(
      cloud: [_cloud('GFSG99', 'Bambu PETG @BBL H2D')],
      builtin: [_builtin('GFG99', 'Generic PETG')],
      printerModel: 'X1C',
      printerModels: _models,
    );

    expect(list.map((p) => p.pickerId), ['builtin_GFG99']);
  });

  test('a cloud preset the search hid does not cover its built-in twin', () {
    final list = filamentPresetCatalog(
      cloud: [_cloud('GFSG99', 'Bambu Polyterpene')],
      builtin: [_builtin('GFG99', 'Generic PETG')],
      query: 'petg',
    );

    expect(list.map((p) => p.pickerId), ['builtin_GFG99']);
  });

  test('hides a cloud preset that names a different printer', () {
    final list = filamentPresetCatalog(
      cloud: [
        _cloud('GFSL05', 'Bambu PLA Basic @BBL X1C'),
        _cloud('GFSG99', 'Bambu PETG @BBL H2D'),
      ],
      printerModel: 'X1C',
      printerModels: _models,
    );

    expect(list.map((p) => p.name), ['Bambu PLA Basic @BBL X1C']);
  });

  test('keeps a preset that names no printer at all', () {
    // Failing open: a name we cannot classify is not evidence of a mismatch,
    // and hiding it would remove a preset that works.
    final list = filamentPresetCatalog(
      cloud: [_cloud('GFSL05', 'Generic PLA')],
      printerModel: 'X1C',
      printerModels: _models,
    );

    expect(list, hasLength(1));
  });

  test('keeps an A1 Mini preset for a printer the cloud renamed to A1M', () {
    final list = filamentPresetCatalog(
      cloud: [_cloud('GFSL05', 'Bambu PLA @BBL A1M')],
      printerModel: 'A1 Mini',
      printerModels: _models,
    );

    expect(list, hasLength(1));
  });

  test('hides an imported preset whose own compatibility list excludes us', () {
    final list = filamentPresetCatalog(
      local: [
        _local('1', 'H2D only',
            compatible: const ['Bambu Lab H2D 0.4 nozzle']),
        _local('2', 'For us', compatible: const ['Bambu Lab X1 Carbon 0.4 nozzle']),
      ],
      fullPrinterName: 'Bambu Lab X1 Carbon 0.4 nozzle',
    );

    expect(list.map((p) => p.name), ['For us']);
  });

  test('keeps an imported preset that declares no compatibility at all', () {
    // Hand-edited and lossily-imported bundles have no list; they worked
    // before the filter existed and must keep working.
    final list = filamentPresetCatalog(
      local: [_local('1', 'Nameless')],
      fullPrinterName: 'Bambu Lab X1 Carbon 0.4 nozzle',
    );

    expect(list, hasLength(1));
  });

  test('keeps the slot\'s current preset even when the filter would drop it',
      () {
    // Reopening the sheet on a slot must not silently offer to change it.
    final list = filamentPresetCatalog(
      cloud: [_cloud('GFSG99', 'Bambu PETG @BBL H2D')],
      printerModel: 'X1C',
      printerModels: _models,
      savedPresetId: 'GFSG99',
    );

    expect(list, hasLength(1));
  });

  test('recognises the current preset by the filament id the printer reports',
      () {
    // The printer knows "GFG99"; the cloud lists it as "GFSG99_04".
    final list = filamentPresetCatalog(
      cloud: [_cloud('GFSG99_04', 'Bambu PETG @BBL H2D')],
      printerModel: 'X1C',
      printerModels: _models,
      currentFilamentId: 'GFG99',
    );

    expect(list, hasLength(1));
  });

  test('applies the search to the current preset too', () {
    // A search that kept showing one unmatched row looks broken.
    final list = filamentPresetCatalog(
      cloud: [_cloud('GFSG99', 'Bambu PETG')],
      query: 'pla',
      savedPresetId: 'GFSG99',
    );

    expect(list, isEmpty);
  });

  test('searches case-insensitively across every tier', () {
    final list = filamentPresetCatalog(
      cloud: [_cloud('GFSL05', 'Bambu PLA Basic')],
      local: [_local('1', 'My PETG')],
      builtin: [_builtin('GFB99', 'Generic ABS')],
      query: 'pla',
    );

    expect(list.map((p) => p.name), ['Bambu PLA Basic']);
  });
}
