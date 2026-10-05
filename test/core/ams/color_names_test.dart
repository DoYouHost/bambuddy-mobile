import 'package:bambuddy_mobile/core/ams/color_names.dart';
import 'package:bambuddy_mobile/core/ams/slot_addressing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Against the web itself: every answer in the fixture comes from
/// `utils/colors.ts` and `amsHelpers.ts::formatSlotLabel`
/// (`tool/gen_filament_mapping_golden.sh`).
void main() {
  final golden = readFixture('color_names_golden.json') as Map<String, dynamic>;

  // The web's own family names, which go to the server as they are.
  String? english(ColorFamily? f) => f == null ? null : colorFamilyWireName(f);

  test('every hex falls in the family the web puts it in', () {
    for (final c in (golden['families'] as List).cast<Map<String, dynamic>>()) {
      expect(
        english(colorFamily(c['hex'] as String)),
        c['family'],
        reason: c['hex'] as String,
      );
    }
  });

  test('the catalogue names a hex, by material where it can', () {
    final catalog = ColorCatalog.fromJson(
      golden['catalog'] as Map<String, dynamic>,
    );
    for (final c in (golden['names'] as List).cast<Map<String, dynamic>>()) {
      final hex = c['hex'] as String;
      expect(
        catalog.nameOf(hex, material: c['material'] as String?) ??
            english(colorFamily(hex)),
        c['name'],
        reason: hex,
      );
    }
  });

  test('the name sent to the server is the web\'s getColorName', () {
    final catalog = ColorCatalog.fromJson(
      golden['catalog'] as Map<String, dynamic>,
    );
    for (final c in (golden['names'] as List).cast<Map<String, dynamic>>()) {
      if (c['material'] != null) continue;
      expect(colorNameForServer(catalog, c['hex'] as String), c['name']);
    }
    expect(colorNameForServer(ColorCatalog.empty, ''), 'Unknown');
  });

  test('two colours that read alike get their hex', () {
    for (final c in (golden['pairs'] as List).cast<Map<String, dynamic>>()) {
      final a = (c['a'] as List).cast<String?>();
      final b = (c['b'] as List).cast<String?>();
      final (first, second) = disambiguateColorNames(
        (name: a[0], hex: a[1]),
        (name: b[0], hex: b[1]),
      );
      expect([first, second], c['out'], reason: '$a / $b');
    }
  });

  test('slots are named as the web\'s mapping names them', () {
    for (final c in (golden['labels'] as List).cast<Map<String, dynamic>>()) {
      expect(
        formatSlotLabel(
          c['ams'] as int,
          c['tray'] as int,
          isHt: c['ht'] as bool,
        ),
        c['label'],
      );
    }
  });
}
