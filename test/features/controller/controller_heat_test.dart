import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_heat.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dash_kit/dash_kit.dart';
import 'package:bambuddy_mobile/features/controller/scale_to_fit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

const _phone = Size(844, 390);

PrinterStatus _status({
  Map<String, double>? temps,
  String state = 'IDLE',
  int? extruder,
  int? airduct,
}) => PrinterStatus(
  id: 1,
  connected: true,
  state: state,
  activeExtruder: extruder,
  airductMode: airduct,
  coolingFanSpeed: 70,
  bigFan1Speed: 40,
  bigFan2Speed: 0,
  temperatures:
      temps ??
      const {
        'nozzle': 218,
        'nozzle_target': 220,
        'bed': 60,
        'bed_target': 60,
        'chamber': 34,
      },
);

void main() {
  late RecordingCommands commands;

  Future<void> pump(
    WidgetTester tester,
    PrinterStatus status, {
    String model = 'X1C',
    Size size = _phone,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    commands = RecordingCommands();
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    await pumpPhone(
      tester,
      const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(16),
          // Scaled as the screen scales its body.
          child: ScaleToFit(child: ControllerHeat(printerId: 1)),
        ),
      ),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        noServerProfileOverride,
        printerCommandsRepositoryProvider.overrideWithValue(commands),
        fixedDashboardOverride(
          DashboardState(
            printers: [
              PrinterWithStatus(
                printer: Printer(id: 1, name: 'P', model: model),
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

  Future<void> tapStep(WidgetTester tester, String id, {int index = 0}) async {
    await tester.tap(byLogId(id).at(index));
    await tester.pump();
  }

  group('a fan', () {
    testWidgets('reading out of range is shown at the end, not a crash', (
      tester,
    ) async {
      await pump(
        tester,
        const PrinterStatus(
          id: 1,
          connected: true,
          state: 'IDLE',
          coolingFanSpeed: 120,
          temperatures: {'nozzle': 30, 'bed': 25},
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('100%'), findsOneWidget);
    });
  });

  group('the targets', () {
    testWidgets('show each heater with the target it is heading for', (
      tester,
    ) async {
      await pump(tester, _status());

      expect(find.text('218°'), findsOneWidget);
      expect(find.text(pl.controllerTarget('220°')), findsOneWidget);
      expect(find.text('60°'), findsOneWidget);
      expect(find.text(pl.controllerTarget('60°')), findsOneWidget);
    });

    testWidgets('say whether each heater is heating, holding or cooling', (
      tester,
    ) async {
      await pump(
        tester,
        _status(
          temps: const {
            'nozzle': 150,
            'nozzle_target': 220,
            'bed': 60,
            'bed_target': 61,
            'chamber': 34,
          },
        ),
      );

      expect(find.text(pl.controllerHeating), findsOneWidget);
      expect(find.text(pl.controllerAtTarget), findsOneWidget);
      expect(find.text(pl.controllerCooling), findsNothing);
    });

    testWidgets('a heater above its target is cooling, one off says nothing', (
      tester,
    ) async {
      await pump(
        tester,
        _status(
          temps: const {
            'nozzle': 230,
            'nozzle_target': 200,
            'bed': 40,
            'chamber': 34,
          },
        ),
      );

      expect(find.text(pl.controllerCooling), findsOneWidget);
      expect(find.text(pl.controllerHeating), findsNothing);
      expect(find.text(pl.controllerAtTarget), findsNothing);
    });

    testWidgets('plus raises the nozzle by one step', (tester) async {
      await pump(tester, _status());

      await tapStep(tester, 'controller.heat_plus');

      expect(commands.calls, ['nozzle:1:225:0']);
    });

    testWidgets('minus lowers the bed by one step', (tester) async {
      await pump(tester, _status());

      await tapStep(tester, 'controller.heat_minus', index: 1);

      expect(commands.calls, ['bed:1:55']);
    });

    testWidgets('at zero the target reads Off and cannot go lower', (
      tester,
    ) async {
      await pump(
        tester,
        _status(temps: const {'nozzle': 30, 'bed': 25, 'chamber': 20}),
      );

      expect(
        find.descendant(
          of: byLogId('controller.heat_target'),
          matching: find.text(pl.ctrlOff),
        ),
        findsNWidgets(2),
      );
      await tester.tap(byLogId('controller.heat_minus').first);
      await tester.pump();

      expect(commands.calls, isEmpty);
    });

    testWidgets('the ceiling stops plus, and a step never overshoots it', (
      tester,
    ) async {
      await pump(
        tester,
        _status(temps: const {'nozzle': 298, 'nozzle_target': 298, 'bed': 25}),
      );

      await tapStep(tester, 'controller.heat_plus');

      expect(commands.calls, ['nozzle:1:300:0']);
    });

    testWidgets('a target already at the ceiling cannot be raised', (
      tester,
    ) async {
      await pump(
        tester,
        _status(temps: const {'nozzle': 300, 'nozzle_target': 300, 'bed': 25}),
      );

      await tester.tap(byLogId('controller.heat_plus').first);
      await tester.pump();

      expect(commands.calls, isEmpty);
    });
  });

  group('typing a target', () {
    Future<void> openKeypad(WidgetTester tester, {int index = 0}) async {
      await tester.tap(byLogId('controller.heat_target').at(index));
      await settle(tester);
    }

    Future<void> typeDigits(WidgetTester tester, String digits) async {
      for (final digit in digits.split('')) {
        await tester.tap(byLogId('controller.heat_target_key.$digit'));
        await tester.pump();
      }
    }

    Future<void> confirm(WidgetTester tester) async {
      await tester.tap(byLogId('controller.heat_target_set'));
      await settle(tester);
    }

    /// What the target button of the heater at [index] says.
    Finder typedIn(String text, {int index = 0}) => find.descendant(
      of: byLogId('controller.heat_target').at(index),
      matching: find.text(text),
    );

    testWidgets('sets the number that was typed', (tester) async {
      await pump(tester, _status());
      await openKeypad(tester);

      await typeDigits(tester, '230');
      await confirm(tester);

      expect(commands.calls, ['nozzle:1:230:0']);
    });

    testWidgets('holds a number above the ceiling to it', (tester) async {
      await pump(tester, _status());
      await openKeypad(tester);

      await typeDigits(tester, '999');
      await confirm(tester);

      expect(commands.calls, ['nozzle:1:300:0']);
    });

    testWidgets('holds a number to the ceiling of that heater', (tester) async {
      await pump(tester, _status(), model: 'H2D');
      await openKeypad(tester, index: 2);

      await typeDigits(tester, '999');
      await confirm(tester);

      expect(commands.calls, ['chamber:1:60']);
    });

    testWidgets('marks the button that takes the digits while it is open', (
      tester,
    ) async {
      await pump(tester, _status());
      BorderSide? border(int index) => tester
          .widget<OutlinedButton>(
            find.descendant(
              of: byLogId('controller.heat_target').at(index),
              matching: find.byType(OutlinedButton),
            ),
          )
          .style
          ?.side
          ?.resolve({});
      final accent = DashTokens.of(
        tester.element(find.byType(ControllerHeat)),
      ).accent;
      expect(border(0)?.color, isNot(accent));

      await openKeypad(tester);
      expect(border(0)?.color, accent);
      // Only the one being typed in.
      expect(border(1)?.color, isNot(accent));

      await tester.tap(byLogId('controller.heat_target_cancel'));
      await settle(tester);
      expect(border(0)?.color, isNot(accent));
    });

    testWidgets('a lone 0 switches the heater off', (tester) async {
      await pump(tester, _status());
      await openKeypad(tester);

      await typeDigits(tester, '0');
      await confirm(tester);

      expect(commands.calls, ['nozzle:1:0:0']);
    });

    testWidgets('a second 0 is still just 0', (tester) async {
      await pump(tester, _status());
      await openKeypad(tester);

      await typeDigits(tester, '00');
      expect(typedIn('0°'), findsOneWidget);
      await confirm(tester);

      expect(commands.calls, ['nozzle:1:0:0']);
    });

    testWidgets('a leading 0 gives way to the next digit', (tester) async {
      await pump(tester, _status());
      await openKeypad(tester);

      await typeDigits(tester, '05');
      expect(typedIn('5°'), findsOneWidget);
      await confirm(tester);

      expect(commands.calls, ['nozzle:1:5:0']);
    });

    testWidgets('the first digit replaces the target the button showed', (
      tester,
    ) async {
      await pump(tester, _status());
      await openKeypad(tester);
      expect(typedIn(pl.controllerTarget('220°')), findsOneWidget);

      await typeDigits(tester, '2');
      expect(typedIn('2°'), findsOneWidget);
      await typeDigits(tester, '5');
      expect(typedIn('25°'), findsOneWidget);
      await confirm(tester);

      expect(commands.calls, ['nozzle:1:25:0']);
    });

    testWidgets('takes no more than three digits', (tester) async {
      await pump(tester, _status());
      await openKeypad(tester);

      await typeDigits(tester, '2305');
      expect(typedIn('230°'), findsOneWidget);
      await confirm(tester);

      expect(commands.calls, ['nozzle:1:230:0']);
    });

    testWidgets('confirming with nothing typed sends nothing', (tester) async {
      await pump(tester, _status());
      await openKeypad(tester);

      await confirm(tester);

      expect(commands.calls, isEmpty);
      expect(byLogId('controller.heat_target_key.1'), findsNothing);
    });

    testWidgets('cancelling sends nothing and gives the button back', (
      tester,
    ) async {
      await pump(tester, _status());
      await openKeypad(tester);
      await typeDigits(tester, '230');

      await tester.tap(byLogId('controller.heat_target_cancel'));
      await settle(tester);

      expect(commands.calls, isEmpty);
      expect(typedIn(pl.controllerTarget('220°')), findsOneWidget);
    });

    testWidgets('a tap outside closes it and sends nothing', (tester) async {
      await pump(tester, _status());
      await openKeypad(tester);
      await typeDigits(tester, '230');

      await tester.tapAt(const Offset(4, 200));
      await settle(tester);

      expect(commands.calls, isEmpty);
      expect(byLogId('controller.heat_target_key.1'), findsNothing);
      expect(typedIn(pl.controllerTarget('220°')), findsOneWidget);
    });

    testWidgets('is laid out as a keypad', (tester) async {
      await pump(tester, _status());
      await openKeypad(tester);

      Rect key(String id) =>
          tester.getRect(byLogId('controller.heat_target_$id'));
      Rect digit(int d) => key('key.$d');
      for (final row in const [
        [1, 2, 3],
        [4, 5, 6],
        [7, 8, 9],
      ]) {
        expect(digit(row[1]).top, digit(row[0]).top);
        expect(digit(row[2]).top, digit(row[0]).top);
        expect(digit(row[0]).left, lessThan(digit(row[1]).left));
        expect(digit(row[1]).left, lessThan(digit(row[2]).left));
      }
      expect(digit(4).top, greaterThan(digit(1).top));
      expect(digit(7).top, greaterThan(digit(4).top));
      expect(digit(0).top, greaterThan(digit(7).top));
      expect(digit(0).center.dx, digit(8).center.dx);
      // ✕ and ✓ flank the 0 on its row.
      expect(key('cancel').top, digit(0).top);
      expect(key('cancel').right, lessThan(digit(0).left));
      expect(key('set').top, digit(0).top);
      expect(key('set').left, greaterThan(digit(0).right));
      expect(tester.takeException(), isNull);
    });

    testWidgets('is dragged by its handle, keys and all', (tester) async {
      await pump(tester, _status());
      await openKeypad(tester);
      final before = tester.getRect(byLogId('controller.heat_target_key.5'));

      await tester.drag(
        byLogId('controller.heat_target_handle'),
        const Offset(-120, 30),
      );
      await tester.pump();

      expect(
        tester.getRect(byLogId('controller.heat_target_key.5')).center,
        before.center + const Offset(-120, 30),
      );
      // Still a keypad after the move.
      await typeDigits(tester, '7');
      await confirm(tester);
      expect(commands.calls, ['nozzle:1:7:0']);
    });

    testWidgets('stays clear of the button being typed in', (tester) async {
      await pump(tester, _status());
      for (final index in [0, 1]) {
        await openKeypad(tester, index: index);
        final field = tester.getRect(
          byLogId('controller.heat_target').at(index),
        );
        final keys = [
          for (final d in [1, 2, 3, 4, 5, 6, 7, 8, 9, 0])
            tester.getRect(byLogId('controller.heat_target_key.$d')),
          tester.getRect(byLogId('controller.heat_target_cancel')),
          tester.getRect(byLogId('controller.heat_target_set')),
        ];
        final pad = keys.reduce((a, b) => a.expandToInclude(b));

        expect(pad.overlaps(field), isFalse, reason: 'heater $index');
        expect(pad.top, greaterThan(0));
        expect(pad.bottom, lessThan(_phone.height));

        await tester.tap(byLogId('controller.heat_target_cancel'));
        await settle(tester);
      }
    });
  });

  group('the chamber', () {
    testWidgets('of a printer without a heater can only be read', (
      tester,
    ) async {
      await pump(tester, _status());

      expect(find.text(pl.controllerNoChamberHeater), findsOneWidget);
      // Nozzle and bed have steppers; the chamber does not.
      expect(byLogId('controller.heat_plus'), findsNWidgets(2));
    });

    testWidgets('of a printer with a heater has a stepper of its own', (
      tester,
    ) async {
      await pump(tester, _status(), model: 'H2D');

      expect(find.text(pl.controllerNoChamberHeater), findsNothing);
      expect(byLogId('controller.heat_plus'), findsNWidgets(3));

      await tapStep(tester, 'controller.heat_plus', index: 2);

      expect(commands.calls, ['chamber:1:5']);
    });

    testWidgets('shows its airduct and flips it', (tester) async {
      await pump(tester, _status(airduct: 0), model: 'H2D');

      expect(find.text(pl.ctrlAirductCooling), findsOneWidget);

      await tester.tap(byLogId('controller.airduct'));
      await tester.pump();

      expect(commands.calls, ['airduct:1:true']);
    });

    testWidgets('has no airduct on a printer without one', (tester) async {
      await pump(tester, _status(airduct: 0));

      expect(byLogId('controller.airduct'), findsNothing);
    });
  });

  group('two nozzles', () {
    const temps = {
      'nozzle': 38.0,
      'nozzle_2': 218.0,
      'nozzle_2_target': 220.0,
      'bed': 60.0,
      'bed_target': 60.0,
    };

    testWidgets('mark the active one and offer the other', (tester) async {
      await pump(tester, _status(temps: temps, extruder: 0), model: 'H2D');

      expect(find.text(pl.ctrlNozzleActive), findsOneWidget);
      expect(byLogId('controller.activate_nozzle'), findsOneWidget);
      expect(find.text(pl.tempNozzleNumbered('1')), findsOneWidget);
      expect(find.text(pl.tempNozzleNumbered('2')), findsOneWidget);
    });

    testWidgets('activating the left head selects extruder 1', (tester) async {
      await pump(tester, _status(temps: temps, extruder: 0), model: 'H2D');

      await tester.tap(byLogId('controller.activate_nozzle'));
      await tester.pump();

      expect(commands.calls, ['extruder:1:1']);
    });

    testWidgets('is locked while printing', (tester) async {
      await pump(
        tester,
        _status(temps: temps, extruder: 0, state: 'RUNNING'),
        model: 'H2D',
      );

      await tester.tap(byLogId('controller.activate_nozzle'));
      await tester.pump();

      expect(commands.calls, isEmpty);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('a target goes to the head it belongs to', (tester) async {
      await pump(tester, _status(temps: temps, extruder: 0), model: 'H2D');

      // The first card is the plain key, which is the left head: index 1.
      await tapStep(tester, 'controller.heat_plus', index: 0);
      // The second is `nozzle_2`, the right head: index 0.
      await tapStep(tester, 'controller.heat_plus', index: 1);

      expect(commands.calls, ['nozzle:1:5:1', 'nozzle:1:225:0']);
    });

    testWidgets('one nozzle has no switch at all', (tester) async {
      await pump(tester, _status());

      expect(byLogId('controller.activate_nozzle'), findsNothing);
      expect(find.text(pl.ctrlNozzleActive), findsNothing);
    });
  });

  group('the fans', () {
    testWidgets('are listed with what they run at', (tester) async {
      await pump(tester, _status());

      expect(byLogId('controller.fan.part'), findsOneWidget);
      expect(byLogId('controller.fan.aux'), findsOneWidget);
      expect(byLogId('controller.fan.chamber'), findsOneWidget);
      expect(find.text('70%'), findsOneWidget);
    });

    testWidgets('a tap on the slider sets that fan', (tester) async {
      await pump(tester, _status());

      await tester.tap(byLogId('controller.fan.part'));
      await tester.pump();

      expect(commands.calls, ['fan:1:part:50']);
    });
  });

  group('a session the server refuses', () {
    testWidgets('is told so, and every control is dead', (tester) async {
      await pump(tester, _status());
      commands.error = const AuthException(AppErrorCode.forbidden);

      await tapStep(tester, 'controller.heat_plus');
      await settle(tester);
      commands.calls.clear();

      expect(find.text(pl.ctrlForbidden), findsOneWidget);
      await tester.tap(byLogId('controller.heat_plus').first);
      await tester.tap(byLogId('controller.fan.part'));
      await tester.pump();

      expect(commands.calls, isEmpty);
    });
  });

  group('the layout', () {
    for (final size in const [
      Size(844, 390),
      Size(1229, 540),
      Size(740, 320),
      Size(1280, 800),
    ]) {
      testWidgets('fills ${size.width.round()}x${size.height.round()} without '
          'scrolling', (tester) async {
        await pump(tester, _status(), model: 'H2D', size: size);

        expect(
          find.descendant(
            of: find.byType(ControllerHeat),
            matching: find.byType(Scrollable),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        final bottom = tester.getRect(find.byType(ControllerHeat)).bottom;
        expect(
          tester.getRect(byLogId('controller.fan.part')).bottom,
          lessThanOrEqualTo(bottom),
        );
      });
    }
  });
}
