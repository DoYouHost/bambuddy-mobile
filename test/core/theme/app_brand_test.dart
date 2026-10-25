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

  group('watchAccent', () {
    test('the green brand and a System without a palette send nothing', () {
      expect(watchAccent(AccentSource.bambuddy, null), isNull);
      expect(watchAccent(AccentSource.system, null), isNull);
    });

    test('a preset sends itself', () {
      for (final MapEntry(key: accent, value: preset)
          in accentPresets.entries) {
        expect(watchAccent(accent, null), preset, reason: accent.name);
      }
    });

    // dynamic_color seeds the phone's scheme with the palette's primary, so
    // the same seed gives the watch the phone's primary palette.
    test('System sends the seed of the phone scheme', () {
      final palette = schemes(
        const Color(0xFFB3261E),
        DynamicSchemeVariant.tonalSpot,
      );
      final accent = watchAccent(AccentSource.system, palette)!;
      expect(accent.variant, DynamicSchemeVariant.tonalSpot);
      expect(
        ColorScheme.fromSeed(seedColor: accent.seed).primary,
        palette.light.primary,
      );
    });
  });

  group('watchTheme', () {
    test('the phone source sends the phone accent', () {
      expect(watchTheme(const WatchAppearance(), AccentSource.purple, null), (
        accent: accentPresets[AccentSource.purple],
        face: false,
      ));
    });

    test('the face source still sends the phone accent to fall back on', () {
      expect(
        watchTheme(
          const WatchAppearance(source: WatchThemeSource.face),
          AccentSource.purple,
          null,
        ),
        (accent: accentPresets[AccentSource.purple], face: true),
      );
    });

    test('the preset source sends the preset, whatever the phone wears', () {
      expect(
        watchTheme(
          const WatchAppearance(
            source: WatchThemeSource.preset,
            preset: AccentSource.orange,
          ),
          AccentSource.purple,
          null,
        ),
        (accent: accentPresets[AccentSource.orange], face: false),
      );
      expect(
        watchTheme(
          const WatchAppearance(source: WatchThemeSource.preset),
          AccentSource.purple,
          null,
        ),
        (accent: null, face: false),
        reason: 'the green preset is what the watch draws untold',
      );
    });
  });
}
