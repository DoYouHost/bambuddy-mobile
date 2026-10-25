import 'package:bambuddy_mobile/core/settings/appearance_prefs.dart';
import 'package:bambuddy_mobile/core/theme/app_brand.dart';
import 'package:bambuddy_mobile/core/theme/appearance_providers.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  SystemSchemes schemes(Color seed, DynamicSchemeVariant variant) => (
    light: ColorScheme.fromSeed(seedColor: seed, dynamicSchemeVariant: variant),
    dark: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      dynamicSchemeVariant: variant,
    ),
  );

  test('every accent passes the contrast audit', () {
    for (final accent in AccentSource.values) {
      expect(
        dashContrastAudit(resolveBrand(accent, null)),
        isEmpty,
        reason: accent.name,
      );
    }
  });

  test('every preset is its own colour', () {
    final fills = {
      for (final accent in accentPresets.keys)
        resolveBrand(accent, null).light.fill,
      bambuddyBrand.light.fill,
    };
    expect(fills, hasLength(accentPresets.length + 1));
  });

  // A stored "System" on a phone below Android 12, or one restored from a
  // backup onto such a phone, must still paint an accent.
  test('System without a palette is the green brand', () {
    expect(resolveBrand(AccentSource.system, null), bambuddyBrand);
  });

  test('System follows the palette it is given and passes the audit', () {
    for (final palette in [
      schemes(const Color(0xFFB3261E), DynamicSchemeVariant.tonalSpot),
      schemes(const Color(0xFF7A7A7A), DynamicSchemeVariant.monochrome),
    ]) {
      final brand = resolveBrand(AccentSource.system, palette);
      expect(brand, isNot(bambuddyBrand));
      expect(dashContrastAudit(brand), isEmpty);
    }
  });

  test('graphite is an exact grey', () {
    final brand = resolveBrand(AccentSource.graphite, null);
    for (final c in [brand.light.fill, brand.light.ink, brand.dark.fill]) {
      expect(c.r == c.g && c.g == c.b, isTrue, reason: '$c');
    }
  });
}
