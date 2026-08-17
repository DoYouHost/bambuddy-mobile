import 'package:bambuddy_mobile/core/ams/slot_configuration.dart';
import 'package:bambuddy_mobile/core/models/filament_preset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a Bambu cloud preset sends its own setting id and filament id', () {
    final config = SlotConfiguration.forPreset(
      preset: FilamentPreset(
        source: FilamentPresetSource.cloud,
        id: 'GFSL05_09',
        name: 'Bambu PLA Basic @BBL X1C',
      ),
      colourHex: 'FF0000',
      nozzleDiameter: '0.4',
    );

    expect(config.trayInfoIdx, 'GFL05');
    expect(config.settingId, 'GFSL05_09');
    expect(config.trayType, 'PLA');
    expect(config.traySubBrands, 'Bambu PLA Basic');
    expect(config.nozzleTempMin, 190);
    expect(config.nozzleTempMax, 230);
  });

  test('a user cloud preset prefers the filament id read from its detail', () {
    // Deriving the id from the setting id would resolve the slot to the
    // generic the preset inherits from (bambuddy #1053).
    final config = SlotConfiguration.forPreset(
      preset: FilamentPreset(
        source: FilamentPresetSource.cloud,
        id: 'PFUS9ac902733670a9',
        name: 'Devil Design PETG @Bambu Lab X1 Carbon 0.4 nozzle',
        isUser: true,
      ),
      colourHex: '00FF00',
      nozzleDiameter: '0.4',
      cloudFilamentId: 'P285e239',
    );

    expect(config.trayInfoIdx, 'P285e239');
    expect(config.settingId, 'PFUS9ac902733670a9');
    expect(config.traySubBrands, 'Devil Design PETG');
  });

  test('a built-in entry is already the filament id, and carries no setting',
      () {
    // Sending a setting id the printer cannot look up leaves the slot half
    // configured.
    final config = SlotConfiguration.forPreset(
      preset: FilamentPreset(
        source: FilamentPresetSource.builtin,
        id: 'GFG99',
        name: 'Generic PETG',
      ),
      colourHex: '112233',
      nozzleDiameter: '0.6',
    );

    expect(config.trayInfoIdx, 'GFG99');
    expect(config.settingId, '');
    expect(config.trayType, 'PETG');
    expect(config.nozzleTempMin, 220);
    expect(config.nozzleTempMax, 260);
  });

  test('an imported preset falls back to the closest Bambu generic', () {
    final config = SlotConfiguration.forPreset(
      preset: FilamentPreset(
        source: FilamentPresetSource.local,
        id: '7',
        name: 'eSUN ABS+ @Bambu Lab X1 Carbon 0.4 nozzle',
        filamentType: 'ABS',
      ),
      colourHex: 'FFFFFF',
      nozzleDiameter: '0.4',
    );

    expect(config.trayInfoIdx, 'GFB99');
    expect(config.settingId, '');
    expect(config.trayType, 'ABS');
  });

  test('an imported preset keeps the temperatures its bundle recorded', () {
    final config = SlotConfiguration.forPreset(
      preset: FilamentPreset(
        source: FilamentPresetSource.local,
        id: '7',
        name: 'eSUN PLA Pro',
        filamentType: 'PLA',
        nozzleTempMin: 205,
        nozzleTempMax: 225,
      ),
      colourHex: 'FFFFFF',
      nozzleDiameter: '0.4',
    );

    expect(config.nozzleTempMin, 205);
    expect(config.nozzleTempMax, 225);
  });

  test('a half-recorded range fills its gap from the material, not from PLA',
      () {
    final config = SlotConfiguration.forPreset(
      preset: FilamentPreset(
        source: FilamentPresetSource.local,
        id: '7',
        name: 'eSUN PETG',
        filamentType: 'PETG',
        nozzleTempMin: 235,
      ),
      colourHex: 'FFFFFF',
      nozzleDiameter: '0.4',
    );

    expect(config.nozzleTempMin, 235);
    expect(config.nozzleTempMax, 260);
  });

  test('reads the material from the name, over the type the bundle stored', () {
    // Older importers record "PLA Support for PETG" as PLA; the printer would
    // then get a range 40 °C too cold.
    final config = SlotConfiguration.forPreset(
      preset: FilamentPreset(
        source: FilamentPresetSource.local,
        id: '7',
        name: 'PLA Support for PETG',
        filamentType: 'PLA',
      ),
      colourHex: 'FFFFFF',
      nozzleDiameter: '0.4',
    );

    expect(config.trayType, 'PETG');
    expect(config.nozzleTempMax, 260);
  });

  test('makes the colour opaque, and leaves the hash off', () {
    // The server answers 422 for a `#`, and a transparent alpha is how an
    // empty slot is reported.
    final config = SlotConfiguration.forPreset(
      preset: FilamentPreset(
        source: FilamentPresetSource.builtin,
        id: 'GFL99',
        name: 'Generic PLA',
      ),
      colourHex: 'A1B2C3',
      nozzleDiameter: '0.4',
    );

    expect(config.trayColour, 'A1B2C3FF');
  });

  test('sends every parameter the route declares', () {
    // All 12 are required or defaulted server-side; a missing one is a 422.
    final query = SlotConfiguration.forPreset(
      preset: FilamentPreset(
        source: FilamentPresetSource.builtin,
        id: 'GFL99',
        name: 'Generic PLA',
      ),
      colourHex: 'FFFFFF',
      nozzleDiameter: '0.4',
    ).toQuery();

    expect(query.keys, containsAll(<String>[
      'tray_info_idx',
      'tray_type',
      'tray_sub_brands',
      'tray_color',
      'nozzle_temp_min',
      'nozzle_temp_max',
      'cali_idx',
      'nozzle_diameter',
      'setting_id',
      'kprofile_filament_id',
      'kprofile_setting_id',
      'k_value',
    ]));
    // No K profile picked yet — the printer keeps its default K = 0.020.
    expect(query['cali_idx'], -1);
    expect(query['k_value'], 0);
  });
}
