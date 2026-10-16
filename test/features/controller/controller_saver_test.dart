import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_saver.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

const _room = Size(800, 400);
const _box = Size(300, 150);

void main() {
  group('the bounce', () {
    Bounce at(Offset p, Offset v) => (position: p, velocity: v, hue: 100);

    test('moves with its velocity and keeps its hue in open space', () {
      final next = bounceStep(
        at(const Offset(100, 100), const Offset(50, 20)),
        const Duration(seconds: 1),
        _room,
        _box,
      );

      expect(next.position, const Offset(150, 120));
      expect(next.hue, 100);
    });

    test('turns back at a side and shifts its hue by a quarter', () {
      final next = bounceStep(
        at(const Offset(495, 100), const Offset(50, 0)),
        const Duration(seconds: 1),
        _room,
        _box,
      );

      expect(next.position.dx, 500, reason: 'stopped at the wall');
      expect(next.velocity.dx, -50);
      expect(next.hue, 190);
    });

    test('turns back at the top and shifts its hue by a sixth', () {
      final next = bounceStep(
        at(const Offset(100, 5), const Offset(0, -20)),
        const Duration(seconds: 1),
        _room,
        _box,
      );

      expect(next.position.dy, 0);
      expect(next.velocity.dy, 20);
      expect(next.hue, 160);
    });

    test('a corner turns both ways and shifts the hue by both', () {
      final next = bounceStep(
        at(const Offset(495, 245), const Offset(50, 50)),
        const Duration(seconds: 1),
        _room,
        _box,
      );

      expect(next.velocity, const Offset(-50, -50));
      expect(next.hue, (100 + 90 + 60) % 360);
    });
  });

  group('the saver', () {
    late int taps;

    Future<void> pump(
      WidgetTester tester, {
      int minutes = 1,
      bool keepAwake = true,
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(844, 390);
      addTearDown(tester.view.reset);
      taps = 0;
      SharedPreferences.setMockInitialValues({
        'controller_prefs':
            '{"saver_after_minutes":$minutes,"keep_awake":$keepAwake}',
      });
      final sp = await SharedPreferences.getInstance();
      await pumpPhone(
        tester,
        ControllerSaverHost(
          printerId: 1,
          child: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  TextButton(
                    onPressed: () => taps++,
                    child: const Text('press'),
                  ),
                  TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => AlertDialog(
                        content: TextButton(
                          onPressed: () => taps++,
                          child: const Text('in dialog'),
                        ),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ],
              ),
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

    Finder saver() => find.byType(ControllerSaver);

    testWidgets('comes up once the screen has been left alone long enough', (
      tester,
    ) async {
      await pump(tester);

      await tester.pump(const Duration(seconds: 59));
      expect(saver(), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(saver(), findsOneWidget);
    });

    testWidgets('the first touch only wakes the screen', (tester) async {
      await pump(tester);
      await tester.pump(const Duration(minutes: 1, seconds: 1));

      await tester.tap(find.text('press'), warnIfMissed: false);
      await tester.pump();

      expect(saver(), findsNothing);
      expect(taps, 0, reason: 'the control under the saver was not pressed');
    });

    testWidgets('a touch restarts the count', (tester) async {
      await pump(tester);
      await tester.pump(const Duration(seconds: 50));

      await tester.tap(find.text('press'));
      await tester.pump(const Duration(seconds: 50));
      expect(saver(), findsNothing, reason: '50 s since the touch');
      expect(taps, 1);

      await tester.pump(const Duration(seconds: 11));
      expect(saver(), findsOneWidget);
    });

    testWidgets('comes back after waking if nobody touches it', (tester) async {
      await pump(tester);
      await tester.pump(const Duration(minutes: 1, seconds: 1));
      await tester.tap(find.text('press'), warnIfMissed: false);
      await tester.pump();
      expect(saver(), findsNothing);

      await tester.pump(const Duration(minutes: 1, seconds: 1));
      expect(saver(), findsOneWidget);
    });

    testWidgets('covers an open dialog too', (tester) async {
      await pump(tester);
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(minutes: 1));

      expect(saver(), findsOneWidget);
      await tester.tap(find.text('in dialog'), warnIfMissed: false);
      await tester.pump();
      expect(taps, 0, reason: 'the dialog under the saver was not pressed');
    });

    testWidgets('does not count down while the phone may turn the screen off', (
      tester,
    ) async {
      await pump(tester, keepAwake: false);

      await tester.pump(const Duration(hours: 1));

      expect(saver(), findsNothing);
    });

    testWidgets('never comes up when set to Never', (tester) async {
      await pump(tester, minutes: 0);

      await tester.pump(const Duration(hours: 1));

      expect(saver(), findsNothing);
    });
  });
}
