import 'package:bambuddy_mobile/core/ams/k_profile_match.dart';
import 'package:bambuddy_mobile/core/models/k_profile.dart';
import 'package:flutter_test/flutter_test.dart';

KProfile profile(
  String name, {
  int slotId = 1,
  String k = '0.020000',
  String filamentId = '',
  int extruderId = 0,
}) =>
    KProfile(
      slotId: slotId,
      name: name,
      kValue: k,
      filamentId: filamentId,
      extruderId: extruderId,
    );

void main() {
  group('matching', () {
    test('a shared filament id matches whatever the profile is called', () {
      // The user names a profile after the colour they calibrated; the id is
      // the only thing both sides agree on (bambuddy #1688).
      final black = profile('Czarny z szafy', slotId: 3, filamentId: 'GFG98');

      final choices = matchKProfiles(
        profiles: [black, profile('PETG something else', slotId: 4)],
        presetName: 'Bambu PETG-CF @BBL X1C',
        presetFilamentId: 'GFG98',
      );

      expect(choices.matching.map((p) => p.slotId), contains(3));
    });

    test('the id survives the version suffix the printer reports', () {
      final choices = matchKProfiles(
        profiles: [profile('whatever', filamentId: 'GFSG98_09')],
        presetName: 'Nothing recognisable',
        presetFilamentId: 'GFG98',
      );

      expect(choices.matching, hasLength(1));
    });

    test('a branded preset only takes profiles naming that brand', () {
      final choices = matchKProfiles(
        profiles: [
          profile('Azurefilm PLA test', slotId: 1),
          profile('PLA generic test', slotId: 2),
        ],
        presetName: 'Azurefilm PLA Wood @BBL X1C',
      );

      expect(choices.matching.map((p) => p.slotId), [1]);
      expect(choices.other.map((p) => p.slotId), [2],
          reason: 'the rest stays reachable, just not first');
    });

    test('"Generic PLA" is a preset name, not a manufacturer', () {
      // Read as a brand it demands "GENERIC" in the profile name, which no
      // real profile has — so every built-in preset would match nothing
      // (bambuddy #2710).
      final choices = matchKProfiles(
        profiles: [profile('PLA kalibracja', slotId: 5)],
        presetName: 'Generic PLA',
      );

      expect(choices.matching.map((p) => p.slotId), [5]);
    });

    test('nylon and PA are the same material under two names', () {
      final choices = matchKProfiles(
        profiles: [profile('PA-CF dry', slotId: 6)],
        presetName: 'Generic Nylon',
      );

      expect(choices.matching, hasLength(1));
    });

    test('a one-letter material matches nothing rather than everything', () {
      final choices = matchKProfiles(
        profiles: [profile('PLA basic'), profile('PETG basic')],
        presetName: 'X',
      );

      expect(choices.matching, isEmpty);
      expect(choices.other, hasLength(2));
    });

    test('an agreeing filament id does not care how short the material is', () {
      // The material guard exists to stop a one-letter substring matching half
      // the table by name; it says nothing about an id both sides agree on.
      final choices = matchKProfiles(
        profiles: [profile('whatever', slotId: 8, filamentId: 'GFL99')],
        presetName: 'X',
        presetFilamentId: 'GFL99',
      );

      expect(choices.matching.map((p) => p.slotId), [8]);
    });
  });

  group('the profile the slot is printing with', () {
    test('is offered first even when nothing about it matches', () {
      // A slot configured as "Generic PLA" can be bound to a profile
      // calibrated for something else; dropping it here would offer to reset
      // the printer to its default K without saying so (bambuddy #1689).
      final active = profile('Ekspery ment', slotId: 9, k: '0.045000');

      final choices = matchKProfiles(
        profiles: [active, profile('PLA basic', slotId: 2)],
        presetName: 'Generic PLA',
        activeCaliIdx: 9,
      );

      expect(choices.matching.first.slotId, 9);
      expect(choices.matching.map((p) => p.slotId), [9, 2]);
    });

    test('is the only thing offered before a preset is picked', () {
      final choices = matchKProfiles(
        profiles: [profile('A', slotId: 1), profile('B', slotId: 4)],
        activeCaliIdx: 4,
      );

      expect(choices.matching.map((p) => p.slotId), [4]);
      expect(choices.other.map((p) => p.slotId), [1]);
    });

    test('cali_idx 0 is the printer default, not a stored profile', () {
      final choices = matchKProfiles(
        profiles: [profile('A', slotId: 0)],
        activeCaliIdx: 0,
      );

      expect(choices.matching, isEmpty);
    });

    test('is not duplicated when it matches on its own merits', () {
      final choices = matchKProfiles(
        profiles: [profile('PLA basic', slotId: 7)],
        presetName: 'Generic PLA',
        activeCaliIdx: 7,
      );

      expect(choices.matching, hasLength(1));
    });
  });

  group('duplicates', () {
    test('one row per calibration, taking the nozzle the slot feeds', () {
      // A dual-nozzle printer reports the same calibration once per extruder.
      final choices = matchKProfiles(
        profiles: [
          profile('PLA basic', slotId: 1, extruderId: 0),
          profile('PLA basic', slotId: 2, extruderId: 1),
        ],
        presetName: 'Generic PLA',
        extruderId: 1,
      );

      expect(choices.matching, hasLength(1));
      expect(choices.matching.single.extruderId, 1);
    });

    test('same name, different K is two different profiles', () {
      final choices = matchKProfiles(
        profiles: [
          profile('PLA basic', slotId: 1, k: '0.020000'),
          profile('PLA basic', slotId: 2, k: '0.035000'),
        ],
        presetName: 'Generic PLA',
      );

      expect(choices.matching, hasLength(2));
    });

    test('same name and value but a different filament is not one profile', () {
      // Folding them makes the second unselectable — the duplicate rows this
      // dedup is for agree on the filament id, these two do not.
      final choices = matchKProfiles(
        profiles: [
          profile('Black', slotId: 1, filamentId: 'GFL99'),
          profile('Black', slotId: 2, filamentId: 'GFG99'),
        ],
        presetName: 'Generic PLA',
        presetFilamentId: 'GFL99',
      );

      expect(
        [...choices.matching, ...choices.other].map((p) => p.slotId),
        containsAll([1, 2]),
      );
    });

    test('a matched profile does not turn up in the other group as well', () {
      final choices = matchKProfiles(
        profiles: [
          profile('PLA basic', slotId: 1, extruderId: 0),
          profile('PLA basic', slotId: 2, extruderId: 1),
        ],
        presetName: 'Generic PLA',
      );

      expect(choices.other, isEmpty,
          reason: 'the duplicate row is the same calibration, not another one');
    });
  });

  test('everything the printer holds stays selectable', () {
    // The match runs on names a user typed, so it will sometimes be wrong; the
    // printer's table is the authority on what can be picked.
    final choices = matchKProfiles(
      profiles: [profile('zzz', slotId: 1), profile('aaa', slotId: 2)],
      presetName: 'Generic PETG',
    );

    expect(choices.matching, isEmpty);
    expect(choices.other.map((p) => p.name), ['aaa', 'zzz']);
  });

  group('the picker', () {
    test('finds a profile by the value the menu carries', () {
      final choices = matchKProfiles(
        profiles: [profile('PLA basic', slotId: 3)],
        presetName: 'Generic PLA',
      );

      expect(choices.byOptionId('PLA basic|0.020000|')?.slotId, 3);
      expect(choices.byOptionId(''), isNull, reason: 'the default');
      expect(choices.byOptionId('heading:other'), isNull);
    });

    test('is hidden when the printer holds nothing', () {
      expect(matchKProfiles(profiles: const []).any, isFalse);
    });
  });
}
