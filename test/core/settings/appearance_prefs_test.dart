import 'package:bambuddy_mobile/core/settings/appearance_prefs.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('every accent and mode survives a round trip', () {
    for (final accent in AccentSource.values) {
      for (final mode in ThemeMode.values) {
        final prefs = AppearancePrefs(accent: accent, mode: mode);
        expect(AppearancePrefs.fromJson(prefs.toJson()), prefs);
      }
    }
  });

  // The defaults are the look the app had before the choice existed, so an
  // install upgrading from an older version sees no change.
  test('nothing stored reads as the green accent following the system', () {
    expect(
      AppearancePrefs.fromJson(const {}),
      const AppearancePrefs(
        accent: AccentSource.bambuddy,
        mode: ThemeMode.system,
      ),
    );
  });

  test('a damaged field costs that field, not the other', () {
    expect(
      AppearancePrefs.fromJson({'accent': 'teal', 'mode': 'dark'}),
      const AppearancePrefs(mode: ThemeMode.dark),
    );
    expect(
      AppearancePrefs.fromJson({'accent': 'orange', 'mode': 3}),
      const AppearancePrefs(accent: AccentSource.orange),
    );
    expect(
      AppearancePrefs.fromJson({
        'accent': null,
        'mode': ['dark'],
      }),
      const AppearancePrefs(),
    );
  });

  test('fields it does not know are ignored', () {
    expect(
      AppearancePrefs.fromJson({'accent': 'pink', 'mode': 'light', 'font': 2}),
      const AppearancePrefs(accent: AccentSource.pink, mode: ThemeMode.light),
    );
  });

  group('SettingsRepository', () {
    Future<SettingsRepository> repo(Map<String, Object> stored) async {
      SharedPreferences.setMockInitialValues(stored);
      return SettingsRepository(await SharedPreferences.getInstance());
    }

    test('saves and loads the choice', () async {
      final r = await repo({});
      const prefs = AppearancePrefs(
        accent: AccentSource.graphite,
        mode: ThemeMode.dark,
      );

      await r.saveAppearancePrefs(prefs);

      expect(r.loadAppearancePrefs(), prefs);
    });

    test('nothing stored reads as the defaults', () async {
      expect((await repo({})).loadAppearancePrefs(), const AppearancePrefs());
    });

    test(
      'a value that is not JSON, or not an object, reads as the defaults',
      () async {
        for (final raw in ['{oops', '"dark"', '[1, 2]', '']) {
          final r = await repo({'appearance_prefs': raw});
          expect(r.loadAppearancePrefs(), const AppearancePrefs(), reason: raw);
        }
      },
    );
  });

  group('WatchAppearance', () {
    test('round-trips', () {
      const value = WatchAppearance(
        source: WatchThemeSource.preset,
        preset: AccentSource.pink,
      );
      expect(WatchAppearance.fromJson(value.toJson()), value);
    });

    test('unknown or missing fields read as the phone theme and green', () {
      expect(
        WatchAppearance.fromJson({'source': 'moon', 'preset': 7}),
        const WatchAppearance(),
      );
      expect(WatchAppearance.fromJson({}), const WatchAppearance());
    });

    // "System" is the face switch's job; as a preset it would mean nothing.
    test('a System preset reads as green', () {
      expect(
        WatchAppearance.fromJson({'source': 'preset', 'preset': 'system'}),
        const WatchAppearance(source: WatchThemeSource.preset),
      );
    });
  });
}
