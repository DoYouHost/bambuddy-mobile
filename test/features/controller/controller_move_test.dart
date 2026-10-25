import 'dart:async';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/printers/bed_jog.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_move.dart';
import 'package:bambuddy_mobile/features/dashboard/controls_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/features/controller/scale_to_fit.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

const _phone = Size(844, 390);

PrinterStatus _status({
  String state = 'IDLE',
  bool connected = true,
  int? extruder,
  bool twoNozzles = false,
}) => PrinterStatus(
  id: 1,
  connected: connected,
  state: state,
  activeExtruder: extruder,
  temperatures: {'nozzle': 25, if (twoNozzles) 'nozzle_2': 25, 'bed': 24},
);

void main() {
  late RecordingCommands commands;

  Future<void> pump(
    WidgetTester tester,
    PrinterStatus status, {
    String? model = 'X1C',
    BedJogConvention? convention,
    Size size = _phone,
  }) async {
    useLogicalWindow(tester, size);
    commands = RecordingCommands();
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    await pumpPhone(
      tester,
      const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(16),
          // Scaled as the screen scales its body.
          child: ScaleToFit(child: ControllerMove(printerId: 1)),
        ),
      ),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        noServerProfileOverride,
        printerCommandsRepositoryProvider.overrideWithValue(commands),
        if (convention != null)
          bedJogConventionProvider.overrideWith((ref) async => convention),
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

  Future<void> tap(WidgetTester tester, String id, {int index = 0}) async {
    await tester.tap(byLogId(id).at(index));
    await tester.pump();
  }

  group('the X/Y pad', () {
    testWidgets('sends a relative jog of the step in the arrow\'s direction', (
      tester,
    ) async {
      await pump(tester, _status());

      await tap(tester, 'controller.jog_y_plus');
      await tap(tester, 'controller.jog_x_minus');

      expect(commands.calls, ['xyJog:1:0.0:10.0', 'xyJog:1:-10.0:0.0']);
    });

    testWidgets('follows the step that was chosen', (tester) async {
      await pump(tester, _status());

      await tap(tester, 'controller.step_preset', index: 0);
      await tap(tester, 'controller.jog_x_plus');

      expect(commands.calls, ['xyJog:1:1.0:0.0']);
    });

    testWidgets('waits for the jog in flight before taking another', (
      tester,
    ) async {
      await pump(tester, _status());
      commands.gate = Completer<void>();

      await tap(tester, 'controller.jog_y_plus');
      // The rest of the pad looks as dead as it is.
      expect(
        tester
            .widget<FilledButton>(
              find.descendant(
                of: byLogId('controller.jog_x_plus'),
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );
      await tap(tester, 'controller.jog_x_plus');
      commands.gate!.complete();
      await tester.pump();

      expect(commands.calls, ['xyJog:1:0.0:10.0']);
    });
  });

  group('Z', () {
    testWidgets('sends what bedJogDistance says for this model', (
      tester,
    ) async {
      await pump(tester, _status());

      await tap(tester, 'controller.jog_z_up');
      await tap(tester, 'controller.jog_z_down');

      final up = bedJogDistance(
        up: true,
        step: 10,
        model: 'X1C',
        convention: BedJogConvention.direct,
      );
      final down = bedJogDistance(
        up: false,
        step: 10,
        model: 'X1C',
        convention: BedJogConvention.direct,
      );
      expect(commands.calls, ['bedJog:1:$up:false', 'bedJog:1:$down:false']);
      expect(up, -down!, reason: 'the two arrows are opposite');
    });

    testWidgets('on an A1 the server\'s convention may flip the sign', (
      tester,
    ) async {
      await pump(
        tester,
        _status(),
        model: 'A1',
        convention: BedJogConvention.flippedOnA1,
      );
      await tester.pump();

      await tap(tester, 'controller.jog_z_up');

      final flipped = bedJogDistance(
        up: true,
        step: 10,
        model: 'A1',
        convention: BedJogConvention.flippedOnA1,
      );
      expect(commands.calls, ['bedJog:1:$flipped:false']);
    });

    testWidgets('a direction that cannot be known is a note, not a guess', (
      tester,
    ) async {
      await pump(
        tester,
        _status(),
        model: 'A1',
        convention: BedJogConvention.unknown,
      );
      await tester.pump();

      expect(find.text(pl.ctrlMoveZUnknownDirection), findsOneWidget);
      expect(byLogId('controller.jog_z_up'), findsNothing);
    });

    testWidgets('a printer without a model gets the note about it', (
      tester,
    ) async {
      await pump(tester, _status(), model: null);

      expect(find.text(pl.ctrlMoveZNoModel), findsOneWidget);
      expect(byLogId('controller.jog_z_up'), findsNothing);
    });
  });

  group('extrude and retract', () {
    testWidgets('move the filament by the length, forward or back', (
      tester,
    ) async {
      await pump(tester, _status());

      await tap(tester, 'controller.jog_extrude');
      await tap(tester, 'controller.jog_retract');

      expect(commands.calls, ['extruderJog:1:10.0', 'extruderJog:1:-10.0']);
    });

    testWidgets('follow the length that was chosen', (tester) async {
      await pump(tester, _status());

      await tap(tester, 'controller.length_preset', index: 2);
      await tap(tester, 'controller.jog_extrude');

      expect(commands.calls, ['extruderJog:1:25.0']);
    });

    testWidgets('on one nozzle there is nothing to choose between', (
      tester,
    ) async {
      await pump(tester, _status());

      expect(byLogId('controller.jog_nozzle'), findsNothing);
    });
  });

  group('two nozzles', () {
    testWidgets('choose which one extrudes, and select it on the printer', (
      tester,
    ) async {
      await pump(tester, _status(twoNozzles: true, extruder: 0), model: 'H2D');

      expect(byLogId('controller.jog_nozzle'), findsNWidgets(2));

      // Nozzle 1 is the left head, hardware index 1.
      await tap(tester, 'controller.jog_nozzle', index: 0);

      expect(commands.calls, ['extruder:1:1']);
    });

    testWidgets('leave the active one alone', (tester) async {
      await pump(tester, _status(twoNozzles: true, extruder: 0), model: 'H2D');

      // Nozzle 2 is the right head, index 0, which is already active.
      await tap(tester, 'controller.jog_nozzle', index: 1);

      expect(commands.calls, isEmpty);
    });
  });

  group('home', () {
    testWidgets('runs the full home and says it started', (tester) async {
      await pump(tester, _status());

      await tap(tester, 'controller.home');
      await tester.pump();

      expect(commands.calls, ['homeAxes:1']);
      expect(find.text(pl.ctrlMoveHomeStarted), findsOneWidget);
    });
  });

  group('when it is not allowed', () {
    testWidgets('a running print locks every control and says why', (
      tester,
    ) async {
      await pump(tester, _status(state: 'RUNNING'));

      expect(find.text(pl.controllerMoveLocked), findsOneWidget);
      for (final id in [
        'controller.jog_y_plus',
        'controller.jog_z_up',
        'controller.jog_extrude',
        'controller.home',
      ]) {
        await tap(tester, id);
      }
      await tap(tester, 'controller.step_preset', index: 0);

      expect(commands.calls, isEmpty);
    });

    testWidgets('a printer that does not answer cannot be moved', (
      tester,
    ) async {
      await pump(tester, _status(connected: false));

      await tap(tester, 'controller.jog_x_plus');

      expect(commands.calls, isEmpty);
    });

    testWidgets('a session the server refuses is told so and locked out', (
      tester,
    ) async {
      await pump(tester, _status());
      commands.error = const AuthException(AppErrorCode.forbidden);

      await tap(tester, 'controller.jog_x_plus');
      await settle(tester);
      commands.calls.clear();

      expect(find.text(pl.ctrlForbidden), findsOneWidget);
      await tap(tester, 'controller.jog_x_plus');

      expect(commands.calls, isEmpty);
    });
  });

  group('the size of the controls', () {
    const jogs = [
      'controller.jog_x_plus',
      'controller.jog_y_minus',
      'controller.jog_z_up',
      'controller.jog_z_down',
      'controller.jog_extrude',
      'controller.jog_retract',
      'controller.home',
    ];

    testWidgets('every jog is a real touch target at the design size', (
      tester,
    ) async {
      await pump(tester, _status());

      for (final id in jogs) {
        final size = tester.getRect(byLogId(id)).size;
        expect(size.height, greaterThanOrEqualTo(44), reason: id);
        expect(size.width, greaterThanOrEqualTo(44), reason: id);
      }
    });

    testWidgets('and they grow when the screen does', (tester) async {
      await pump(tester, _status());
      final small = tester.getRect(byLogId('controller.jog_z_up')).size;

      await pump(tester, _status(), size: const Size(1280, 800));
      final large = tester.getRect(byLogId('controller.jog_z_up')).size;

      expect(large.height, greaterThan(small.height * 1.3));
      expect(large.width, greaterThan(small.width * 1.3));
    });

    testWidgets('Z fills the pad\'s height between its two buttons', (
      tester,
    ) async {
      await pump(tester, _status());

      final up = tester.getRect(byLogId('controller.jog_z_up'));
      final down = tester.getRect(byLogId('controller.jog_z_down'));
      final top = tester.getRect(byLogId('controller.jog_y_plus'));
      final bottom = tester.getRect(byLogId('controller.jog_y_minus'));
      expect(up.top, closeTo(top.top, 0.5));
      expect(down.bottom, closeTo(bottom.bottom, 0.5));
      // Taller than a pad arrow, and only a gap between them.
      expect(up.height, greaterThan(top.height * 1.3));
      expect(down.top - up.bottom, lessThan(up.height / 4));
    });

    testWidgets('Extrude and Retract fill their card under the lengths', (
      tester,
    ) async {
      await pump(tester, _status());

      final length = tester.getRect(byLogId('controller.length_preset').last);
      final extrude = tester.getRect(byLogId('controller.jog_extrude'));
      final retract = tester.getRect(byLogId('controller.jog_retract'));
      expect(extrude.top - length.bottom, lessThan(extrude.height / 4));
      expect(retract.top - extrude.bottom, lessThan(extrude.height / 4));
    });

    testWidgets('the pad\'s arrows fill their cells, no gap in the middle', (
      tester,
    ) async {
      await pump(tester, _status());

      final up = tester.getRect(byLogId('controller.jog_y_plus'));
      final right = tester.getRect(byLogId('controller.jog_x_plus'));
      final left = tester.getRect(byLogId('controller.jog_x_minus'));
      final down = tester.getRect(byLogId('controller.jog_y_minus'));
      // The left and right arrows are as wide as the up and down ones are,
      // and the three rows touch only through the gaps between them.
      expect(left.width, closeTo(up.width, 0.5));
      expect(right.width, closeTo(up.width, 0.5));
      expect(right.top - up.bottom, lessThan(up.height / 4));
      expect(down.top - right.bottom, lessThan(up.height / 4));
    });

    testWidgets('are filled, locked or not, never a bare outline', (
      tester,
    ) async {
      await pump(tester, _status(state: 'RUNNING'));

      for (final id in ['controller.jog_x_plus', 'controller.jog_z_up']) {
        final button = buttonAt(tester, id);
        expect(button.onPressed, isNull, reason: '$id is locked in a print');
        final fill = button.style?.backgroundColor?.resolve({
          WidgetState.disabled,
        });
        expect(fill, isNotNull, reason: id);
        expect(fill!.a, greaterThan(0.05), reason: id);
      }
    });

    testWidgets('the step row lines up with the pad and Z above it', (
      tester,
    ) async {
      await pump(tester, _status());

      Rect at(String id, {bool last = false}) =>
          tester.getRect(last ? byLogId(id).last : byLogId(id).first);
      final steps = byLogId('controller.step_preset');
      final firstStep = tester.getRect(steps.first);
      final lastStep = tester.getRect(steps.last);
      final home = at('controller.home');

      // The presets span the pad's width, edge to edge...
      expect(firstStep.left, closeTo(at('controller.jog_x_minus').left, 0.5));
      expect(lastStep.right, closeTo(at('controller.jog_x_plus').right, 0.5));
      // ...and Home spans Z's.
      expect(home.left, closeTo(at('controller.jog_z_up').left, 0.5));
      expect(home.right, closeTo(at('controller.jog_z_up').right, 0.5));
      // Same top and bottom, so it is one row.
      expect(home.top, closeTo(firstStep.top, 0.5));
      expect(home.bottom, closeTo(firstStep.bottom, 0.5));
    });

    testWidgets('the axes share one card', (tester) async {
      await pump(tester, _status());

      // The pad and Z sit side by side in the same box, not in two.
      final pad = tester.getRect(byLogId('controller.jog_x_plus'));
      final z = tester.getRect(byLogId('controller.jog_z_up'));
      expect(pad.right, lessThan(z.left));
      expect(
        (pad.center.dy - z.center.dy).abs(),
        lessThan(200),
        reason: 'on one row',
      );
    });
  });

  group('controls that do the same kind of thing', () {
    for (final size in const [Size(844, 390), Size(1280, 800)]) {
      testWidgets('are one size in every card at '
          '${size.width.round()}x${size.height.round()}', (tester) async {
        await pump(tester, _status(), size: size);

        Size of(String id) => tester.getRect(byLogId(id).first).size;
        // The step chips sit in the axes card, the length chips in the
        // extruder's; one scale over the body keeps them the same.
        expect(
          of('controller.step_preset').height,
          closeTo(of('controller.length_preset').height, 0.01),
        );
        expect(
          of('controller.jog_z_up').height,
          closeTo(of('controller.jog_extrude').height, 0.01),
          reason: 'jogs share one height',
        );
        expect(
          of('controller.jog_z_down').height,
          closeTo(of('controller.jog_retract').height, 0.01),
          reason: 'the second button of each pair too',
        );
        expect(
          of('controller.jog_x_plus').height,
          closeTo(of('controller.jog_y_minus').height, 0.01),
          reason: 'the rows of the pad are one height',
        );
        expect(
          of('controller.home').height,
          closeTo(of('controller.step_preset').height, 0.01),
          reason: 'Home sits in the step row, at its height',
        );
      });
    }
  });

  group('the jogs', () {
    testWidgets('fill the width of their cards, leaving no empty band', (
      tester,
    ) async {
      await pump(tester, _status(), size: const Size(1280, 600));

      final right = tester.getRect(byLogId('controller.jog_x_plus'));
      final zUp = tester.getRect(byLogId('controller.jog_z_up'));
      final extrude = tester.getRect(byLogId('controller.jog_extrude'));
      final length = tester.getRect(byLogId('controller.length_preset').last);
      // The pad reaches the Z column, and Extrude spans its card like the
      // presets above it.
      expect(zUp.left - right.right, lessThan(48));
      expect(extrude.right, closeTo(length.right, 0.5));
    });
  });

  group('the step', () {
    testWidgets('sits with the axes it moves, not with the extruder', (
      tester,
    ) async {
      await pump(tester, _status());

      final pad = tester.getRect(byLogId('controller.jog_y_minus'));
      final step = tester.getRect(byLogId('controller.step_preset').first);
      final home = tester.getRect(byLogId('controller.home'));
      final extruder = tester.getRect(byLogId('controller.jog_extrude'));
      expect(step.top, greaterThan(pad.bottom), reason: 'under the pad');
      expect(home.top, greaterThan(pad.bottom));
      expect(home.right, lessThan(extruder.left), reason: 'not in its card');
    });
  });

  group('the layout', () {
    for (final size in const [
      Size(844, 390),
      Size(1229, 540),
      Size(740, 320),
      Size(1280, 800),
    ]) {
      testWidgets('fits ${size.width.round()}x${size.height.round()} without '
          'scrolling', (tester) async {
        await pump(
          tester,
          _status(twoNozzles: true, extruder: 0),
          model: 'H2D',
          size: size,
        );

        expect(
          find.descendant(
            of: find.byType(ControllerMove),
            matching: find.byType(Scrollable),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
