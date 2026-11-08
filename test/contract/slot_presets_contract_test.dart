import 'package:bambuddy_mobile/core/models/ams_filament_preset.dart';
import 'package:bambuddy_mobile/data/ams_slot_config_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

/// The saved slot presets the dashboard names its slot rows after (#64): one
/// listing per printer, keyed by the server's own slot number, and the
/// filament id each was saved with.
void main() {
  group('slot presets contract', skip: contractSkipReason, () {
    late Dio dio;
    late AmsSlotConfigRepository slots;
    late int printerId;

    setUpAll(() async {
      dio = await authenticatedDio();
      slots = AmsSlotConfigRepository(dio);
      printerId =
          ((await dio.get<List<dynamic>>('/api/v1/printers/')).data!.first
                  as Map<String, dynamic>)['id']
              as int;
    });

    tearDown(() async {
      for (final (ams, tray) in [(0, 2), (255, 1)]) {
        try {
          await dio.delete<dynamic>(
            '/api/v1/printers/$printerId/slot-presets/$ams/$tray',
          );
        } on DioException {
          // Nothing saved there: nothing to clean.
        }
      }
    });

    test('a saved preset reads back by unit and tray, the external holder '
        'included, with the filament id it was saved with', () async {
      const preset = AmsFilamentPreset(
        source: AmsPresetSource.local,
        id: '7',
        name: 'eSUN PETG',
      );
      await slots.saveSlotPreset(
        printerId,
        amsId: 0,
        trayId: 2,
        preset: preset,
        presetName: 'eSUN PETG',
        trayInfoIdx: 'P4d5e6f7',
      );
      await slots.saveSlotPreset(
        printerId,
        amsId: 255,
        trayId: 1,
        preset: preset,
        presetName: 'Generic PLA',
        trayInfoIdx: 'GFA00',
      );

      final all = await slots.slotPresets(printerId);

      expect(all[(0, 2)]?.presetName, 'eSUN PETG');
      expect(all[(0, 2)]?.presetId, 'local_7');
      expect(all[(255, 1)]?.presetName, 'Generic PLA');
      // Recorded since #3216; an older server drops it and the app reads null.
      if (all[(0, 2)]!.trayInfoIdx == null) {
        markTestSkipped('this server does not record tray_info_idx');
        return;
      }
      expect(all[(0, 2)]!.trayInfoIdx, 'P4d5e6f7');
      expect(all[(255, 1)]!.trayInfoIdx, 'GFA00');
    });

    test('a printer with nothing saved lists nothing', () async {
      expect(await slots.slotPresets(printerId), isEmpty);
    });
  });
}
