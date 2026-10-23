import 'dart:async';

import 'package:dio/dio.dart';
import 'package:bambuddy_mobile/core/ams/color_names.dart';
import 'package:bambuddy_mobile/core/ams/job_cost.dart';
import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/cost_center.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/filament_requirement.dart';
import 'package:bambuddy_mobile/core/models/library_file.dart';
import 'package:bambuddy_mobile/core/models/plate_list.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_print.dart';
import 'package:bambuddy_mobile/features/controller/scale_to_fit.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/common/print_thumbnail.dart';
import 'package:bambuddy_mobile/features/orders/orders_providers.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/features/queue/job_cost_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_drafts.dart';
import 'package:bambuddy_mobile/features/queue/queue_mapping_sheet.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../contract/sent_writes.dart';
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

/// The plates a file holds are whatever its gcode names say: plate 2 may have
/// been deleted in the slicer.
PlateList _platesAt(List<int> indexes) => PlateList.fromJson({
  'plates': [
    for (final i in indexes) {'index': i, 'name': 'P$i', 'object_count': 1},
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
    QueueItem? draft,
    List<Object>? asked,
    bool inRoster = true,
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
    useLogicalWindow(tester, size);
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
            asked: asked,
          ),
          fixedDashboardOverride(
            DashboardState(
              printers: [
                if (inRoster)
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
        draft: draft ?? libraryFileQueueDraft(file ?? _file()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester) async {
    await tester.tap(byLogId('controller.print.submit'));
    await tester.pumpAndSettle();
  }

  /// Saves the mapping dialog.
  Future<void> confirmSheet(WidgetTester tester) async {
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

      expect(buttonAt(tester, 'controller.print.plate.less').onPressed, isNull);
      await tester.tap(byLogId('controller.print.plate.more'));
      await tester.tap(byLogId('controller.print.plate.more'));
      await tester.pump();
      expect(buttonAt(tester, 'controller.print.plate.more').onPressed, isNull);
    });

    testWidgets('a gap in the plate numbers is stepped over', (tester) async {
      await pump(tester, plates: _platesAt([1, 3]));
      expect(find.text('P1'), findsOneWidget);

      await tester.tap(byLogId('controller.print.plate.more'));
      await tester.pumpAndSettle();
      expect(find.text('P3'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.descendant(
                of: byLogId('controller.print.plate.more'),
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );
      await send(tester);

      expect(capturedBody?['plate_id'], 3);
    });

    testWidgets('a file whose plates start above 1 opens on its first and '
        'sends it', (tester) async {
      await pump(tester, plates: _platesAt([2, 3]));
      expect(find.text('P2'), findsOneWidget);

      await send(tester);

      expect(capturedBody?['plate_id'], 2);
    });

    testWidgets('a file that starts at plate 1 sends no plate until one is '
        'picked', (tester) async {
      await pump(tester, plates: _platesAt([1, 3]));

      await send(tester);

      expect(capturedBody?.containsKey('plate_id'), isFalse);
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
      // Six positions in a dialog of a panel's height: the list scrolls.
      await tester.dragUntilVisible(
        byLogId('queue_mapping.rack_position_3'),
        find.byType(ListView).last,
        const Offset(0, -60),
      );
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

  /// Opens the "More options" dialog.
  Future<void> openMore(WidgetTester tester) async {
    await tester.tap(byLogId('controller.print.more'));
    await tester.pumpAndSettle();
  }

  /// A row of the dialog, scrolled into the part of the list that is built.
  Future<void> reveal(WidgetTester tester, String id, {Finder? target}) async {
    await tester.dragUntilVisible(
      target ?? byLogId('controller.print.more.$id'),
      find.descendant(of: find.byType(Dialog), matching: find.byType(ListView)),
      const Offset(0, -60),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapMore(WidgetTester tester, String id) async {
    await reveal(tester, id);
    await tester.tap(byLogId('controller.print.more.$id'));
    await tester.pumpAndSettle();
  }

  Future<void> closeMore(WidgetTester tester) async {
    await tester.tap(byLogId('controller.print.more.close'));
    await tester.pumpAndSettle();
  }

  /// Fails on any text under [root] that its box cuts short.
  void expectNothingCut(WidgetTester tester, Finder root) {
    for (final e
        in find.descendant(of: root, matching: find.byType(Text)).evaluate()) {
      final paragraph = e.renderObject! as RenderParagraph;
      final text = paragraph.text.toPlainText();
      // Server data and names the user chose may be long.
      if (text.contains('.gcode.3mf') || text.contains('Warsztat')) continue;
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: '"$text" is cut short',
      );
    }
  }

  const tight = CostCenter(
    id: 2,
    name: 'Workshop',
    budget: CostCenterBudget.monthly,
    budgetLimit: 100,
    budgetAvailable: 5,
  );
  const personal = CostCenter(id: 1, name: 'Alice', isPrivate: true);

  for (final locale in AppLocalizations.supportedLocales) {
    for (final size in const [Size(832, 392), Size(1280, 800)]) {
      for (final textScale in const [1.0, 1.3]) {
        final where =
            '${locale.languageCode} at ${size.width.round()}x'
            '${size.height.round()}, font $textScale';

        testWidgets('billing keeps its text its size in $where', (
          tester,
        ) async {
          tester.platformDispatcher.textScaleFactorTestValue = textScale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await pump(
            tester,
            locale: locale,
            size: size,
            copies: true,
            extra: [
              serverUiFlagsProvider.overrideWith(
                (ref) async => {'billing_enabled': true},
              ),
              printableCostCentersProvider.overrideWith(
                (ref) async => [personal, tight],
              ),
              jobCostProvider.overrideWith(
                (ref, key) async => (total: 10.0, anyPrice: true),
              ),
            ],
          );
          // The cheaper centre has less than the job costs.
          await tester.tap(byLogId('controller.print.cost_center'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Workshop'));
          await tester.pumpAndSettle();
          expectNothingCut(tester, find.byType(Dialog));
          await closeMore(tester);

          expect(tester.takeException(), isNull);
          expectNothingCut(tester, find.byType(ControllerPrintScreen));
        });

        for (final blocked in const [<CostCenter>[], null]) {
          testWidgets(
            'the ${blocked == null ? 'refused' : 'empty'} billing note '
            'keeps its text its size in $where',
            (tester) async {
              tester.platformDispatcher.textScaleFactorTestValue = textScale;
              addTearDown(
                tester.platformDispatcher.clearTextScaleFactorTestValue,
              );
              await pump(
                tester,
                locale: locale,
                size: size,
                extra: [
                  serverUiFlagsProvider.overrideWith(
                    (ref) async => {'billing_enabled': true},
                  ),
                  printableCostCentersProvider.overrideWith(
                    (ref) async => blocked,
                  ),
                ],
              );

              expect(tester.takeException(), isNull);
              expectNothingCut(tester, find.byType(ControllerPrintScreen));
            },
          );
        }

        testWidgets('the options dialog keeps its text its size in $where', (
          tester,
        ) async {
          tester.platformDispatcher.textScaleFactorTestValue = textScale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await pump(
            tester,
            locale: locale,
            size: size,
            printer: _h2d,
            file: _file(model: 'H2D'),
            extra: [
              queueOutcomeProvider.overrideWithValue(const AsyncData(true)),
              gcodeSnippetModelsProvider.overrideWithValue(
                const AsyncData({'P1S'}),
              ),
            ],
          );

          await tester.tap(
            find.text(lookupAppLocalizations(locale).queueScheduleQueue),
          );
          await tester.pump();
          await openMore(tester);
          final list = find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(ListView),
          );
          // Every row in turn: the list builds only the ones in view.
          for (var i = 0; i < 8; i++) {
            expectNothingCut(tester, find.byType(Dialog));
            await tester.drag(list, const Offset(0, -80));
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  group('an archive', () {
    Archive archive({int? plateId, bool asks = false, int? createdById}) =>
        Archive(
          id: 77,
          createdById: createdById,
          filename: 'cube.gcode.3mf',
          status: 'completed',
          printName: 'Cube',
          slicedForModel: 'P1S',
          plateId: plateId,
          confirmRequested: asks,
        );

    testWidgets('is reprinted from the archive, on the plate it ran', (
      tester,
    ) async {
      final asked = <Object>[];
      await pump(
        tester,
        plates: _threePlates,
        draft: archiveQueueDraft(archive(plateId: 2)),
        asked: asked,
      );

      expect(find.byType(PrintThumbnail), findsOneWidget);
      await send(tester);

      expect(capturedBody?['archive_id'], 77);
      expect(capturedBody?['library_file_id'], isNull);
      expect(capturedBody?['plate_id'], 2);
      // The plate list and the filament it needs are read from the archive:
      // a library route keyed by an archive id answers for another file.
      expect(asked, isNotEmpty);
      for (final key in asked) {
        final isArchive = switch (key) {
          (final bool archive, int _) => archive,
          PlateSource(:final isArchive) => isArchive,
          _ => fail('unexpected key $key'),
        };
        expect(isArchive, isTrue, reason: '$key');
      }
    });

    testWidgets('a plate the file no longer lists gives way to the first', (
      tester,
    ) async {
      await pump(
        tester,
        plates: _threePlates,
        draft: archiveQueueDraft(archive(plateId: 5)),
      );

      await send(tester);

      // Plate 1, which the request leaves out; never the missing 5.
      expect(capturedBody?['plate_id'], isNull);
    });

    const reprintOwn = CurrentUser(
      id: 7,
      username: 'op',
      isAdmin: false,
      permissions: {Permissions.queueCreate, Permissions.archivesReprintOwn},
    );

    testWidgets('a printer gone from the roster says so', (tester) async {
      await pump(tester, inRoster: false);

      expect(submitButton(tester).onPressed, isNull);
      expect(find.text(pl.controllerPrinterGone), findsOneWidget);
    });

    testWidgets('a reprint-own user prints their own print again', (
      tester,
    ) async {
      await pump(
        tester,
        draft: archiveQueueDraft(archive(createdById: 7)),
        extra: [currentUserOverride(reprintOwn)],
      );

      expect(submitButton(tester).onPressed, isNotNull);
    });

    testWidgets('someone else\'s print is refused here too, and says why', (
      tester,
    ) async {
      await pump(
        tester,
        draft: archiveQueueDraft(archive(createdById: 99)),
        extra: [currentUserOverride(reprintOwn)],
      );

      expect(submitButton(tester).onPressed, isNull);
      expect(find.text(pl.archiveReprintNotAllowed), findsOneWidget);
    });

    testWidgets('a file is refused to an account that may not queue', (
      tester,
    ) async {
      await pump(
        tester,
        extra: [
          currentUserOverride(
            const CurrentUser(id: 7, username: 'op', isAdmin: false),
          ),
        ],
      );

      expect(submitButton(tester).onPressed, isNull);
      expect(find.text(pl.archiveReprintNoQueue), findsOneWidget);
    });

    testWidgets('an archive that asked for its outcome asks again', (
      tester,
    ) async {
      await pump(
        tester,
        draft: archiveQueueDraft(archive(asks: true)),
        extra: [
          queueOutcomeProvider.overrideWithValue(const AsyncData(true)),
          defaultConfirmOutcomeProvider.overrideWithValue(
            const AsyncData(false),
          ),
        ],
      );

      await openMore(tester);
      await reveal(tester, 'confirm_outcome');
      expect(
        find.descendant(
          of: byLogId('controller.print.more.confirm_outcome'),
          matching: find.text(pl.commonOn),
        ),
        findsOneWidget,
      );
      // Locked on: the server keeps asking whatever the switch says.
      await tester.tap(byLogId('controller.print.more.confirm_outcome'));
      await tester.pumpAndSettle();
      await closeMore(tester);
      await send(tester);

      expect(capturedBody?['confirm_outcome'], isTrue);
    });
  });

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

  group('more options', () {
    testWidgets('the switches reach the request', (tester) async {
      await pump(tester);

      await openMore(tester);
      await tapMore(tester, 'require_previous');
      await tapMore(tester, 'power_off');
      await closeMore(tester);
      await send(tester);

      expect(capturedBody?['require_previous_success'], isTrue);
      expect(capturedBody?['auto_off_after'], isTrue);
    });

    testWidgets('vibration and first-layer inspection are sent and kept', (
      tester,
    ) async {
      await pump(tester);

      await openMore(tester);
      await tapMore(tester, 'vibration');
      await tapMore(tester, 'layer_inspect');
      await closeMore(tester);
      await send(tester);

      expect(capturedBody?['vibration_cali'], isFalse);
      expect(capturedBody?['layer_inspect'], isFalse);
      expect(storedPrintOptions().vibrationCali, isFalse);
    });

    testWidgets(
      'a change made in the dialog is on the screen after it closes',
      (tester) async {
        await pump(tester);

        await openMore(tester);
        await tapMore(tester, 'vibration');
        await closeMore(tester);
        await openMore(tester);
        await reveal(tester, 'vibration');

        expect(
          find.descendant(
            of: byLogId('controller.print.more.vibration'),
            matching: find.text(pl.commonOff),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('manual start is offered in Queue and nowhere else', (
      tester,
    ) async {
      await pump(tester);

      await openMore(tester);
      await reveal(tester, 'power_off');
      expect(byLogId('controller.print.more.manual_start'), findsNothing);
      await closeMore(tester);

      await tester.tap(find.text(pl.queueScheduleQueue));
      await tester.pump();
      await openMore(tester);
      await tapMore(tester, 'manual_start');
      await closeMore(tester);
      await send(tester);

      expect(capturedBody?['manual_start'], isTrue);
    });

    testWidgets('leaving Queue drops the manual start', (tester) async {
      await pump(tester);

      await tester.tap(find.text(pl.queueScheduleQueue));
      await tester.pump();
      await openMore(tester);
      await tapMore(tester, 'manual_start');
      await closeMore(tester);
      await tester.tap(find.text(pl.controllerPrintNow));
      await tester.pump();
      await send(tester);

      expect(capturedBody?['manual_start'], isFalse);
    });

    testWidgets('an account held for review is not offered the switch', (
      tester,
    ) async {
      await pump(tester, held: true);
      await tester.tap(find.text(pl.queueScheduleQueue));
      await tester.pump();

      await openMore(tester);
      await reveal(tester, 'power_off');

      expect(byLogId('controller.print.more.manual_start'), findsNothing);
    });

    testWidgets('preheat is inherited until it is set', (tester) async {
      await pump(tester);

      await send(tester);

      expect(capturedBody?['preheat_override'], 'inherit');
      expect(
        capturedBody?.containsKey('preheat_chamber_target_override'),
        isFalse,
      );
    });

    testWidgets('preheat on takes a chamber target in steps of five', (
      tester,
    ) async {
      await pump(tester);

      await openMore(tester);
      await reveal(tester, 'preheat', target: find.text(pl.queueEditPreheat));
      await tester.tap(
        find.descendant(
          of: byLogId('controller.print.more.preheat'),
          matching: find.text(pl.commonOn),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, 'chamber.more');
      await tester.tap(byLogId('controller.print.more.chamber.more'));
      await tester.pump();
      await tester.tap(byLogId('controller.print.more.chamber.more'));
      await tester.pumpAndSettle();
      expect(find.text('10°'), findsOneWidget);
      await closeMore(tester);
      await send(tester);

      expect(capturedBody?['preheat_override'], 'on');
      expect(capturedBody?['preheat_chamber_target_override'], 10);
    });

    testWidgets('the target goes back to the filament default below five', (
      tester,
    ) async {
      await pump(tester);

      await openMore(tester);
      await reveal(tester, 'chamber.more');
      await tester.tap(byLogId('controller.print.more.chamber.more'));
      await tester.pumpAndSettle();
      expect(find.text('5°'), findsOneWidget);
      await tester.tap(byLogId('controller.print.more.chamber.less'));
      await tester.pumpAndSettle();
      expect(find.text('—'), findsWidgets);
      await closeMore(tester);
      await send(tester);

      expect(
        capturedBody?.containsKey('preheat_chamber_target_override'),
        isFalse,
      );
    });

    testWidgets('the target stops at what the server takes', (tester) async {
      await pump(tester);

      await openMore(tester);
      await reveal(tester, 'chamber.more');
      for (var i = 0; i < 20; i++) {
        await tester.tap(byLogId('controller.print.more.chamber.more'));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.text('60°'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.descendant(
                of: byLogId('controller.print.more.chamber.more'),
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('a ceiling between two steps is the last stop', (tester) async {
      await pump(
        tester,
        extra: [chamberMaxTargetProvider.overrideWithValue(62)],
      );

      await openMore(tester);
      await reveal(tester, 'chamber.more');
      for (var i = 0; i < 13; i++) {
        await tester.tap(byLogId('controller.print.more.chamber.more'));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.text('62°'), findsOneWidget);
    });

    testWidgets('preheat off sends no target', (tester) async {
      await pump(tester);

      await openMore(tester);
      await reveal(tester, 'chamber.more');
      await tester.tap(byLogId('controller.print.more.chamber.more'));
      await tester.pumpAndSettle();
      await reveal(tester, 'preheat', target: find.text(pl.queueEditPreheat));
      await tester.tap(
        find.descendant(
          of: byLogId('controller.print.more.preheat'),
          matching: find.text(pl.commonOff),
        ),
      );
      await tester.pumpAndSettle();
      expect(byLogId('controller.print.more.chamber.more'), findsNothing);
      await closeMore(tester);
      await send(tester);

      expect(capturedBody?['preheat_override'], 'off');
      expect(
        capturedBody?.containsKey('preheat_chamber_target_override'),
        isFalse,
      );
    });

    testWidgets(
      'G-code injection is offered only where the server has snippets',
      (tester) async {
        await pump(tester);
        await openMore(tester);
        await reveal(tester, 'power_off');
        expect(byLogId('controller.print.more.gcode_injection'), findsNothing);
      },
    );

    testWidgets('injection is sent once switched on', (tester) async {
      await pump(
        tester,
        extra: [
          gcodeSnippetModelsProvider.overrideWithValue(
            const AsyncData({'P1S'}),
          ),
        ],
      );

      await openMore(tester);
      await tapMore(tester, 'gcode_injection');
      await closeMore(tester);
      await send(tester);

      expect(capturedBody?['gcode_injection'], isTrue);
    });

    testWidgets('injection for a model with no snippet says so', (
      tester,
    ) async {
      await pump(
        tester,
        extra: [
          gcodeSnippetModelsProvider.overrideWithValue(
            const AsyncData({'H2D'}),
          ),
        ],
      );

      await openMore(tester);
      await tapMore(tester, 'gcode_injection');

      expect(
        find.text(pl.queueEditGcodeInjectionNoSnippet('P1S')),
        findsOneWidget,
      );
    });

    testWidgets('nozzle offset is offered to a printer with two nozzles', (
      tester,
    ) async {
      await pump(
        tester,
        printer: _h2d,
        file: _file(model: 'H2D'),
      );
      await openMore(tester);
      await reveal(tester, 'nozzle_offset');
      expect(byLogId('controller.print.more.nozzle_offset'), findsOneWidget);
    });

    testWidgets('and to no other', (tester) async {
      await pump(tester);
      await openMore(tester);
      await reveal(tester, 'power_off');
      expect(byLogId('controller.print.more.nozzle_offset'), findsNothing);
    });

    testWidgets('asking for the outcome needs a server that offers it', (
      tester,
    ) async {
      await pump(tester);
      await openMore(tester);
      await reveal(tester, 'power_off');
      expect(byLogId('controller.print.more.confirm_outcome'), findsNothing);
    });

    testWidgets('the outcome switch starts from the server default', (
      tester,
    ) async {
      await pump(
        tester,
        extra: [
          queueOutcomeProvider.overrideWithValue(const AsyncData(true)),
          defaultConfirmOutcomeProvider.overrideWithValue(
            const AsyncData(true),
          ),
        ],
      );

      await openMore(tester);
      await reveal(tester, 'confirm_outcome');
      expect(
        find.descendant(
          of: byLogId('controller.print.more.confirm_outcome'),
          matching: find.text(pl.commonOn),
        ),
        findsOneWidget,
      );
      await tester.tap(byLogId('controller.print.more.confirm_outcome'));
      await tester.pumpAndSettle();
      await closeMore(tester);
      await send(tester);

      expect(capturedBody?['confirm_outcome'], isFalse);
    });

    testWidgets('the dialog fits a small window and a large system font', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(
        tester,
        size: const Size(740, 320),
        printer: _h2d,
        file: _file(model: 'H2D'),
        extra: [
          queueOutcomeProvider.overrideWithValue(const AsyncData(true)),
          gcodeSnippetModelsProvider.overrideWithValue(
            const AsyncData({'H2D'}),
          ),
        ],
      );

      await openMore(tester);

      expect(tester.takeException(), isNull);
    });
  });

  group('billing', () {
    const alice = CostCenter(id: 1, name: 'Alice', isPrivate: true);
    const workshop = CostCenter(
      id: 2,
      name: 'Workshop',
      budget: CostCenterBudget.monthly,
      budgetLimit: 100,
      budgetAvailable: 5,
    );

    List<Override> billing(
      FutureOr<List<CostCenter>?> Function() centers, {
      bool on = true,
      JobCost? cost,
    }) => [
      serverUiFlagsProvider.overrideWith(
        (ref) async => {'billing_enabled': on},
      ),
      printableCostCentersProvider.overrideWith(
        (ref) async => on ? await centers() : const [],
      ),
      if (cost != null) jobCostProvider.overrideWith((ref, key) async => cost),
    ];

    testWidgets('the job is booked to the personal centre by default', (
      tester,
    ) async {
      await pump(tester, extra: billing(() => [alice, workshop]));

      expect(
        find.text(
          pl.controllerPrintCostCenter(pl.queueCostCenterPersonal('Alice')),
        ),
        findsOneWidget,
      );
      await send(tester);

      expect(capturedBody?['cost_center_id'], 1);
    });

    testWidgets('another centre can be picked in the dialog', (tester) async {
      await pump(tester, extra: billing(() => [alice, workshop]));

      await tester.tap(byLogId('controller.print.cost_center'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Workshop'));
      await tester.pumpAndSettle();
      await closeMore(tester);
      expect(
        find.text(pl.controllerPrintCostCenter('Workshop')),
        findsOneWidget,
      );
      await send(tester);

      expect(capturedBody?['cost_center_id'], 2);
    });

    testWidgets('a centre with less left than the job says so', (tester) async {
      await pump(
        tester,
        extra: billing(() => [workshop], cost: (total: 10.0, anyPrice: true)),
      );

      expect(find.text(pl.queueInsufficientBudget), findsOneWidget);
    });

    testWidgets('the estimate is shown with the filament', (tester) async {
      await pump(
        tester,
        extra: billing(() => [alice], cost: (total: 1.5, anyPrice: true)),
      );

      expect(
        find.textContaining(pl.queueEstimatedCost('').trim()),
        findsOneWidget,
      );
    });

    testWidgets('without billing no centre is asked for or sent', (
      tester,
    ) async {
      await pump(tester, extra: billing(() => [alice], on: false));

      expect(byLogId('controller.print.cost_center'), findsNothing);
      await send(tester);

      expect(capturedBody?.containsKey('cost_center_id'), isFalse);
    });

    testWidgets('an account with no centre to print on cannot print', (
      tester,
    ) async {
      await pump(tester, extra: billing(() => const []));

      expect(find.text(pl.controllerPrintNoCostCenter), findsOneWidget);
      expect(submitButton(tester).onPressed, isNull);
    });

    testWidgets('a session that may not list its centres is told so', (
      tester,
    ) async {
      await pump(tester, extra: billing(() => null));

      expect(find.text(pl.controllerPrintCostCentersRefused), findsOneWidget);
      expect(find.text(pl.controllerPrintNoCostCenter), findsNothing);
      expect(submitButton(tester).onPressed, isNull);
    });

    testWidgets('waits for the centres to arrive', (tester) async {
      final answer = Completer<List<CostCenter>?>();
      await pump(tester, extra: billing(() => answer.future));
      expect(submitButton(tester).onPressed, isNull);

      answer.complete([alice]);
      await tester.pumpAndSettle();

      expect(submitButton(tester).onPressed, isNotNull);
    });

    testWidgets('a failed read can be retried', (tester) async {
      var reads = 0;
      await pump(
        tester,
        extra: billing(() {
          if (reads++ == 0) throw Exception('offline');
          return [alice];
        }),
      );
      expect(find.text(pl.queueCostCenterLoadFailed), findsOneWidget);
      expect(submitButton(tester).onPressed, isNull);

      await tester.tap(byLogId('controller.print.cost_center_retry'));
      await tester.pumpAndSettle();

      expect(find.text(pl.queueCostCenterLoadFailed), findsNothing);
      expect(submitButton(tester).onPressed, isNotNull);
    });

    // Recorded for `controller_prints_contract_test.dart` to replay on a live
    // server: plate 2 of an archive that asked for its outcome, on a
    // dual-nozzle printer, booked to a centre.
    testWidgets('an archive reprinted from the controller sends this', (
      tester,
    ) async {
      await pump(
        tester,
        printer: _h2d,
        plates: _threePlates,
        draft: archiveQueueDraft(
          const Archive(
            id: 77,
            filename: 'cube.gcode.3mf',
            status: 'completed',
            printName: 'Cube',
            slicedForModel: 'H2D',
            plateId: 2,
            confirmRequested: true,
          ),
        ),
        extra: [
          ...billing(() => [alice, workshop]),
          queueOutcomeProvider.overrideWithValue(const AsyncData(true)),
        ],
      );
      await send(tester);

      expectSentAsRecorded(
        'controller_reprint_archive',
        writesOf(sentRequests),
      );
    });
  });

  group('the mapping dialog', () {
    // A row carries its filament's material in the identifier.
    Finder byLogIdStarting(String id) => find.byWidgetPredicate(
      (w) => w is Semantics && (w.properties.identifier ?? '').startsWith(id),
    );

    Future<void> openMapping(WidgetTester tester) async {
      await tester.tap(byLogId('controller.print.filament').first);
      await tester.pumpAndSettle();
    }

    testWidgets('is a dialog beside a list, not a bottom sheet', (
      tester,
    ) async {
      await pump(tester);

      await openMapping(tester);

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      // The filaments and the way to save them are on one screen.
      expect(byLogIdStarting('queue_mapping.slot'), findsNWidgets(3));
      expect(byLogId('queue_mapping.confirm'), findsOneWidget);
    });

    testWidgets('the close button closes it and changes nothing', (
      tester,
    ) async {
      await pump(tester);
      await openMapping(tester);

      await tester.tap(byLogId('queue_mapping.close'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(byLogId('controller.print.reset_mapping'), findsNothing);
    });

    testWidgets('the slot is picked from a dialog too, and kept', (
      tester,
    ) async {
      await pump(tester);
      await openMapping(tester);

      await tester.tap(byLogIdStarting('queue_mapping.slot').first);
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNWidgets(2));
      expect(find.byType(BottomSheet), findsNothing);

      await tester.tap(byLogIdStarting('queue_mapping.tray_option').last);
      await tester.pumpAndSettle();

      // Only the picker is gone.
      expect(find.byType(Dialog), findsOneWidget);
      await tester.tap(byLogId('queue_mapping.confirm'));
      await tester.pumpAndSettle();
      expect(find.text(pl.controllerPrintManualMapping), findsOneWidget);
    });

    testWidgets('the picker closes with its own button', (tester) async {
      await pump(tester);
      await openMapping(tester);
      await tester.tap(byLogIdStarting('queue_mapping.slot').first);
      await tester.pumpAndSettle();

      await tester.tap(byLogId('queue_mapping.picker_close'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('both dialogs grow with the body on a larger screen', (
      tester,
    ) async {
      Future<double> width(Future<void> Function() open) async {
        await open();
        final box = find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(ScaleToFit),
        );
        final w = tester.getSize(box.first).width;
        await tester.tapAt(const Offset(2, 2));
        await tester.pumpAndSettle();
        return w;
      }

      await pump(tester, size: const Size(1280, 800));
      final mapping = await width(() async {
        await tester.tap(byLogId('controller.print.filament').first);
        await tester.pumpAndSettle();
      });
      final more = await width(() async {
        await tester.tap(byLogId('controller.print.more'));
        await tester.pumpAndSettle();
      });

      // Laid out for 680 and 560 dp, and drawn bigger: the scale is the body's,
      // read inside it, not the 1 the screen's own context would give.
      expect(mapping, greaterThan(680));
      expect(more, greaterThan(560));
    });

    for (final locale in AppLocalizations.supportedLocales) {
      for (final size in const [Size(832, 392), Size(1280, 800)]) {
        testWidgets('keeps its text its size in ${locale.languageCode} at '
            '${size.width.round()}x${size.height.round()}', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await pump(tester, locale: locale, size: size);
          await openMapping(tester);

          expect(tester.takeException(), isNull);
          expectNothingCut(tester, find.byType(Dialog));

          await tester.tap(byLogIdStarting('queue_mapping.slot').first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
