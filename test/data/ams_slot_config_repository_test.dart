import 'package:bambuddy_mobile/core/ams/slot_configuration.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/ams_filament_preset.dart';
import 'package:bambuddy_mobile/data/ams_slot_config_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late AmsSlotConfigRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    repo = AmsSlotConfigRepository(dio);
  });

  group('preset sources', () {
    test('reads the filament tier out of the cloud settings', () {
      adapter.onGet(
        '/api/v1/cloud/settings',
        (s) => s.reply(200, {
          'filament': [
            {'setting_id': 'GFSL05_09', 'name': 'Bambu PLA Basic'},
            {'setting_id': 'PFUS123', 'name': 'My PLA', 'is_custom': true},
          ],
          'printer': [
            {'setting_id': 'GFSP01', 'name': 'X1C 0.4'},
          ],
        }),
      );

      expect(
        repo.cloudFilaments(),
        completion(
          isA<List<AmsFilamentPreset>>()
              .having((l) => l.map((p) => p.id), 'ids', [
                'GFSL05_09',
                'PFUS123',
              ])
              .having((l) => l.last.isUser, 'a user preset is marked', isTrue),
        ),
      );
    });

    test(
      'a missing cloud login surfaces as unauthorized, not as an empty list',
      () {
        // The picker has to tell "no presets" from "log in to see yours".
        adapter.onGet(
          '/api/v1/cloud/settings',
          (s) => s.reply(401, {'detail': 'Not authenticated'}),
        );

        expect(
          repo.cloudFilaments(),
          throwsA(
            isA<AuthException>().having(
              (e) => e.code,
              'code',
              AppErrorCode.unauthorized,
            ),
          ),
        );
      },
    );

    test('decodes an imported preset\'s compatibility list', () {
      adapter.onGet(
        '/api/v1/local-presets/',
        (s) => s.reply(200, {
          'filament': [
            {
              'id': 7,
              'name': 'eSUN PETG',
              'filament_type': 'PETG',
              'nozzle_temp_min': 230,
              'nozzle_temp_max': 250,
              'compatible_printers': '["Bambu Lab X1 Carbon 0.4 nozzle"]',
            },
          ],
        }),
      );

      expect(
        repo.localFilaments(),
        completion(
          isA<List<AmsFilamentPreset>>()
              .having((l) => l.single.pickerId, 'picker id', 'local_7')
              .having(
                (l) => l.single.compatiblePrinters,
                'compatible printers',
                ['Bambu Lab X1 Carbon 0.4 nozzle'],
              )
              .having((l) => l.single.nozzleTempMin, 'min temperature', 230),
        ),
      );
    });

    test('keeps an imported preset whose compatibility list is not JSON', () {
      // Unreadable evidence is not evidence — the preset stays offered.
      adapter.onGet(
        '/api/v1/local-presets/',
        (s) => s.reply(200, {
          'filament': [
            {'id': 7, 'name': 'eSUN PETG', 'compatible_printers': 'not json'},
          ],
        }),
      );

      expect(
        repo.localFilaments(),
        completion(
          isA<List<AmsFilamentPreset>>().having(
            (l) => l.single.compatiblePrinters,
            'compatible printers',
            isNull,
          ),
        ),
      );
    });

    test('reads the built-in table', () {
      adapter.onGet(
        '/api/v1/cloud/builtin-filaments',
        (s) => s.reply(200, [
          {'filament_id': 'GFL99', 'name': 'Generic PLA'},
        ]),
      );

      expect(
        repo.builtinFilaments(),
        completion(
          isA<List<AmsFilamentPreset>>().having(
            (l) => l.single.pickerId,
            'picker id',
            'builtin_GFL99',
          ),
        ),
      );
    });

    test('skips a preset the server sent without an id', () {
      // An entry with no id cannot be selected, and would crash the write.
      adapter.onGet(
        '/api/v1/cloud/builtin-filaments',
        (s) => s.reply(200, [
          {'name': 'Nameless'},
          {'filament_id': 'GFL99', 'name': 'Generic PLA'},
        ]),
      );

      expect(repo.builtinFilaments(), completion(hasLength(1)));
    });

    test('reads the printer-model registry', () {
      adapter.onGet(
        '/api/v1/slicer/printer-models',
        (s) => s.reply(200, {'Bambu Lab X1 Carbon': 'X1C'}),
      );

      expect(repo.printerModels(), completion({'Bambu Lab X1 Carbon': 'X1C'}));
    });
  });

  group('cloudFilamentId', () {
    test('answers the filament id from the preset detail', () {
      adapter.onGet(
        '/api/v1/cloud/settings/PFUS123',
        (s) => s.reply(200, {'filament_id': 'P285e239', 'base_id': 'GFL99'}),
      );

      expect(repo.cloudFilamentId('PFUS123'), completion('P285e239'));
    });

    test('answers null rather than failing when the detail cannot be read', () {
      // Best effort: losing the better id must not stop the slot being
      // configured with the one derived from the setting id.
      adapter.onGet(
        '/api/v1/cloud/settings/PFUS123',
        (s) => s.reply(500, {'detail': 'boom'}),
      );

      expect(repo.cloudFilamentId('PFUS123'), completion(isNull));
    });
  });

  group('slot presets', () {
    test('reads the mapping saved for a slot', () {
      adapter.onGet(
        '/api/v1/printers/1/slot-presets/0/2',
        (s) => s.reply(200, {
          'ams_id': 0,
          'tray_id': 2,
          'preset_id': 'GFSL05_09',
          'preset_name': 'Bambu PLA Basic',
        }),
      );

      expect(
        repo.slotPreset(1, amsId: 0, trayId: 2),
        completion(
          isA<SlotPreset>().having((p) => p.presetId, 'preset id', 'GFSL05_09'),
        ),
      );
    });

    test('an unmapped slot answers null, not an empty mapping', () {
      adapter.onGet(
        '/api/v1/printers/1/slot-presets/0/2',
        (s) => s.reply(200, null),
      );

      expect(repo.slotPreset(1, amsId: 0, trayId: 2), completion(isNull));
    });

    test('saves the mapping with the id the picker uses', () async {
      adapter.onPut(
        '/api/v1/printers/1/slot-presets/0/2',
        (s) => s.reply(200, {'ams_id': 0, 'tray_id': 2}),
        queryParameters: {
          'preset_id': 'local_7',
          'preset_name': 'eSUN PETG',
          'preset_source': 'local',
        },
      );

      await repo.saveSlotPreset(
        1,
        amsId: 0,
        trayId: 2,
        preset: const AmsFilamentPreset(
          source: AmsPresetSource.local,
          id: '7',
          name: 'eSUN PETG',
        ),
        presetName: 'eSUN PETG',
      );
    });
  });

  group('the two commands', () {
    test('configure addresses the slot by its local ids', () async {
      // Not the global tray number `ams/load` takes — the server resolves the
      // external spool itself by adding 254.
      adapter.onPost(
        '/api/v1/printers/1/slots/255/1/configure',
        (s) => s.reply(200, {'success': true}),
        queryParameters: {
          'tray_info_idx': 'GFL99',
          'tray_type': 'PLA',
          'tray_sub_brands': 'Generic PLA',
          'tray_color': 'FFFFFFFF',
          'nozzle_temp_min': 190,
          'nozzle_temp_max': 230,
          'cali_idx': -1,
          'nozzle_diameter': '0.4',
          'setting_id': '',
          'kprofile_filament_id': '',
          'kprofile_setting_id': '',
          'k_value': 0,
        },
      );

      await repo.configureSlot(
        1,
        amsId: 255,
        trayId: 1,
        configuration: SlotConfiguration.forPreset(
          preset: const AmsFilamentPreset(
            source: AmsPresetSource.builtin,
            id: 'GFL99',
            name: 'Generic PLA',
          ),
          colourHex: 'FFFFFF',
          nozzleDiameter: '0.4',
        ),
      );
    });

    test('reset posts to the tray route', () async {
      adapter.onPost(
        '/api/v1/printers/1/ams/0/tray/3/reset',
        (s) => s.reply(200, {'success': true}),
      );

      await repo.resetSlot(1, amsId: 0, trayId: 3);
    });

    test('a printer that is not connected surfaces its 400', () {
      // The route answers 400 for a disconnected printer; the sheet says so
      // rather than reporting success.
      adapter.onPost(
        '/api/v1/printers/1/ams/0/tray/3/reset',
        (s) => s.reply(400, {'detail': 'Printer not connected'}),
      );

      expect(
        repo.resetSlot(1, amsId: 0, trayId: 3),
        throwsA(isA<ApiException>()),
      );
    });

    test('a key without printers:control is refused', () {
      adapter.onPost(
        '/api/v1/printers/1/ams/0/tray/3/reset',
        (s) => s.reply(403, {'detail': 'forbidden'}),
      );

      expect(
        repo.resetSlot(1, amsId: 0, trayId: 3),
        throwsA(
          isA<AuthException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.forbidden,
          ),
        ),
      );
    });
  });

  group('K profiles', () {
    test('reads the printer table for one nozzle size', () async {
      // The diameter is a filter, not a hint: a 0.4 calibration means nothing
      // on a 0.6 nozzle.
      adapter.onGet(
        '/api/v1/printers/1/kprofiles/',
        (s) => s.reply(200, {
          'nozzle_diameter': '0.6',
          'profiles': [
            {
              'slot_id': 3,
              'name': 'PLA basic',
              'k_value': '0.020000',
              'filament_id': 'GFL05',
              'extruder_id': 1,
              'setting_id': 'PFUS123',
            },
            'not an object',
          ],
        }),
        queryParameters: {'nozzle_diameter': '0.6'},
      );

      final profiles = await repo.kProfiles(1, nozzleDiameter: '0.6');

      expect(profiles, hasLength(1), reason: 'a junk row drops, the rest stay');
      expect(profiles.single.slotId, 3);
      expect(profiles.single.k, 0.02);
      expect(
        profiles.single.kValue,
        '0.020000',
        reason: 'kept verbatim — it is half the identity key',
      );
      expect(profiles.single.optionId, 'PLA basic|0.020000|GFL05');
    });

    test('a printer that is not connected surfaces its 400', () {
      // Left to the caller: the sheet drops the picker rather than failing.
      adapter.onGet(
        '/api/v1/printers/1/kprofiles/',
        (s) => s.reply(400, {'detail': 'Printer not connected'}),
        queryParameters: {'nozzle_diameter': '0.4'},
      );

      expect(
        repo.kProfiles(1, nozzleDiameter: '0.4'),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
