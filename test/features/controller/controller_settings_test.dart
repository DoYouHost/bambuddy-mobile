import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/settings/controller_prefs.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_providers.dart';
import 'package:bambuddy_mobile/features/controller/controller_saver.dart';
import 'package:bambuddy_mobile/features/controller/controller_settings.dart';
import 'package:bambuddy_mobile/features/controller/scale_to_fit.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

void main() {
  setUpAll(loadAppFonts);

  late SharedPreferences sp;

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(844, 390),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    sp = await SharedPreferences.getInstance();
    await pumpPhone(
      tester,
      const ControllerSaverHost(
        printerId: 1,
        child: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: ScaleToFit(child: ControllerSettings()),
          ),
        ),
      ),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        noServerProfileOverride,
        fixedDashboardOverride(
          const DashboardState(
            printers: [
              PrinterWithStatus(
                printer: Printer(id: 1, name: 'X1C'),
                status: PrinterStatus(id: 1, connected: true, state: 'IDLE'),
              ),
            ],
          ),
        ),
        inertStatusesOverride,
      ],
    );
    await tester.pump();
  }

  ControllerPrefs prefs(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(ControllerSettings)),
  ).read(controllerPrefsProvider);

  /// What the next start of the app would read.
  ControllerPrefs stored(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(ControllerSettings)),
  ).read(settingsRepositoryProvider).loadControllerPrefs();

  Future<void> tapChoice(WidgetTester tester, int index) async {
    await tester.tap(byLogId('controller.saver_after').at(index));
    await settle(tester);
  }

  group('the saver\'s idle time', () {
    testWidgets('a time is stored at once', (tester) async {
      await pump(tester);

      await tapChoice(tester, ControllerPrefs.saverAfterOptions.indexOf(10));

      expect(prefs(tester).saverAfterMinutes, 10);
      expect(stored(tester).saverAfterMinutes, 10);
    });

    testWidgets('Never asks about burn-in first and keeps the old time when '
        'refused', (tester) async {
      await pump(tester);
      final before = prefs(tester).saverAfterMinutes;

      await tapChoice(tester, ControllerPrefs.saverAfterOptions.length - 1);
      expect(find.text(pl.controllerSaverNeverBody), findsOneWidget);
      await tester.tap(byLogId('controller.saver_never.cancel'));
      await settle(tester);

      expect(prefs(tester).saverAfterMinutes, before);
      expect(stored(tester).saverAfterMinutes, before);
    });

    testWidgets('Never is stored once the risk is accepted', (tester) async {
      await pump(tester);

      await tapChoice(tester, ControllerPrefs.saverAfterOptions.length - 1);
      await tester.tap(byLogId('controller.saver_never.confirm'));
      await settle(tester);

      expect(prefs(tester).saverAfterMinutes, ControllerPrefs.saverNever);
      expect(stored(tester).saverAfter, isNull);
    });
  });

  testWidgets('Never, once accepted, asks nothing when tapped again', (
    tester,
  ) async {
    await pump(tester);
    final never = ControllerPrefs.saverAfterOptions.length - 1;
    await tapChoice(tester, never);
    await tester.tap(byLogId('controller.saver_never.confirm'));
    await settle(tester);

    await tapChoice(tester, never);

    expect(find.text(pl.controllerSaverNeverBody), findsNothing);
  });

  group('without the screen always on', () {
    Future<void> screenNotHeld(WidgetTester tester) async {
      await pump(tester);
      if (prefs(tester).keepAwake) {
        await tester.tap(byLogId('controller.keep_awake'));
        await tester.pump();
      }
    }

    testWidgets('the saver\'s settings are locked and say why', (tester) async {
      await screenNotHeld(tester);
      final before = prefs(tester).saverAfterMinutes;

      expect(find.text(pl.controllerSaverNeedsAwake), findsOneWidget);
      await tapChoice(tester, ControllerPrefs.saverAfterOptions.indexOf(10));
      await tester.tap(byLogId('controller.saver_preview'));
      await tester.pump();

      expect(prefs(tester).saverAfterMinutes, before);
      expect(find.byType(ControllerSaver), findsNothing);
    });

    testWidgets('turning it back on unlocks them', (tester) async {
      await screenNotHeld(tester);
      await tester.tap(byLogId('controller.keep_awake'));
      await tester.pump();

      expect(find.text(pl.controllerSaverNeedsAwake), findsNothing);
      await tapChoice(tester, ControllerPrefs.saverAfterOptions.indexOf(10));
      expect(prefs(tester).saverAfterMinutes, 10);
    });
  });

  group('the switches', () {
    testWidgets('each one flips its own setting', (tester) async {
      await pump(tester);
      final before = prefs(tester);

      for (final id in [
        'controller.wake_on_warnings',
        'controller.keep_awake',
        'controller.live_camera',
      ]) {
        await tester.tap(byLogId(id));
        await tester.pump();
      }

      final after = stored(tester);
      expect(after.wakeOnWarnings, !before.wakeOnWarnings);
      expect(after.keepAwake, !before.keepAwake);
      expect(after.liveCamera, !before.liveCamera);
    });
  });

  group('brightness', () {
    testWidgets('moves in steps between its bounds', (tester) async {
      await pump(tester);

      await tester.drag(
        byLogId('controller.saver_brightness'),
        const Offset(2000, 0),
      );
      await tester.pump();
      expect(
        stored(tester).saverBrightness,
        ControllerPrefs.maxSaverBrightness,
      );

      await tester.drag(
        byLogId('controller.saver_brightness'),
        const Offset(-2000, 0),
      );
      await tester.pump();
      expect(
        stored(tester).saverBrightness,
        ControllerPrefs.minSaverBrightness,
      );
    });
  });

  testWidgets('Preview puts the saver up now', (tester) async {
    await pump(tester);

    await tester.tap(byLogId('controller.saver_preview'));
    await tester.pump();

    expect(find.byType(ControllerSaver), findsOneWidget);
  });

  group('the layout', () {
    for (final size in const [
      Size(844, 390),
      Size(740, 320),
      Size(1280, 800),
    ]) {
      testWidgets('fits ${size.width.round()}x${size.height.round()}', (
        tester,
      ) async {
        await pump(tester, size: size);

        expect(tester.takeException(), isNull);
      });
    }
  });
}
