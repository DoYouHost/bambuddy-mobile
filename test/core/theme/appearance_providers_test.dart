import 'package:bambuddy_mobile/core/settings/appearance_prefs.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/core/theme/appearance_providers.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CountingRepository extends SettingsRepository {
  _CountingRepository(super.prefs);

  var saves = 0;

  @override
  Future<void> saveAppearancePrefs(AppearancePrefs prefs) {
    saves++;
    return super.saveAppearancePrefs(prefs);
  }
}

void main() {
  late _CountingRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = _CountingRepository(await SharedPreferences.getInstance());
  });

  SystemSchemes schemesOf(Color seed) => (
    light: ColorScheme.fromSeed(seedColor: seed),
    dark: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
  );

  test('a choice is stored and survives a new scope', () async {
    final first = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(first.dispose);
    const choice = AppearancePrefs(
      accent: AccentSource.purple,
      mode: ThemeMode.dark,
    );

    await first.read(appearanceProvider.notifier).set(choice);

    final second = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(second.dispose);
    expect(second.read(appearanceProvider), choice);
  });

  test('choosing what is already chosen writes nothing', () async {
    final c = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
    const choice = AppearancePrefs(accent: AccentSource.orange);

    await c.read(appearanceProvider.notifier).set(choice);
    await c.read(appearanceProvider.notifier).set(choice);
    await c
        .read(appearanceProvider.notifier)
        .set(const AppearancePrefs(accent: AccentSource.orange));

    expect(repo.saves, 1);
  });

  test('the brand follows the accent', () async {
    final c = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
    expect(c.read(appBrandProvider), bambuddyBrand);

    await c
        .read(appearanceProvider.notifier)
        .set(const AppearancePrefs(accent: AccentSource.blue));

    expect(c.read(appBrandProvider), isNot(bambuddyBrand));
  });

  testWidgets('the palette read before runApp is the first value, and a '
      'resume reads it again', (tester) async {
    final initial = schemesOf(const Color(0xFF2E7DD7));
    final later = schemesOf(const Color(0xFFD72E7D));
    var reads = 0;
    final c = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repo),
        initialSystemSchemesProvider.overrideWithValue(initial),
        systemSchemesReaderProvider.overrideWithValue(() async {
          reads++;
          return later;
        }),
      ],
    );
    addTearDown(c.dispose);

    expect(c.read(systemSchemesProvider), initial);
    expect(reads, 0);

    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();

    expect(reads, 1);
    expect(c.read(systemSchemesProvider), later);
  });

  // No plugin answers in a host test, which is what a platform without
  // dynamic colour looks like; main() must not stop on it.
  test('a platform that cannot answer has no palette', () async {
    expect(await readSystemSchemes(), isNull);
  });
}
