import 'dart:async';

import 'package:dio/dio.dart';
import 'package:bambuddy_mobile/core/ams/color_names.dart';
import 'package:bambuddy_mobile/core/models/filament_requirement.dart';
import 'package:bambuddy_mobile/core/models/library_file.dart';
import 'package:bambuddy_mobile/core/models/plate_list.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_print.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/orders/orders_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_mapping_sheet.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import '../queue/queue_form_harness.dart';

const _p1s = Printer(id: 1, name: 'P1S Warsztat', model: 'P1S');
const _h2d = Printer(id: 1, name: 'H2D Warsztat', model: 'H2D');

// Orange PLA, teal PETG and black ABS, in that order, on one AMS.
const _ams = [
  AmsUnit(
    id: 0,
    trays: [
      AmsTray(id: 0, trayType: 'PLA', trayColor: 'FF8A3DFF'),
      AmsTray(id: 1, trayType: 'PETG', trayColor: '2FB5A8FF'),
      AmsTray(id: 2, trayType: 'ABS', trayColor: '2B2B2BFF'),
      AmsTray(id: 3, trayType: 'PLA', trayColor: 'FF8A3DFF'),
    ],
  ),
];

const _threeFilaments = [
  FilamentRequirement(slotId: 1, type: 'PLA', color: '#FF8A3D'),
  FilamentRequirement(slotId: 2, type: 'PETG', color: '#2FB5A8'),
  FilamentRequirement(slotId: 3, type: 'ABS', color: '#2B2B2B'),
];

LibraryFile _file({String? model = 'P1S', String name = 'benchy.gcode.3mf'}) =>
    LibraryFile(
      id: 5,
      filename: name,
      fileType: 'gcode',
      fileSize: 4096,
      printCount: 0,
      slicedForModel: model,
      printTimeSeconds: 11520,
      filamentUsedGrams: 45,
    );

/// A printer whose AMS the test can change between opening the screen and
/// pressing Print.
class _Live extends PrintersRepository {
  _Live(this.status) : super(Dio());

  PrinterStatus status;

  @override
  Future<List<Printer>> fetchPrinters() async => const [];

  @override
  Future<PrinterStatus?> fetchStatus(int printerId) async => status;

  @override
  Future<SlotInventory> fetchInventoryRemain(int printerId) async =>
      (grams: const <int, double>{}, spools: const <int, SlotSpool>{});
}

const _h2c = Printer(id: 1, name: 'H2C Warsztat', model: 'H2C');

List<NozzleRackSlot> _rack() => const [
  NozzleRackSlot(id: 16, nozzleDiameter: '0.4', nozzleType: 'HS01'),
  NozzleRackSlot(id: 17, nozzleDiameter: '0.6', nozzleType: 'HS01'),
  NozzleRackSlot(id: 18, nozzleDiameter: '0.4', nozzleType: 'HS01'),
  NozzleRackSlot(id: 19, nozzleDiameter: '', nozzleType: ''),
];

/// One filament in a rack-bound group wanting a 0.4 standard nozzle.
final _oneRackGroup = FilamentRequirement.parseList({
  'filaments': [
    {
      'slot_id': 1,
      'type': 'PLA',
      'color': '#FF8A3D',
      'group_id': 1,
      'group': {
        'on_rack': true,
        'nozzle_diameter': '0.40',
        'volume_type': 'Standard',
      },
    },
  ],
});

final _threePlates = PlateList.fromJson({
  'plates': [
    {'index': 1, 'name': 'Base', 'object_count': 1},
    {'index': 2, 'name': 'Lid', 'object_count': 1},
    {'index': 3, 'name': 'Clip', 'object_count': 1},
  ],
  'is_multi_plate': true,
  'has_gcode': true,
});

void main() {
  setUpAll(loadAppFonts);
  setUp(setUpQueueForm);

  /// The print screen on [printer], over a landscape phone.
  Future<void> pump(
    WidgetTester tester, {
    Printer printer = _p1s,
    LibraryFile? file,
    List<FilamentRequirement> requirements = _threeFilaments,
    Map<int, PrinterStatus>? live,
    PlateList plates = PlateList.none,
    bool triState = true,
    bool copies = false,
    bool held = false,
    int createStatus = 200,
    Locale? locale,
    List<NozzleRackSlot>? nozzleRack,
    List<Override> extra = const [],
    PrinterStatus? status,
    Size size = const Size(844, 390),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noServerProfileOverride,
          ...queueFormOverrides(
            triState: triState,
            plates: plates,
            printers: [printer],
            requirements: requirements,
            live: live ?? {printer.id: const PrinterStatus(id: 1, ams: _ams)},
            createStatus: createStatus,
            nozzleRack: nozzleRack,
          ),
          fixedDashboardOverride(
            DashboardState(
              printers: [
                PrinterWithStatus(
                  printer: printer,
                  status:
                      status ??
                      const PrinterStatus(
                        id: 1,
                        connected: true,
                        state: 'IDLE',
                      ),
                ),
              ],
            ),
          ),
          inertStatusesOverride,
          batchListingProvider.overrideWithValue(AsyncData(copies)),
          batchOrdersProvider.overrideWithValue(const AsyncData(false)),
          queueOutcomeProvider.overrideWithValue(const AsyncData(false)),
          preferLowestFilamentProvider.overrideWithValue(
            const AsyncData(false),
          ),
          mappingColorCatalogProvider.overrideWith(
            (ref) async => ColorCatalog.empty,
          ),
          awaitingReviewProvider.overrideWithValue(held),
          ...extra,
        ],
        child: locale == null
            ? plApp(const SizedBox())
            : MaterialApp(
                theme: buildDashThemeData(
                  Brightness.dark,
                  brand: bambuddyBrand,
                ),
                locale: locale,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: AppLocalizations.supportedLocales,
                home: const SizedBox(),
              ),
      ),
    );
    await tester.pumpAndSettle();
    // Pushed over a base route, as the controller pushes it: leaving it must
    // leave something behind.
    unawaited(
      openControllerPrint(
        tester.element(find.byType(SizedBox).first),
        printer: printer,
        file: file ?? _file(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester) async {
    await tester.tap(byLogId('controller.print.submit'));
    await tester.pumpAndSettle();
  }

  /// Saves the mapping sheet: its button is at the foot of a list that does not
  /// build it until it is scrolled to.
  Future<void> confirmSheet(WidgetTester tester) async {
    await tester.dragUntilVisible(
      byLogId('queue_mapping.confirm'),
      find.byType(ListView).last,
      const Offset(0, -120),
    );
    await tester.ensureVisible(byLogId('queue_mapping.confirm'));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('queue_mapping.confirm'));
    await tester.pumpAndSettle();
  }

  FilledButton submitButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.descendant(
      of: byLogId('controller.print.submit'),
      matching: find.byType(FilledButton),
    ),
  );

  group('the screen', () {
    testWidgets('names the file and locks the printer in the bar', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text(pl.controllerPrintTitle), findsOneWidget);
      expect(find.text('benchy.gcode.3mf'), findsWidgets);
      expect(find.text('P1S Warsztat'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    });

    testWidgets('matches every filament to a slot of this printer', (
      tester,
    ) async {
      await pump(tester);

      expect(byLogId('controller.print.filament'), findsNWidgets(3));
      expect(find.textContaining('A1 · PLA'), findsOneWidget);
      expect(find.textContaining('A2 · PETG'), findsOneWidget);
      expect(find.textContaining('A3 · ABS'), findsOneWidget);
      expect(
        find.text(pl.controllerPrintAutoMatched('P1S Warsztat')),
        findsOneWidget,
      );
      expect(find.text(pl.controllerPrintNotLoaded), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a filament no slot supplies is flagged', (tester) async {
      await pump(
        tester,
        requirements: const [
          FilamentRequirement(slotId: 1, type: 'PLA', color: '#FF8A3D'),
          FilamentRequirement(slotId: 2, type: 'TPU', color: '#111111'),
        ],
      );

      expect(find.text(pl.controllerPrintNotLoaded), findsOneWidget);
      expect(find.text(pl.controllerPrintUnmapped(1)), findsOneWidget);
    });

    testWidgets('fits a small window and a large system font', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(
        tester,
        size: const Size(740, 320),
        copies: true,
        plates: _threePlates,
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('what is sent', () {
    testWidgets('the job is for the controller printer and no model', (
      tester,
    ) async {
      await pump(tester);

      await send(tester);

      expect(capturedBody?['printer_id'], 1);
      expect(capturedBody?.containsKey('target_model'), isFalse);
      expect(capturedBody?.containsKey('target_location'), isFalse);
      expect(capturedBody?['library_file_id'], 5);
    });

    testWidgets('the filament is matched against the printer as it is', (
      tester,
    ) async {
      await pump(tester);

      await send(tester);

      // Orange PLA, teal PETG, black ABS: A1, A2, A3.
      expect(capturedBody?['ams_mapping'], [0, 1, 2]);
    });

    testWidgets('a printer that reports nothing loaded sends no mapping', (
      tester,
    ) async {
      await pump(tester, live: const {});

      await send(tester);

      expect(capturedBody?.containsKey('ams_mapping'), isFalse);
    });

    testWidgets('Now goes first in the queue', (tester) async {
      await pump(tester);

      await send(tester);

      expect(capturedBody?['insert_at_top'], isTrue);
    });

    testWidgets('Queue goes to the end', (tester) async {
      await pump(tester);

      await tester.tap(find.text(pl.queueScheduleQueue));
      await tester.pump();
      expect(find.text(pl.fmAddToQueue), findsOneWidget);
      await send(tester);

      expect(capturedBody?['insert_at_top'], isNot(isTrue));
    });

    testWidgets('Schedule waits for a time', (tester) async {
      await pump(tester);

      await tester.tap(find.text(pl.queueScheduleSchedule));
      await tester.pump();

      expect(byLogId('controller.print.pick_time'), findsOneWidget);
      expect(submitButton(tester).onPressed, isNull);
    });

    testWidgets('an account held for review always waits', (tester) async {
      await pump(tester, held: true);
      expect(find.text(pl.queueEditAwaitingReviewNote), findsOneWidget);

      await send(tester);

      expect(capturedBody?['manual_start'], isTrue);
    });

    testWidgets('an ordinary account is not held', (tester) async {
      await pump(tester);

      await send(tester);

      expect(capturedBody?['manual_start'], isFalse);
    });

    testWidgets('nozzle offset goes to a printer with two nozzles', (
      tester,
    ) async {
      await pump(
        tester,
        printer: _h2d,
        file: _file(model: 'H2D'),
      );

      await send(tester);

      expect(capturedBody?.containsKey('nozzle_offset_cali'), isTrue);
    });

    testWidgets('and to no other', (tester) async {
      await pump(tester);

      await send(tester);

      expect(capturedBody?.containsKey('nozzle_offset_cali'), isFalse);
    });

    testWidgets('a created job closes the screen and is reported', (
      tester,
    ) async {
      await pump(tester);

      await send(tester);

      expect(find.byType(ControllerPrintScreen), findsNothing);
    });

    testWidgets('a refused job leaves the screen as it was', (tester) async {
      await pump(tester, createStatus: 400);

      await send(tester);

      expect(find.byType(ControllerPrintScreen), findsOneWidget);
      expect(submitButton(tester).onPressed, isNotNull);
    });

    testWidgets('pressing twice does not send twice', (tester) async {
      await pump(tester);

      // The button is off the moment it is pressed, until the answer is in.
      await tester.tap(byLogId('controller.print.submit'));
      await tester.pump();

      expect(submitButton(tester).onPressed, isNull);
      await tester.pumpAndSettle();
    });
  });

  group('plate and copies', () {
    testWidgets('a single-plate file has no plate row', (tester) async {
      await pump(tester);

      expect(byLogId('controller.print.plate.more'), findsNothing);
    });

    testWidgets('another plate is sent, and starts the mapping over', (
      tester,
    ) async {
      await pump(tester, plates: _threePlates);
      expect(find.text('Base'), findsOneWidget);

      await tester.tap(byLogId('controller.print.plate.more'));
      await tester.pumpAndSettle();
      expect(find.text('Lid'), findsOneWidget);
      await send(tester);

      expect(capturedBody?['plate_id'], 2);
    });

    testWidgets('the plate row stops at both ends', (tester) async {
      await pump(tester, plates: _threePlates);

      FilledButton button(String id) => tester.widget<FilledButton>(
        find.descendant(of: byLogId(id), matching: find.byType(FilledButton)),
      );

      expect(button('controller.print.plate.less').onPressed, isNull);
      await tester.tap(byLogId('controller.print.plate.more'));
      await tester.tap(byLogId('controller.print.plate.more'));
      await tester.pump();
      expect(button('controller.print.plate.more').onPressed, isNull);
    });

    testWidgets('copies are offered only where the server lists batches', (
      tester,
    ) async {
      await pump(tester);

      expect(byLogId('controller.print.copies.more'), findsNothing);
    });

    testWidgets('copies count from one and are sent', (tester) async {
      await pump(tester, copies: true);
      FilledButton less() => tester.widget<FilledButton>(
        find.descendant(
          of: byLogId('controller.print.copies.less'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(less().onPressed, isNull);

      await tester.tap(byLogId('controller.print.copies.more'));
      await tester.tap(byLogId('controller.print.copies.more'));
      await tester.pump();
      expect(find.text('3'), findsOneWidget);
      await send(tester);

      expect(capturedBody?['quantity'], 3);
    });
  });

  group('the mapping', () {
    testWidgets('a row opens the sheet; dismissing it changes nothing', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(byLogId('controller.print.filament').first);
      await tester.pumpAndSettle();
      expect(find.text(pl.mappingReRead), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text(pl.mappingReRead), findsNothing);
      expect(
        find.text(pl.controllerPrintAutoMatched('P1S Warsztat')),
        findsOneWidget,
      );
      expect(byLogId('controller.print.reset_mapping'), findsNothing);
    });

    testWidgets('saving the sheet makes it a manual mapping, until reset', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(byLogId('controller.print.filament').first);
      await tester.pumpAndSettle();

      await confirmSheet(tester);

      expect(find.text(pl.controllerPrintManualMapping), findsOneWidget);
      expect(byLogId('controller.print.reset_mapping'), findsOneWidget);

      await tester.tap(byLogId('controller.print.reset_mapping'));
      await tester.pump();

      expect(
        find.text(pl.controllerPrintAutoMatched('P1S Warsztat')),
        findsOneWidget,
      );
    });

    testWidgets('another plate drops a mapping made for the first', (
      tester,
    ) async {
      await pump(tester, plates: _threePlates);
      await tester.tap(byLogId('controller.print.filament').first);
      await tester.pumpAndSettle();
      await confirmSheet(tester);
      expect(find.text(pl.controllerPrintManualMapping), findsOneWidget);

      await tester.tap(byLogId('controller.print.plate.more'));
      await tester.pump();

      expect(find.text(pl.controllerPrintManualMapping), findsNothing);
    });
  });

  group('what is auto stays auto', () {
    testWidgets('a spool swapped after the screen opened is followed', (
      tester,
    ) async {
      final live = _Live(const PrinterStatus(id: 1, ams: _ams));
      await pump(
        tester,
        extra: [printersRepositoryProvider.overrideWithValue(live)],
      );
      expect(find.textContaining('A1 · PLA'), findsOneWidget);

      // PETG and PLA trade places in the AMS.
      live.status = const PrinterStatus(
        id: 1,
        ams: [
          AmsUnit(
            id: 0,
            trays: [
              AmsTray(id: 0, trayType: 'PETG', trayColor: '2FB5A8FF'),
              AmsTray(id: 1, trayType: 'PLA', trayColor: 'FF8A3DFF'),
              AmsTray(id: 2, trayType: 'ABS', trayColor: '2B2B2BFF'),
            ],
          ),
        ],
      );
      await send(tester);

      expect(capturedBody?['ams_mapping'], [1, 0, 2]);
    });
  });

  group('the nozzle rack', () {
    Future<void> openRack(WidgetTester tester) async {
      await tester.tap(byLogId('controller.print.filament').first);
      await tester.pumpAndSettle();
      await tester.tap(byLogId('queue_mapping.rack').first);
      await tester.pumpAndSettle();
      await tester.tap(byLogId('queue_mapping.rack_position_3'));
      await tester.pumpAndSettle();
    }

    Future<void> pumpRack(WidgetTester tester) => pump(
      tester,
      printer: _h2c,
      file: _file(model: 'H2C'),
      requirements: _oneRackGroup,
      nozzleRack: _rack(),
      live: const {1: PrinterStatus(id: 1, ams: _ams)},
    );

    testWidgets('a position picked and saved is sent', (tester) async {
      await pumpRack(tester);

      await openRack(tester);
      await confirmSheet(tester);
      await send(tester);

      expect(capturedBody?['nozzle_rack_choice'], isNotNull);
    });

    testWidgets('a position picked in a sheet that is dismissed is not', (
      tester,
    ) async {
      await pumpRack(tester);

      await openRack(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await send(tester);

      expect(capturedBody?.containsKey('nozzle_rack_choice'), isFalse);
    });
  });

  // The controller never shrinks text to fit: where it does not fit, the layout
  // gives way. Measured with the app's own fonts in every language.
  for (final locale in AppLocalizations.supportedLocales) {
    for (final size in const [Size(832, 392), Size(1280, 800)]) {
      for (final textScale in const [1.0, 1.3]) {
        testWidgets('the print screen keeps its text its size in '
            '${locale.languageCode} at ${size.width.round()}x${size.height.round()}, '
            'font $textScale', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = textScale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await pump(
            tester,
            locale: locale,
            size: size,
            copies: true,
            plates: _threePlates,
            file: _file(name: 'a_rather_long_file_name_for_a_tile.gcode.3mf'),
            held: true,
            requirements: const [
              ..._threeFilaments,
              FilamentRequirement(slotId: 4, type: 'TPU', color: '#111111'),
            ],
          );

          // The one that scales the body as a whole; none inside it.
          expect(
            find.descendant(
              of: find.byType(ControllerPrintScreen),
              matching: find.byType(FittedBox),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          for (final e
              in find
                  .descendant(
                    of: find.byType(ControllerPrintScreen),
                    matching: find.byType(Text),
                  )
                  .evaluate()) {
            final paragraph = e.renderObject! as RenderParagraph;
            final text = paragraph.text.toPlainText();
            // Server data and names the user chose may be long.
            if (text.contains('.gcode.3mf') ||
                text.contains('Warsztat') ||
                text.endsWith(' g')) {
              continue;
            }
            expect(
              paragraph.didExceedMaxLines,
              isFalse,
              reason: '"$text" is cut short',
            );
          }
        });
      }
    }
  }

  group('print options', () {
    String valueOf(WidgetTester tester, String id) => tester
        .widgetList<Text>(
          find.descendant(of: byLogId(id), matching: find.byType(Text)),
        )
        .last
        .data!;

    testWidgets('a calibration steps Auto, On, Off, Auto', (tester) async {
      await pump(tester);
      final seen = <String>[valueOf(tester, 'controller.print.bed_levelling')];

      for (var i = 0; i < 3; i++) {
        await tester.tap(byLogId('controller.print.bed_levelling'));
        await tester.pump();
        seen.add(valueOf(tester, 'controller.print.bed_levelling'));
      }

      // The remembered starting point is On, as for a user who never set it.
      expect(seen, [pl.commonOn, pl.commonOff, pl.commonAuto, pl.commonOn]);
    });

    testWidgets('an older server has only On and Off', (tester) async {
      await pump(tester, triState: false);
      final seen = <String>[valueOf(tester, 'controller.print.flow_cali')];

      for (var i = 0; i < 2; i++) {
        await tester.tap(byLogId('controller.print.flow_cali'));
        await tester.pump();
        seen.add(valueOf(tester, 'controller.print.flow_cali'));
      }

      expect(seen, [pl.commonOn, pl.commonOff, pl.commonOn]);
    });

    testWidgets('a choice is sent and remembered for the next print', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(byLogId('controller.print.timelapse'));
      await tester.tap(byLogId('controller.print.bed_levelling'));
      await tester.pump();

      await send(tester);

      expect(capturedBody?['timelapse'], isTrue);
      expect(capturedBody?['bed_levelling'], isFalse);
      expect(storedPrintOptions().timelapse, isTrue);
    });
  });

  group('when it cannot be printed', () {
    testWidgets('a file for another model says so and cannot be sent', (
      tester,
    ) async {
      await pump(tester, file: _file(model: 'H2D'));

      expect(
        find.text(pl.controllerPrintWrongModel('H2D', 'P1S')),
        findsOneWidget,
      );
      expect(submitButton(tester).onPressed, isNull);
    });

    testWidgets('a printer of the same family takes the file', (tester) async {
      await pump(tester, file: _file(model: 'X1C'));

      expect(submitButton(tester).onPressed, isNotNull);
    });

    testWidgets('a printer that is printing says the job will wait', (
      tester,
    ) async {
      await pump(
        tester,
        status: const PrinterStatus(id: 1, connected: true, state: 'RUNNING'),
      );

      expect(find.text(pl.controllerPrintBusy), findsOneWidget);
      expect(submitButton(tester).onPressed, isNotNull);
    });

    testWidgets('a printer that cannot be reached says the job will wait', (
      tester,
    ) async {
      await pump(tester, status: const PrinterStatus(id: 1, connected: false));

      expect(find.text(pl.controllerPrintOffline), findsOneWidget);
      expect(submitButton(tester).onPressed, isNotNull);
    });

    testWidgets('Close leaves without sending', (tester) async {
      await pump(tester);

      await tester.tap(byLogId('controller.print.close'));
      await tester.pumpAndSettle();

      expect(find.byType(ControllerPrintScreen), findsNothing);
      expect(capturedBody, isNull);
    });
  });
}
