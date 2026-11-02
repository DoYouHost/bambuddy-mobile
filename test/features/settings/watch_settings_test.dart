import 'package:bambuddy_mobile/core/settings/appearance_prefs.dart';
import 'package:bambuddy_mobile/features/settings/watch_settings.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/core/theme/app_brand.dart';
import 'package:bambuddy_mobile/core/theme/appearance_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

void main() {
  Future<ProviderContainer> pumpScreen(
    WidgetTester tester, {
    Map<String, Object> stored = const {},
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context, listen: false);
            return plApp(const Scaffold(body: WatchSettings()));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  bool switchOn(WidgetTester tester, String id) => tester
      .widget<Switch>(
        find.descendant(of: byLogId(id), matching: find.byType(Switch)),
      )
      .value;

  WatchThemeSource stored(ProviderContainer c) =>
      c.read(settingsRepositoryProvider).loadWatchAppearance().source;

  testWidgets('starts on the phone theme, with no presets on offer', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(switchOn(tester, 'watch_settings.from_phone'), isTrue);
    expect(switchOn(tester, 'watch_settings.from_face'), isFalse);
    expect(byLogId('watch_settings.accent'), findsNothing);
  });

  testWidgets('the face switch turns the phone switch off', (tester) async {
    final container = await pumpScreen(tester);

    await tester.tap(byLogId('watch_settings.from_face'));
    await tester.pumpAndSettle();

    expect(switchOn(tester, 'watch_settings.from_face'), isTrue);
    expect(switchOn(tester, 'watch_settings.from_phone'), isFalse);
    expect(stored(container), WatchThemeSource.face);
    expect(container.read(watchThemeProvider).face, isTrue);
  });

  testWidgets('both off offers the presets, and a pick is what is sent', (
    tester,
  ) async {
    final container = await pumpScreen(tester);

    await tester.tap(byLogId('watch_settings.from_phone'));
    await tester.pumpAndSettle();
    expect(stored(container), WatchThemeSource.preset);

    await tester.tap(byLogId('watch_settings.accent'));
    await tester.pumpAndSettle();
    expect(
      byLogId('watch_settings.accent.blue'),
      findsWidgets,
      reason: 'the presets are listed',
    );
    expect(find.text(pl.appearanceAccentSystem), findsNothing);
    await tester.tap(byLogId('watch_settings.accent.orange').last);
    await tester.pumpAndSettle();

    expect(
      container.read(settingsRepositoryProvider).loadWatchAppearance().preset,
      AccentSource.orange,
    );
    expect(container.read(watchThemeProvider), (
      accent: accentPresets[AccentSource.orange],
      face: false,
    ));
  });

  testWidgets('a source switched back on hides the presets again', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      stored: {'watch_appearance': '{"source":"preset","preset":"pink"}'},
    );
    expect(find.text(pl.appearanceAccentPink), findsOneWidget);

    await tester.tap(byLogId('watch_settings.from_phone'));
    await tester.pumpAndSettle();

    expect(byLogId('watch_settings.accent'), findsNothing);
  });
}
