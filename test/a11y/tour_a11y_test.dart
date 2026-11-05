import 'package:bambuddy_mobile/features/tour/tips_screen.dart';
import 'package:bambuddy_mobile/features/tour/tour_beacon.dart';
import 'package:bambuddy_mobile/features/tour/tour_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets for the guided tour and the tips screen:
/// every step of the tour as the user first meets it (card, spotlight scrim and
/// the demo screen underneath, including the wall preview and the open menu and
/// drawer the tour puts up itself), the first step again once its gesture is
/// done and "Next" is offered, and the tips list. The tour runs in its own demo
/// sandbox, so steps are reached the way the app reaches them: the beacon is
/// told what the user did and "Next" is tapped. Screens under the scrim belong
/// to their own features and are measured here only as the tour shows them.
/// Not covered: the real gestures a step asks for (drag, swipe, long press),
/// which `test/features/tour/tour_test.dart` drives.
void main() {
  // The drawer footer reads the app version from the platform.
  setUpAll(
    () => PackageInfo.setMockInitialValues(
      appName: 'bambuddy',
      packageName: 'page.codeberg.morganmlgman.bambuddy_mobile',
      version: '0.17.0',
      buildNumber: '2029000',
      buildSignature: '',
    ),
  );

  a11ySurface(
    'tips',
    demo: false,
    home: () => const TipsScreen(),
    shows: find.text(pl.tipsRunTour),
  );

  for (var i = 0; i < tourSteps.length; i++) {
    a11ySurface(
      'tour, step ${i + 1} (${tourSteps[i].id})',
      demo: false,
      home: _tourLauncher,
      arrange: (tester) async {
        await a11yOpenLauncher(tester, settle: const Duration(seconds: 2));
        await _advanceTo(tester, i);
      },
      shows: find.text(pl.tourStepCounter(i + 1, tourSteps.length)),
    );
  }

  a11ySurface(
    'tour, step 1, gesture done',
    demo: false,
    home: _tourLauncher,
    arrange: (tester) async {
      await a11yOpenLauncher(tester, settle: const Duration(seconds: 2));
      await _signal(tester, tourSteps.first.requires);
    },
    shows: byLogId('tour.next'),
  );
}

/// Tells the tour's beacon the user did [events], as the screens would.
Future<void> _signal(WidgetTester tester, Iterable<String> events) async {
  // The last MaterialApp is the tour's own, which sits under the sandbox's
  // container; the first is the harness's.
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp).last),
  );
  for (final event in events) {
    container.read(tourBeaconProvider)!.signal(event);
  }
  await settle(tester);
}

/// Completes every step before [index] the way the user would and moves on.
Future<void> _advanceTo(WidgetTester tester, int index) async {
  for (var i = 0; i < index; i++) {
    await _signal(tester, tourSteps[i].requires);
    await tester.tap(byLogId('tour.next'));
    await a11ySettle(tester, const Duration(seconds: 1));
  }
}

/// The host sits above the app's navigator in production; here it wraps the one
/// button that opens it.
Widget _tourLauncher() =>
    TourHost(child: A11yLauncher((context) => TourHost.open(context)));
