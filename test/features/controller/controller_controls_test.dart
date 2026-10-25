import 'dart:ui' show Tristate;

import 'package:bambuddy_mobile/core/api/action_outcome.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/models/smart_plug.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/features/controller/controller_controls.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/data/smart_plugs_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_overview.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/dashboard/smart_plugs_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

const _phone = Size(844, 390);

class _Plugs extends SmartPlugsNotifier {
  _Plugs(this._fixed);

  final SmartPlugsState _fixed;
  final calls = <({int id, SmartPlugAction action})>[];

  @override
  SmartPlugsState build() => _fixed;

  @override
  Future<ActionOutcome> control(int plugId, SmartPlugAction action) async {
    calls.add((id: plugId, action: action));
    return ActionOutcome.ok;
  }
}

SmartPlugsState _plug({bool monitorOnly = false, bool reachable = true}) =>
    SmartPlugsState(
      plugs: [
        SmartPlug(
          id: 10,
          name: 'Szafa',
          printerId: 1,
          enabled: true,
          showOnPrinterCard: true,
          plugType: monitorOnly ? 'mqtt' : null,
        ),
      ],
      statuses: {
        10: SmartPlugStatus(
          state: 'ON',
          reachable: reachable,
          energy: const SmartPlugEnergy(power: 42),
        ),
      },
    );

PrinterStatus _printing({
  Map<String, double>? temps,
  int? speed = 2,
  bool? light = false,
  int? extruder,
  String state = 'RUNNING',
}) => PrinterStatus(
  id: 1,
  connected: true,
  state: state,
  progress: 40,
  currentPrint: 'Benchy.3mf',
  speedLevel: speed,
  chamberLight: light,
  activeExtruder: extruder,
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
  setUpAll(loadAppFonts);

  late RecordingCommands commands;
  late _Plugs plugs;

  Future<void> pump(
    WidgetTester tester,
    PrinterStatus status, {
    SmartPlugsState? plugState,
  }) async {
    useLogicalWindow(tester, _phone);
    commands = RecordingCommands();
    plugs = _Plugs(plugState ?? const SmartPlugsState());
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    await pumpPhone(
      tester,
      const Scaffold(body: ControllerOverview(printerId: 1)),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        noServerProfileOverride,
        printerCommandsRepositoryProvider.overrideWithValue(commands),
        smartPlugsProvider.overrideWith(() => plugs),
        fixedDashboardOverride(
          DashboardState(
            printers: [
              PrinterWithStatus(
                printer: const Printer(id: 1, name: 'X1C Warsztat'),
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

  /// Whether the reading with this spoken label is marked as the chosen one.
  bool selected(WidgetTester tester, String label) =>
      tester
          .getSemantics(find.bySemanticsLabel(label))
          .getSemanticsData()
          .flagsCollection
          .isSelected ==
      Tristate.isTrue;

  group('the readings', () {
    testWidgets('show each sensor now and, where set, its target', (
      tester,
    ) async {
      await pump(tester, _printing());

      expect(find.bySemanticsLabel('${pl.tempNozzle} 218° / 220°'), findsOne);
      expect(find.bySemanticsLabel('${pl.tempBed} 60° / 60°'), findsOne);
      expect(find.bySemanticsLabel('${pl.tempChamber} 34°'), findsOne);
    });

    testWidgets('have a bar each and no state label', (tester) async {
      await pump(tester, _printing());

      expect(
        find.descendant(
          of: find.byType(ControllerReadings),
          matching: find.byType(DashProgressBar),
        ),
        findsNWidgets(3),
        reason: 'a bar each',
      );
    });

    testWidgets('on four are one size, none scaled to fit, target on Heat', (
      tester,
    ) async {
      await pump(
        tester,
        _printing(
          temps: const {
            'nozzle': 250,
            'nozzle_target': 250,
            'nozzle_2': 50,
            'bed': 70,
            'bed_target': 70,
            'chamber': 41,
          },
        ),
      );

      final tiles = find.descendant(
        of: find.byType(ControllerReadings),
        matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_ReadingTile',
        ),
      );
      expect(tiles, findsNWidgets(4));
      // Nothing in a tile is scaled by a FittedBox: that is what made each
      // tile's text a size of its own.
      expect(
        find.descendant(of: tiles, matching: find.byType(FittedBox)),
        findsNothing,
      );
      // The same style in every tile, and no target beside the reading.
      double? firstSize(InlineSpan span) {
        double? size;
        span.visitChildren((child) {
          if (child is TextSpan && (child.text ?? '').isNotEmpty) {
            size = child.style?.fontSize;
            return false;
          }
          return true;
        });
        return size;
      }

      final readings = <String, double?>{
        for (final e
            in find
                .descendant(of: tiles, matching: find.byType(RichText))
                .evaluate())
          (e.widget as RichText).text.toPlainText(): firstSize(
            (e.widget as RichText).text,
          ),
      };
      expect(readings.keys, containsAll(['250°', '50°', '70°', '41°']));
      final values = [
        for (final key in ['250°', '50°', '70°', '41°']) readings[key],
      ];
      expect(values.toSet(), hasLength(1));
      expect(values.first, isNotNull);
    });

    for (final (name, temps) in [
      ('three', null),
      (
        'four',
        const {
          'nozzle': 250.0,
          'nozzle_target': 250.0,
          'nozzle_2': 50.0,
          'bed': 70.0,
          'bed_target': 70.0,
          'chamber': 41.0,
        },
      ),
    ]) {
      testWidgets('on $name have the label on the top edge, the bar on the '
          'bottom one and the reading centred between them', (tester) async {
        await pump(tester, _printing(temps: temps));

        final tiles = find.descendant(
          of: find.byType(ControllerReadings),
          matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_ReadingTile',
          ),
        );
        expect(tiles.evaluate(), isNotEmpty);
        // Padding and the tile's border.
        const inset = DashSpace.sm + 1;
        for (var i = 0; i < tiles.evaluate().length; i++) {
          final tile = tester.getRect(tiles.at(i));
          final texts = find
              .descendant(of: tiles.at(i), matching: find.byType(RichText))
              .evaluate()
              .map((e) => tester.getRect(find.byWidget(e.widget)))
              .toList();
          // The label is the upper text, the reading the lower one.
          texts.sort((a, b) => a.top.compareTo(b.top));
          final label = texts.first;
          final reading = texts.last;
          final bar = tester.getRect(
            find.descendant(
              of: tiles.at(i),
              matching: find.byType(DashProgressBar),
            ),
          );

          expect(label.top, closeTo(tile.top + inset, 1), reason: 'label $i');
          expect(bar.bottom, closeTo(tile.bottom - inset, 1), reason: 'bar $i');
          expect(
            reading.center.dy,
            closeTo((label.bottom + bar.top) / 2, 1),
            reason: 'reading vertically between them, tile $i',
          );
          expect(
            reading.center.dx,
            closeTo(tile.center.dx, 1),
            reason: 'reading horizontally, tile $i',
          );
        }
      });
    }

    testWidgets('on three keep the target beside the reading', (tester) async {
      await pump(tester, _printing());

      expect(find.textContaining('218°'), findsWidgets);
      expect(find.textContaining('/ 220°'), findsOneWidget);
    });

    testWidgets('a printer without temperatures has no readings', (
      tester,
    ) async {
      await pump(
        tester,
        const PrinterStatus(id: 1, connected: true, state: 'IDLE'),
      );

      expect(find.text(pl.tempBed), findsNothing);
    });

    testWidgets('two nozzles are numbered and the active one is outlined', (
      tester,
    ) async {
      await pump(
        tester,
        _printing(
          extruder: 0,
          temps: const {
            'nozzle': 38,
            'nozzle_2': 218,
            'nozzle_2_target': 220,
            'bed': 60,
            'bed_target': 60,
          },
        ),
      );

      expect(find.text(pl.tempNozzleNumbered('1')), findsOneWidget);
      expect(find.text(pl.tempNozzleNumbered('2')), findsOneWidget);
      // Extruder 0 is the right-hand head, which reports as `nozzle_2`.
      expect(
        selected(tester, '${pl.tempNozzleNumbered('2')} 218° / 220°'),
        isTrue,
      );
      expect(selected(tester, '${pl.tempNozzleNumbered('1')} 38°'), isFalse);
    });

    testWidgets('extruder 1, the left head, outlines the plain key', (
      tester,
    ) async {
      await pump(
        tester,
        _printing(
          extruder: 1,
          temps: const {
            'nozzle': 218,
            'nozzle_target': 220,
            'nozzle_2': 38,
            'bed': 60,
          },
        ),
      );

      expect(
        selected(tester, '${pl.tempNozzleNumbered('1')} 218° / 220°'),
        isTrue,
      );
      expect(selected(tester, '${pl.tempNozzleNumbered('2')} 38°'), isFalse);
    });

    testWidgets('on one nozzle nothing is outlined', (tester) async {
      await pump(tester, _printing());

      expect(selected(tester, '${pl.tempNozzle} 218° / 220°'), isFalse);
    });

    testWidgets('one nozzle is just "nozzle", never numbered', (tester) async {
      await pump(tester, _printing());

      expect(find.text(pl.tempNozzleNumbered('1')), findsNothing);
      expect(find.text(pl.tempNozzle), findsOneWidget);
    });
  });

  group('speed', () {
    testWidgets('offers the four levels with the current one chosen', (
      tester,
    ) async {
      await pump(tester, _printing(speed: 3));

      for (final level in [1, 2, 3, 4]) {
        expect(byLogId('controller.speed.$level'), findsOneWidget);
      }
      expect(find.text('124%'), findsOneWidget);
    });

    testWidgets('choosing one sends it for this printer', (tester) async {
      await pump(tester, _printing());

      await tester.tap(byLogId('controller.speed.4'));
      await tester.pump();

      expect(commands.calls, ['speed:1:4']);
    });

    testWidgets('an idle printer has no speed to change', (tester) async {
      await pump(tester, _printing(state: 'IDLE'));

      expect(byLogId('controller.speed.1'), findsNothing);
    });
  });

  group('a session the server refuses', () {
    testWidgets('loses the speed and the light, which could only fail', (
      tester,
    ) async {
      await pump(tester, _printing());
      commands.error = const AuthException(AppErrorCode.forbidden);

      await tester.tap(byLogId('controller.speed.4'));
      await settle(tester);

      expect(byLogId('controller.speed.1'), findsNothing);
      expect(byLogId('controller.light'), findsNothing);
    });
  });

  group('the chamber light', () {
    testWidgets('toggles to the opposite of what it is', (tester) async {
      await pump(tester, _printing(light: false));

      await tester.tap(byLogId('controller.light'));
      await tester.pump();

      expect(commands.calls, ['light:1:true']);
    });

    testWidgets('a printer that does not answer offers no switch', (
      tester,
    ) async {
      await pump(
        tester,
        const PrinterStatus(id: 1, connected: false, state: 'IDLE'),
      );

      expect(byLogId('controller.light'), findsNothing);
    });
  });

  group('the smart plug', () {
    testWidgets('is absent when the printer has none', (tester) async {
      await pump(tester, _printing(state: 'IDLE'));

      expect(byLogId('controller.smart_plug'), findsNothing);
    });

    testWidgets('shows what it draws', (tester) async {
      await pump(tester, _printing(state: 'IDLE'), plugState: _plug());

      expect(find.text(pl.powerWatts(42)), findsOneWidget);
    });

    testWidgets('asks before cutting the power, and cancelling does nothing', (
      tester,
    ) async {
      await pump(tester, _printing(state: 'IDLE'), plugState: _plug());

      await tester.tap(byLogId('controller.smart_plug'));
      await settle(tester);

      expect(find.text(pl.smartPlugOffConfirmTitle), findsOneWidget);
      expect(plugs.calls, isEmpty);

      await tester.tap(byLogId('controller.smart_plug_confirm.cancel'));
      await settle(tester);

      expect(plugs.calls, isEmpty);
    });

    testWidgets('confirming switches it off', (tester) async {
      await pump(tester, _printing(state: 'IDLE'), plugState: _plug());

      await tester.tap(byLogId('controller.smart_plug'));
      await settle(tester);
      await tester.tap(byLogId('controller.smart_plug_confirm.confirm'));
      await settle(tester);

      expect(plugs.calls, [(id: 10, action: SmartPlugAction.off)]);
    });

    testWidgets('is locked while printing, with the reason on the lock', (
      tester,
    ) async {
      await pump(tester, _printing(), plugState: _plug());

      await tester.tap(byLogId('controller.smart_plug'));
      await settle(tester);

      expect(find.text(pl.smartPlugOffConfirmTitle), findsNothing);
      expect(plugs.calls, isEmpty);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.byTooltip(pl.smartPlugCantPowerOff), findsOneWidget);
    });

    testWidgets('a monitor-only plug is read, never switched', (tester) async {
      await pump(
        tester,
        _printing(state: 'IDLE'),
        plugState: _plug(monitorOnly: true),
      );

      await tester.tap(byLogId('controller.smart_plug'));
      await settle(tester);

      expect(plugs.calls, isEmpty);
      expect(find.text(pl.smartPlugOffConfirmTitle), findsNothing);
      expect(find.byTooltip(pl.smartPlugMonitorOnly), findsOneWidget);
    });

    testWidgets('an unreachable plug cannot be switched, and says why', (
      tester,
    ) async {
      await pump(
        tester,
        _printing(state: 'IDLE'),
        plugState: _plug(reachable: false),
      );

      await tester.tap(byLogId('controller.smart_plug'));
      await settle(tester);

      expect(plugs.calls, isEmpty);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.byTooltip(pl.smartPlugUnreachable), findsOneWidget);
    });

    testWidgets('a session the server refuses is locked out, with the reason', (
      tester,
    ) async {
      await pump(
        tester,
        _printing(state: 'IDLE'),
        plugState: _plug().copyWith(forbidden: true),
      );

      await tester.tap(byLogId('controller.smart_plug'));
      await settle(tester);

      expect(plugs.calls, isEmpty);
      expect(find.byTooltip(pl.ctrlForbidden), findsOneWidget);
    });

    testWidgets('a plug that works shows a switch, not a lock', (tester) async {
      await pump(tester, _printing(state: 'IDLE'), plugState: _plug());

      expect(find.byIcon(Icons.lock_outline), findsNothing);
    });
  });
}
