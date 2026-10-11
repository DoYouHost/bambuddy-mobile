import 'package:bambuddy_mobile/core/ams/filament_mapping.dart';
import 'package:bambuddy_mobile/core/models/filament_requirement.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The port against the web itself: every case in the fixture was answered by
/// `useFilamentMapping.ts` (`tool/gen_filament_mapping_golden.sh`), from the
/// same printer and file JSON this test parses.
void main() {
  final cases = (readFixture('filament_mapping_golden.json') as List)
      .cast<Map<String, dynamic>>();

  test('every golden case maps as the web does', () {
    for (var n = 0; n < cases.length; n++) {
      final c = cases[n];
      final status = PrinterStatus.fromJson(
        c['status'] as Map<String, dynamic>,
      );
      final requirements = FilamentRequirement.parseList({
        'filaments': c['filaments'],
      });
      final loaded = buildLoadedFilaments(status);

      expect(
        [
          for (final l in loaded)
            {
              'global': l.globalTrayId,
              'color': l.color,
              'extruder': l.extruderId,
            },
        ],
        c['loaded'],
        reason: 'case $n: loaded slots',
      );

      final comparison = buildFilamentComparison(
        requirements,
        loaded,
        {
          for (final MapEntry(:key, :value)
              in (c['manual'] as Map<String, dynamic>).entries)
            int.parse(key): value as int,
        },
        preferLowest: effectivePreferLowest(
          c['setting'] as bool,
          status.amsFilamentBackup,
        ),
        inventoryByTrayId: {
          for (final MapEntry(:key, :value)
              in (c['inventory'] as Map<String, dynamic>).entries)
            int.parse(key): (value as num).toDouble(),
        },
        ftsActive: status.filaSwitch?.installed ?? false,
      );

      expect(buildAmsMapping(comparison), c['mapping'], reason: 'case $n');
      expect(
        [
          for (final x in comparison)
            switch (x.status) {
              FilamentMatch.match => 'match',
              FilamentMatch.typeOnly => 'type_only',
              FilamentMatch.mismatch => 'mismatch',
            },
        ],
        c['statuses'],
        reason: 'case $n: verdicts',
      );
    }
  });

  group('ciede2000', () {
    // Sharma, Wu & Dalal (2005), the reference pairs for the formula.
    test('reproduces the published reference pairs', () {
      expect(
        ciede2000([50, 2.6772, -79.7751], [50, 0, -82.7485]),
        closeTo(2.0425, 1e-4),
      );
      expect(
        ciede2000([50, 3.1571, -77.2803], [50, 0, -82.7485]),
        closeTo(2.8615, 1e-4),
      );
      expect(ciede2000([50, 2.5, 0], [50, 0, -2.5]), closeTo(4.3065, 1e-4));
      expect(
        ciede2000([60.2574, -34.0099, 36.2677], [60.4626, -34.1751, 39.4387]),
        closeTo(1.2644, 1e-4),
      );
    });
  });

  test('a mapping keeps the file\'s slot numbers', () {
    // A plate printing only slot 3 still sends [-1, -1, tray].
    const loaded = LoadedFilament(
      type: 'PLA',
      color: '#ff0000',
      amsId: 0,
      trayId: 1,
      isHt: false,
      isExternal: false,
      globalTrayId: 1,
    );
    final comparison = buildFilamentComparison(
      const [FilamentRequirement(slotId: 3, type: 'PLA', color: '#FF0000')],
      [loaded],
      const {},
    );
    expect(buildAmsMapping(comparison), [-1, -1, 1]);
    expect(buildAmsMapping(const []), isNull);
  });

  test('backup off overrides the setting; unknown keeps it', () {
    expect(effectivePreferLowest(true, false), isFalse);
    expect(effectivePreferLowest(true, null), isTrue);
    expect(effectivePreferLowest(false, true), isFalse);
  });
}
