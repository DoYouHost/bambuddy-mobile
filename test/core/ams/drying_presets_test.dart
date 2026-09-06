import 'package:bambuddy_mobile/core/ams/drying_presets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('drying presets from the server setting', () {
    /// The shape the server stores: a JSON **string**, one object per filament,
    /// `n3f`/`n3s` being the AMS 2 Pro and the AMS-HT.
    const configured =
        '{"PETG":{"n3f":70,"n3s":72,"n3f_hours":8,'
        '"n3s_hours":6},"PLA":{"n3f":45,"n3s":45,"n3f_hours":12,'
        '"n3s_hours":12}}';

    test('a configured table is what the sheet offers', () {
      final presets = dryingPresetsFrom(configured);

      expect(presets['PETG'], (temp: 70, htTemp: 72, hours: 8, htHours: 6));
      expect(presets['PLA'], (temp: 45, htTemp: 45, hours: 12, htHours: 12));
    });

    /// The server uses a configured blob whole rather than merging it over the
    /// defaults, so a filament left out of it is one its own auto-drying has
    /// never heard of either.
    test(
      'a configured table replaces the built-in one, it does not extend it',
      () {
        final presets = dryingPresetsFrom(configured);

        expect(presets.keys, ['PETG', 'PLA']);
        expect(presets.containsKey('ABS'), isFalse);
      },
    );

    test('an object, not a string, is read the same way', () {
      final presets = dryingPresetsFrom({
        'ASA': {'n3f': 60, 'n3s': 80, 'n3f_hours': 10, 'n3s_hours': 8},
      });

      expect(presets['ASA'], (temp: 60, htTemp: 80, hours: 10, htHours: 8));
    });

    test('numbers written as strings still count', () {
      final presets = dryingPresetsFrom(
        '{"PC":{"n3f":"65","n3s":"80","n3f_hours":"12","n3s_hours":"8"}}',
      );

      expect(presets['PC'], (temp: 65, htTemp: 80, hours: 12, htHours: 8));
    });

    group('falls back to the table the server itself would use', () {
      test('nothing configured — the setting is an empty string', () {
        expect(dryingPresetsFrom(''), defaultDryingPresets);
        expect(dryingPresetsFrom('   '), defaultDryingPresets);
      });

      test('the setting is absent, or settings could not be read at all', () {
        expect(dryingPresetsFrom(null), defaultDryingPresets);
      });

      test('the blob is not JSON', () {
        expect(dryingPresetsFrom('{oops'), defaultDryingPresets);
      });

      test('the blob is JSON but not an object', () {
        expect(dryingPresetsFrom('[1,2,3]'), defaultDryingPresets);
        expect(dryingPresetsFrom('42'), defaultDryingPresets);
      });

      test('the blob is an empty object', () {
        expect(dryingPresetsFrom('{}'), defaultDryingPresets);
      });

      /// Every row unusable says the same thing an empty blob does, and the
      /// server would be drying by its own defaults.
      test('every row is malformed', () {
        expect(
          dryingPresetsFrom('{"PLA":"hot","PETG":null}'),
          defaultDryingPresets,
        );
      });
    });

    /// A half-read row would dry a spool for a length of time nobody chose.
    test('a row missing a field is skipped, the rest survive', () {
      final presets = dryingPresetsFrom(
        '{"PLA":{"n3f":45,"n3s":45,"n3f_hours":12},'
        '"TPU":{"n3f":65,"n3s":75,"n3f_hours":12,"n3s_hours":18}}',
      );

      expect(presets.containsKey('PLA'), isFalse);
      expect(presets['TPU'], (temp: 65, htTemp: 75, hours: 12, htHours: 18));
    });

    /// Pinned against `PrintScheduler.DEFAULT_DRYING_PRESETS` — the two tables
    /// disagreeing is the whole failure this reads the setting to avoid.
    test('the bundled fallback is the server\'s own default table', () {
      expect(defaultDryingPresets, hasLength(8));
      expect(defaultDryingPresets['PLA'], (
        temp: 45,
        htTemp: 45,
        hours: 12,
        htHours: 12,
      ));
      expect(defaultDryingPresets['PETG'], (
        temp: 65,
        htTemp: 65,
        hours: 12,
        htHours: 12,
      ));
      expect(defaultDryingPresets['TPU'], (
        temp: 65,
        htTemp: 75,
        hours: 12,
        htHours: 18,
      ));
      expect(defaultDryingPresets['ABS'], (
        temp: 65,
        htTemp: 80,
        hours: 12,
        htHours: 8,
      ));
      expect(defaultDryingPresets['ASA'], (
        temp: 65,
        htTemp: 80,
        hours: 12,
        htHours: 8,
      ));
      expect(defaultDryingPresets['PA'], (
        temp: 65,
        htTemp: 85,
        hours: 12,
        htHours: 12,
      ));
      expect(defaultDryingPresets['PC'], (
        temp: 65,
        htTemp: 80,
        hours: 12,
        htHours: 8,
      ));
      expect(defaultDryingPresets['PVA'], (
        temp: 65,
        htTemp: 85,
        hours: 12,
        htHours: 18,
      ));
    });
  });

  group('the server\'s own drying automation', () {
    test('reads the three switches', () {
      final auto = autoDryingFrom(const {
        'queue_drying_enabled': true,
        'ambient_drying_enabled': false,
        'print_drying_enabled': true,
      });

      expect(auto, (betweenPrints: true, whenIdle: false, whilePrinting: true));
    });

    test('settings that could not be read mean nothing is claimed', () {
      expect(autoDryingFrom(const {}), noAutoDrying);
    });
  });
}
