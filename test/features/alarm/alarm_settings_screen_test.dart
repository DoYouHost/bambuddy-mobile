import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/notifications/notification_prefs.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/features/alarm/alarm_settings_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

class _Printers extends PrintersRepository {
  _Printers(this.printers) : super(Dio());

  final List<Printer> printers;

  @override
  Future<List<Printer>> fetchPrinters() async => printers;
}

const _fleet = [
  Printer(id: 1, name: 'X1C', location: 'Garage'),
  Printer(id: 2, name: 'P1S', location: 'Garage'),
  Printer(id: 3, name: 'A1', location: 'Office'),
  Printer(id: 4, name: 'H2D'),
];

/// A section header by the text it was given; it draws it upper-cased.
Finder _header(String text) =>
    find.byWidgetPredicate((w) => w is SettingsSectionHeader && w.text == text);

void main() {
  const channel = MethodChannel('page.codeberg.morganmlgman.bambuddy/alarm');
  late List<MethodCall> native;

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    AlarmPrefs alarm = AlarmPrefs.defaults,
    double textScale = 1,
    bool canFullScreen = true,
    bool rings = true,
    List<Printer> printers = _fleet,
  }) async {
    native = [];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      native.add(call);
      return switch (call.method) {
        'canFullScreen' => canFullScreen,
        'ring' => rings ? 'player' : null,
        _ => null,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    // Tall enough for every row: a ListView builds only what is on screen.
    useLogicalWindow(tester, const Size(360, 4200));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        printersRepositoryProvider.overrideWithValue(_Printers(printers)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(notificationPrefsProvider.notifier).setAlarm(alarm);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: plApp(
          const AlarmSettingsScreen(),
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
    for (final row in [pl.alarmWindowFrom, pl.alarmWindowTo]) {
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsNothing, reason: row);
    }
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

  group('full-screen permission', () {
    testWidgets('missing: a note and a button to the system page', (
      tester,
    ) async {
      await pump(
        tester,
        alarm: const AlarmPrefs(enabled: true),
        canFullScreen: false,
      );
      expect(find.text(pl.alarmFullScreenNeeded), findsOneWidget);
      await tester.tap(find.text(pl.alarmFullScreenAllow));
      await tester.pump();
      expect(native.map((c) => c.method), contains('openFullScreenSettings'));
    });

    testWidgets('granted: no note', (tester) async {
      await pump(tester, alarm: const AlarmPrefs(enabled: true));
      expect(find.text(pl.alarmFullScreenNeeded), findsNothing);
    });

    testWidgets('missing but the alarm off: nothing to nag about', (
      tester,
    ) async {
      await pump(tester, canFullScreen: false);
      expect(find.text(pl.alarmFullScreenNeeded), findsNothing);
    });

    testWidgets('asked again when the app comes back', (tester) async {
      await pump(
        tester,
        alarm: const AlarmPrefs(enabled: true),
        canFullScreen: false,
      );
      final before = native.where((c) => c.method == 'canFullScreen').length;
      // The order Android walks through; the listener asserts it.
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(
        native.where((c) => c.method == 'canFullScreen').length,
        before + 1,
      );
    });
  });

  group('test alarm', () {
    testWidgets('rings for one minute with the localized labels', (
      tester,
    ) async {
      await pump(
        tester,
        alarm: const AlarmPrefs(enabled: true, ringMinutes: 30),
      );
      await tester.tap(find.text(pl.alarmTest));
      await tester.pump();
      final ring = native.singleWhere((c) => c.method == 'ring');
      expect(ring.arguments, {
        'id': alarmTestId,
        'title': pl.alarmTest,
        'body': pl.alarmTestBody,
        'stop': pl.alarmStop,
        'minutes': 1,
        'printer': '',
      });
    });

    testWidgets('says so when nothing rang', (tester) async {
      await pump(tester, alarm: const AlarmPrefs(enabled: true), rings: false);
      await tester.tap(find.text(pl.alarmTest));
      await tester.pump();
      expect(find.text(pl.alarmTestFailed), findsOneWidget);
    });

    testWidgets('disabled while the alarm is off', (tester) async {
      await pump(tester);
      await tester.tap(find.text(pl.alarmTest));
      await tester.pump();
      expect(native.where((c) => c.method == 'ring'), isEmpty);
    });
  });

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('lays out without overflow at text scale $scale', (
      tester,
    ) async {
      // The permission note is the widest row the section can show.
      await pump(
        tester,
        alarm: const AlarmPrefs(enabled: true),
        textScale: scale,
        canFullScreen: false,
      );
      expect(find.text(pl.alarmFullScreenNeeded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  group('exclusions', () {
    testWidgets('lists each location once and every printer', (tester) async {
      await pump(tester, alarm: const AlarmPrefs(enabled: true));
      expect(_header(pl.alarmExcludedLocationsHeader), findsOneWidget);
      expect(find.text('Garage'), findsOneWidget);
      expect(find.text('Office'), findsOneWidget);
      for (final p in _fleet) {
        expect(find.text(p.name), findsOneWidget);
      }
    });

    testWidgets('no location among the printers: no location card', (
      tester,
    ) async {
      await pump(
        tester,
        alarm: const AlarmPrefs(enabled: true),
        printers: const [Printer(id: 4, name: 'H2D')],
      );
      expect(_header(pl.alarmExcludedLocationsHeader), findsNothing);
      expect(_header(pl.alarmExcludedPrintersHeader), findsOneWidget);
    });

    testWidgets('a printer switch stores its id', (tester) async {
      final c = await pump(tester, alarm: const AlarmPrefs(enabled: true));
      await tester.tap(find.text('H2D'));
      await tester.pumpAndSettle();
      expect(stored(c).excludedPrinters, {4});
      await tester.tap(find.text('H2D'));
      await tester.pumpAndSettle();
      expect(stored(c).excludedPrinters, isEmpty);
    });

    testWidgets('a location switch stores its name', (tester) async {
      final c = await pump(tester, alarm: const AlarmPrefs(enabled: true));
      await tester.tap(find.text('Garage'));
      await tester.pumpAndSettle();
      expect(stored(c).excludedLocations, {'Garage'});
    });

    testWidgets(
      'printers in an excluded location read as excluded and locked',
      (tester) async {
        await pump(
          tester,
          alarm: const AlarmPrefs(enabled: true, excludedLocations: {'Garage'}),
        );
        SettingsSwitchRow row(String name) => tester.widget(
          find.ancestor(
            of: find.text(name),
            matching: find.byType(SettingsSwitchRow),
          ),
        );
        expect(row('X1C').value, isTrue);
        expect(row('X1C').onChanged, isNull);
        expect(row('X1C').subtitle, pl.alarmExcludedWithLocation('Garage'));
        expect(row('A1').value, isFalse);
        expect(row('A1').onChanged, isNotNull);
      },
    );

    testWidgets('greyed out while the alarm is off', (tester) async {
      final c = await pump(tester);
      await tester.tap(find.text('H2D'));
      await tester.pumpAndSettle();
      expect(stored(c).excludedPrinters, isEmpty);
    });
  });
}
