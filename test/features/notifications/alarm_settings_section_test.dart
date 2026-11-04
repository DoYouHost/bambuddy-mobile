import 'package:bambuddy_mobile/core/notifications/notification_prefs.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/features/notifications/alarm_settings_section.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

void main() {
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    AlarmPrefs alarm = AlarmPrefs.defaults,
    double textScale = 1,
  }) async {
    useLogicalWindow(tester, const Size(360, 2400));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    await container.read(notificationPrefsProvider.notifier).setAlarm(alarm);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: plApp(
          const Scaffold(
            body: SingleChildScrollView(child: AlarmSettingsSection()),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  AlarmPrefs stored(ProviderContainer c) =>
      c.read(settingsRepositoryProvider).loadNotificationPrefs().alarm;

  testWidgets('off by default, and everything under it greyed out', (
    tester,
  ) async {
    await pump(tester);
    final switches = tester.widgetList<SettingsSwitchRow>(
      find.byType(SettingsSwitchRow),
    );
    expect(switches.first.value, isFalse);
    expect(switches.skip(1).every((s) => s.onChanged == null), isTrue);
    expect(
      tester.widget<SettingsSlider>(find.byType(SettingsSlider)).enabled,
      isFalse,
    );
  });

  testWidgets('the main switch is stored', (tester) async {
    final c = await pump(tester);
    await tester.tap(find.text(pl.alarmTitle));
    await tester.pumpAndSettle();
    expect(stored(c).enabled, isTrue);
  });

  testWidgets('an event switch clears only its own event', (tester) async {
    final c = await pump(tester, alarm: const AlarmPrefs(enabled: true));
    await tester.tap(find.text(pl.alarmEvtDrying));
    await tester.pumpAndSettle();
    expect(stored(c).events, {
      AlarmEvent.printFinished,
      AlarmEvent.printBlocked,
    });
  });

  testWidgets('the hours are greyed out while the window is off', (
    tester,
  ) async {
    await pump(
      tester,
      alarm: const AlarmPrefs(enabled: true, windowEnabled: false),
    );
    await tester.tap(find.text(pl.alarmWindowFrom));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsNothing);
  });

  testWidgets('a picked hour is stored as minutes after midnight', (
    tester,
  ) async {
    final c = await pump(tester, alarm: const AlarmPrefs(enabled: true));
    expect(find.text('22:00'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
    await tester.tap(find.text(pl.alarmWindowTo));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    final material = MaterialLocalizations.of(
      tester.element(find.byType(TimePickerDialog)),
    );
    // The dial cannot be aimed at reliably; the typed entry mode can.
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '5');
    await tester.enterText(find.byType(TextField).last, '30');
    await tester.tap(find.text(material.okButtonLabel));
    await tester.pumpAndSettle();
    expect(stored(c).windowEnd, 5 * 60 + 30);
    expect(find.text('05:30'), findsOneWidget);
  });

  testWidgets('the slider moves over uneven stops', (tester) async {
    final c = await pump(tester, alarm: const AlarmPrefs(enabled: true));
    expect(find.text(pl.alarmRingFor(10)), findsOneWidget);
    final slider = tester.widget<SettingsSlider>(find.byType(SettingsSlider));
    expect(slider.max, AlarmPrefs.ringMinuteSteps.length - 1);
    slider.onChanged(AlarmPrefs.ringMinuteSteps.indexOf(30));
    await tester.pumpAndSettle();
    expect(stored(c).ringMinutes, 30);
    expect(find.text(pl.alarmRingFor(30)), findsOneWidget);
  });

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('lays out without overflow at text scale $scale', (
      tester,
    ) async {
      await pump(
        tester,
        alarm: const AlarmPrefs(enabled: true),
        textScale: scale,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
