import 'package:bambuddy_mobile/core/format/duration_format.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_saver.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:bambuddy_mobile/core/settings/controller_prefs.dart';
import 'package:flutter/services.dart';
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

  group('the colour', () {
    test('never leaves green to violet, whatever the turn', () {
      for (var hue = 0.0; hue < 720; hue += 7.5) {
        final c = calmHue(hue);
        expect(c, inInclusiveRange(130, 280), reason: 'hue $hue');
      }
    });

    test('still changes at every wall', () {
      expect(calmHue(100), isNot(calmHue(100 + 90)));
      expect(calmHue(100), isNot(calmHue(100 + 60)));
    });
  });

  group('the saver', () {
    late int taps;

    /// Every backlight level the host asked the window for, in order; null is
    /// "back to the system setting".
    late List<Object?> backlight;

    Future<void> pump(
      WidgetTester tester, {
      int minutes = 1,
      bool keepAwake = true,
      PrinterStatus status = const PrinterStatus(
        id: 1,
        connected: true,
        state: 'IDLE',
      ),
    }) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(844, 390);
      addTearDown(tester.view.reset);
      taps = 0;
      backlight = [];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const window = MethodChannel(
        'page.codeberg.morganmlgman.bambuddy/window',
      );
      messenger.setMockMethodCallHandler(window, (call) async {
        if (call.method == 'screenBrightness') {
          backlight.add((call.arguments as Map)['level']);
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(window, null));
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
            DashboardState(
              printers: [
                PrinterWithStatus(
                  printer: const Printer(id: 1, name: 'X1C'),
                  status: status,
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

    testWidgets('dims the backlight to the setting, and gives it back on '
        'waking', (tester) async {
      await pump(tester);
      await tester.pump(const Duration(minutes: 1, seconds: 1));
      expect(backlight, [ControllerPrefs.defaultSaverBrightness / 100]);

      await tester.tap(find.text('press'), warnIfMissed: false);
      await tester.pump();

      expect(backlight.last, isNull);
    });

    testWidgets('gives the backlight back when the controller closes with the '
        'saver up', (tester) async {
      await pump(tester);
      await tester.pump(const Duration(minutes: 1, seconds: 1));

      await tester.pumpWidget(const SizedBox());

      expect(backlight.last, isNull);
    });

    testWidgets('shows the job\'s progress as the Overview does, in plain '
        'text', (tester) async {
      await pump(
        tester,
        status: const PrinterStatus(
          id: 1,
          connected: true,
          state: 'RUNNING',
          progress: 44.3,
        ),
      );
      await tester.pump(const Duration(minutes: 1, seconds: 1));

      expect(find.text('44%'), findsOneWidget);
      // An overlay entry outside a Material gets Flutter's yellow underlined
      // fallback style.
      final style = tester
          .widget<RichText>(
            find.descendant(
              of: find.text(pl.controllerTouchToWake),
              matching: find.byType(RichText),
            ),
          )
          .text
          .style;
      expect(style?.decoration, isNot(TextDecoration.underline));
    });

    testWidgets('a job shows its progress, layer, time left and finish time', (
      tester,
    ) async {
      await pump(
        tester,
        status: const PrinterStatus(
          id: 1,
          connected: true,
          state: 'RUNNING',
          progress: 44.3,
          layerNum: 116,
          totalLayers: 264,
          remainingTime: 51,
        ),
      );
      await tester.pump(const Duration(minutes: 1, seconds: 1));

      expect(find.text('44%'), findsOneWidget);
      expect(find.text('116/264'), findsOneWidget);
      expect(find.text(pl.remaining(formatMinutes(pl, 51))), findsOneWidget);
      expect(find.textContaining(pl.eta('').trim()), findsOneWidget);
    });

    testWidgets('with nothing printing it shows the printer and its state', (
      tester,
    ) async {
      await pump(tester);
      await tester.pump(const Duration(minutes: 1, seconds: 1));

      expect(
        find.descendant(
          of: find.byType(ControllerSaver),
          matching: find.text('X1C'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ControllerSaver),
          matching: find.textContaining('%'),
        ),
        findsNothing,
        reason: 'no job, no progress',
      );
    });

    testWidgets(
      'the box stays on the screen and in calm colours however long it '
      'travels',
      (tester) async {
        await pump(
          tester,
          status: const PrinterStatus(
            id: 1,
            connected: true,
            state: 'RUNNING',
            progress: 51,
            layerNum: 134,
            totalLayers: 264,
            remainingTime: 45,
          ),
        );
        await tester.pump(const Duration(minutes: 1, seconds: 1));

        final screen = Offset.zero & tester.view.physicalSize;
        final card = find
            .descendant(
              of: find.byType(ControllerSaver),
              matching: find.byType(DecoratedBox),
            )
            .first;
        for (var i = 0; i < 600; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          final rect = tester.getRect(card);
          expect(
            screen.contains(rect.topLeft) &&
                screen.contains(rect.bottomRight - const Offset(0.01, 0.01)),
            isTrue,
            reason: 'frame $i: $rect is outside $screen',
          );
          final border =
              (tester.widget<DecoratedBox>(card).decoration as BoxDecoration)
                  .border!
                  .top
                  .color;
          expect(
            HSVColor.fromColor(border).hue,
            inInclusiveRange(129, 281),
            reason: 'frame $i: a warning colour',
          );
        }
      },
    );

    testWidgets('never comes up when set to Never', (tester) async {
      await pump(tester, minutes: 0);

      await tester.pump(const Duration(hours: 1));

      expect(saver(), findsNothing);
    });
  });
}
