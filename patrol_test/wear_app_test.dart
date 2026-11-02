import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/wear/main_wear.dart' as wear;
import 'package:bambuddy_mobile/wear/wear_ongoing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import '../test/wear/wear_tap_targets.dart';

/// The watch app on a real Wear OS, end to end: what a widget test cannot reach
/// — the system's own back-to-home swipe, the home button, the permission
/// dialog, and whether the system really holds an Ongoing Activity (Play's
/// WO-V4) while the app is away.
///
/// Every test starts on a cleared app (`clearPackageData`), so each one goes
/// through the setup screen into demo, where X1 Carbon is always printing.
///
/// Run on both watch AVDs; dumpsys and the back gesture differ between them:
///   patrol test -t patrol_test/wear_app_test.dart --flavor wear -d SERIAL

/// The emulator images run in English.
final en = lookupAppLocalizations(const Locale('en'));

const _ongoing = WearOngoing();

/// Neither the spinner nor the 5 s poll ever lets the tree settle.
const _config = PatrolTesterConfig(settlePolicy: SettlePolicy.trySettle);

/// Demo printer names are server data, not copy.
const _printing = 'X1 Carbon';

Future<void> _startDemo(PatrolIntegrationTester $) async {
  await wear.main();
  // The last button on the setup screen, below the edge of a round face.
  await $(en.wearSetupDemo).scrollTo().tap();
  // A running print is what asks for the notification permission.
  await $.platform.mobile.tap(
    const AndroidSelector(text: 'Allow'),
    timeout: const Duration(seconds: 15),
  );
  await $(_printing).waitUntilVisible();
}

/// Polls what the system holds until it matches [on].
Future<void> _expectOngoing(bool on, String when) async {
  late ({bool foreground, bool ongoingActivity}) status;
  for (var i = 0; i < 30; i++) {
    status = await _ongoing.status();
    if (status.foreground == on && status.ongoingActivity == on) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail(
    '$when: expected foreground=$on ongoingActivity=$on, '
    'got foreground=${status.foreground} '
    'ongoingActivity=${status.ongoingActivity}',
  );
}

Future<void> _comeBack(PatrolIntegrationTester $, String how) async {
  await $.platform.mobile.openApp();
  await $(_printing).waitUntilVisible();
  await _expectOngoing(false, '$how, back in the app');
}

void main() {
  patrolTest(
    'setup types nothing, and offers no install without a phone (WO-P6)',
    config: _config,
    ($) async {
      await wear.main();
      await $(en.wearSetupDemo).scrollTo();
      // The phone-app check answers asynchronously; give it time to land.
      await Future<void>.delayed(const Duration(seconds: 3));
      await $.pump();
      expect(find.byType(TextField, skipOffstage: false), findsNothing);
      // No paired phone on the emulator: nothing to install on.
      expect(
        find.text(en.wearPhoneAppInstall, skipOffstage: false),
        findsNothing,
      );
    },
  );

  patrolTest('demo from a fresh install shows the fleet', config: _config, (
    $,
  ) async {
    await _startDemo($);
    expect($(en.widgetStatusPrinting), findsWidgets);
    await _expectOngoing(false, 'on screen');
  });

  patrolTest(
    'the control screen pauses, resumes and asks before stopping',
    config: _config,
    ($) async {
      await _startDemo($);
      await $(_printing).tap();

      await $(en.ctrlPause).scrollTo().tap();
      await $(en.ctrlResume).scrollTo();
      await $(en.ctrlResume).tap();
      await $(en.ctrlPause).scrollTo();

      await $(en.ctrlStop).scrollTo().tap();
      await $(en.ctrlStopConfirmTitle).waitUntilVisible();
      await $(find.byTooltip(en.cancel)).tap();
      await $(en.ctrlPause).scrollTo();
    },
  );

  patrolTest('settings name the server and leave demo', config: _config, (
    $,
  ) async {
    await _startDemo($);
    await $(en.wearSettingsTitle).scrollTo().tap();
    await $(en.wearCurrentServer).waitUntilVisible();

    await $(en.changeServer).scrollTo().tap();
    await $(find.byTooltip(en.wearConfirm)).tap();
    await $(en.wearSetupDemo).scrollTo();
  });

  patrolTest(
    'every touch target is at least 48 dp where it rests (WO-V2)',
    config: _config,
    ($) async {
      final semantics = $.tester.ensureSemantics();
      await _startDemo($);
      await expectTapTargetsWhereTheyRest($.tester);

      // The check leaves the list at its last row.
      await $(_printing).scrollTo(scrollDirection: AxisDirection.up).tap();
      await $(en.ctrlPause).scrollTo();
      await expectTapTargetsWhereTheyRest($.tester);

      await $.platform.android.pressBack();
      await $(en.wearSettingsTitle).scrollTo().tap();
      await $(en.wearCurrentServer).waitUntilVisible();
      await expectTapTargetsWhereTheyRest($.tester);
      semantics.dispose();
    },
  );

  patrolTest(
    'leaving mid-print keeps the print on the watch face',
    config: _config,
    ($) async {
      await _startDemo($);

      await $.platform.mobile.pressHome();
      await _expectOngoing(true, 'home button');
      await _comeBack($, 'home button');

      await $.platform.android.pressBack();
      await _expectOngoing(true, 'back on the root screen');
      await _comeBack($, 'back on the root screen');

      // Wear OS ends the activity itself on this one, without asking Flutter;
      // the poll behind the face survives only because the engine does. This
      // test running on past it is part of the check.
      await $.platform.mobile.swipe(
        from: const Offset(0.02, 0.5),
        to: const Offset(0.9, 0.5),
      );
      await _expectOngoing(true, 'swipe on the root screen');
      await Future<void>.delayed(const Duration(seconds: 5));
      await _expectOngoing(true, 'swipe on the root screen, 5 s later');
      await _comeBack($, 'swipe on the root screen');
    },
  );

  patrolTest(
    'a swipe on an inner screen goes back inside the app',
    config: _config,
    ($) async {
      await _startDemo($);
      await $(_printing).tap();
      await $(en.ctrlPause).scrollTo();

      await $.platform.mobile.swipe(
        from: const Offset(0.02, 0.5),
        to: const Offset(0.9, 0.5),
      );
      await $(en.wearSettingsTitle).scrollTo();
      await _expectOngoing(false, 'swipe on an inner screen');
    },
  );
}
