import 'dart:io';

import 'package:bambuddy_mobile/core/models/library_file.dart';
import 'package:bambuddy_mobile/core/models/library_folder.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/controller/controller_files.dart';
import 'package:bambuddy_mobile/features/controller/controller_heat.dart';
import 'package:bambuddy_mobile/features/controller/controller_overview.dart';
import 'package:bambuddy_mobile/features/controller/controller_saver.dart';
import 'package:bambuddy_mobile/features/controller/controller_screen.dart';
import 'package:bambuddy_mobile/features/controller/scale_to_fit.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/files/file_manager_providers.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// The controller never shrinks text to make it fit: where it did not fit the
/// layout gives way, so equal things are one size. Measured with the app's own
/// fonts, in every language, at the smallest screen and a tablet, at the normal
/// system font and at 1.3.
const _threeHeaters = {
  'nozzle': 250.0,
  'nozzle_target': 250.0,
  'bed': 70.0,
  'bed_target': 70.0,
  'chamber': 41.0,
};
const _fourHeaters = {
  'nozzle': 250.0,
  'nozzle_target': 250.0,
  'nozzle_2': 50.0,
  'bed': 70.0,
  'bed_target': 70.0,
  'chamber': 41.0,
};

PrinterStatus _status(Map<String, double> temps, {bool job = true}) =>
    PrinterStatus(
      id: 1,
      connected: true,
      state: job ? 'RUNNING' : 'IDLE',
      progress: job ? 56 : null,
      remainingTime: job ? 58 : null,
      layerNum: job ? 182 : null,
      totalLayers: job ? 338 : null,
      currentPrint: job ? 'ring_petg_with_a_rather_long_file_name.3mf' : null,
      speedLevel: 2,
      temperatures: temps,
    );

/// A library with a folder and four files, named at the length that stresses a tile.
class _FixedLibrary extends FileManagerNotifier {
  /// The query is applied over what the library holds, without a fetch.
  @override
  Future<void> setQuery(String q) async {
    final current = state.requireValue;
    state = AsyncData(current.copyWith(query: q, allFiles: current.files));
  }

  @override
  Future<FileManagerState> build() async => FileManagerState(
    allFolders: const [
      LibraryFolder(
        id: 1,
        name: 'Folder with a rather long name for a tile',
        fileCount: 12,
      ),
    ],
    files: [
      for (final (i, model) in [
        'H2D',
        'P1S',
        null,
        'Bambu Lab X1 Carbon',
      ].indexed)
        LibraryFile(
          id: i + 1,
          filename: 'a_rather_long_file_name_$i.gcode.3mf',
          fileType: 'gcode',
          fileSize: 4096,
          printCount: 0,
          slicedForModel: model,
          printTimeSeconds: 123456,
          filamentUsedGrams: 1234.5,
        ),
      const LibraryFile(
        id: 9,
        filename: 'raw_model_file.stl',
        fileType: 'stl',
        fileSize: 4096,
        printCount: 0,
      ),
    ],
  );
}

void main() {
  setUpAll(loadAppFonts);

  test('only the screen\'s own scale and the keypad\'s scale a FittedBox', () {
    // A FittedBox shrinks whatever is in it to fit, so two things of one kind
    // can end up two sizes. The body is scaled as a whole by `ScaleToFit`, and
    // the keypad, which lives in a route of its own, by the same factor.
    final offenders = [
      for (final file in Directory('lib/features/controller').listSync())
        if (file is File &&
            file.path.endsWith('.dart') &&
            file.uri.pathSegments.last != 'scale_to_fit.dart' &&
            file.uri.pathSegments.last != 'controller_heat.dart' &&
            file.readAsStringSync().contains(RegExp(r'FittedBox\(')))
          file.path,
    ];

    expect(offenders, isEmpty);

    // controller_heat.dart holds the keypad, so it may have one, and only there.
    final heat = File(
      'lib/features/controller/controller_heat.dart',
    ).readAsStringSync();
    expect(RegExp(r'FittedBox\(').allMatches(heat), hasLength(1));
    expect(
      heat.indexOf('FittedBox('),
      greaterThan(heat.indexOf('class _Numpad')),
    );
  });

  Future<void> pump(
    WidgetTester tester, {
    required Locale locale,
    required Size size,
    required double textScale,
    required Widget child,
    required PrinterStatus status,
    String name = 'Pracownia X1C numer dwa',
    List<Override> extra = const [],
  }) async {
    useLogicalWindow(tester, size);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    SharedPreferences.setMockInitialValues({
      'controller_prefs': '{"saver_after_minutes":1,"keep_awake":true}',
    });
    final sp = await SharedPreferences.getInstance();
    mockImmersiveChannels(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          noServerProfileOverride,
          inertSmartPlugsOverride,
          fixedDashboardOverride(
            DashboardState(
              printers: [
                PrinterWithStatus(
                  printer: Printer(id: 1, name: name, model: 'H2D'),
                  status: status,
                ),
              ],
            ),
          ),
          inertStatusesOverride,
          ...extra,
        ],
        child: MaterialApp(
          theme: buildDashThemeData(Brightness.dark, brand: bambuddyBrand),
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('fan names that fit are shown whole', (tester) async {
    // Three fan cards leave a name 150 dp or so: the English ones fit.
    await pump(
      tester,
      locale: const Locale('en'),
      size: const Size(832, 392),
      textScale: 1,
      child: const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(16),
          child: ScaleToFit(child: ControllerHeat(printerId: 1)),
        ),
      ),
      status: const PrinterStatus(
        id: 1,
        connected: true,
        state: 'IDLE',
        coolingFanSpeed: 70,
        bigFan1Speed: 40,
        bigFan2Speed: 20,
        temperatures: _threeHeaters,
      ),
    );

    final en = lookupAppLocalizations(const Locale('en'));
    for (final name in [
      en.ctrlFanPartLabel,
      en.ctrlFanAuxLabel,
      en.ctrlFanChamberLabel,
    ]) {
      // The last: "Chamber" is also the heater card's title above.
      final paragraph =
          tester.renderObject(find.text(name).last) as RenderParagraph;
      expect(paragraph.didExceedMaxLines, isFalse, reason: name);
    }
  });

  testWidgets('tabs that do not fit scroll, and the last can be reached', (
    tester,
  ) async {
    await pump(
      tester,
      locale: const Locale('de'),
      size: const Size(520, 360),
      textScale: 1.3,
      child: const ControllerScreen(printerId: 1),
      status: _status(_threeHeaters),
    );

    final bar = find.descendant(
      of: find.byType(ControllerScreen),
      matching: find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      ),
    );
    expect(bar, findsOneWidget);
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: bar, matching: find.byType(Scrollable)),
        )
        .position;
    expect(position.maxScrollExtent, greaterThan(0), reason: 'does not fit');

    // The last tab is out of view, then scrolled to, at the same size as ever.
    final last = byLogId(ControllerTab.values.last.logId);
    final before = tester.getSize(last);
    await tester.ensureVisible(last);
    await tester.pump();
    expect(position.pixels, greaterThan(0));
    expect(tester.getSize(last), before);
    expect(tester.takeException(), isNull);
  });

  for (final locale in AppLocalizations.supportedLocales) {
    for (final size in const [Size(832, 392), Size(1280, 800)]) {
      for (final textScale in const [1.0, 1.3]) {
        final where =
            '${locale.languageCode} at ${size.width.round()}x${size.height.round()}, '
            'font $textScale';

        testWidgets('the Files tab keeps its text its size in $where', (
          tester,
        ) async {
          await pump(
            tester,
            locale: locale,
            size: size,
            textScale: textScale,
            extra: [fileManagerProvider.overrideWith(_FixedLibrary.new)],
            child: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: ScaleToFit(child: ControllerFiles(printerId: 1)),
              ),
            ),
            status: _status(_threeHeaters, job: false),
          );
          await tester.pump();
          await tester.pump();

          expect(
            find.descendant(
              of: find.byType(ControllerFiles),
              matching: find.byType(FittedBox),
            ),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
          for (final e
              in find
                  .descendant(
                    of: find.byType(ControllerFiles),
                    matching: find.byType(Text),
                  )
                  .evaluate()) {
            final paragraph = e.renderObject! as RenderParagraph;
            final text = paragraph.text.toPlainText();
            // Server data (names, the model a file was sliced for) may be long.
            if (text.contains('name') ||
                text.contains('Bambu') ||
                text.contains('.stl')) {
              continue;
            }
            expect(
              paragraph.didExceedMaxLines,
              isFalse,
              reason: '"$text" is cut short',
            );
          }
        });

        testWidgets('the file dialog keeps its text its size in $where', (
          tester,
        ) async {
          await pump(
            tester,
            locale: locale,
            size: size,
            textScale: textScale,
            extra: [fileManagerProvider.overrideWith(_FixedLibrary.new)],
            child: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: ScaleToFit(child: ControllerFiles(printerId: 1)),
              ),
            ),
            status: _status(_threeHeaters, job: false),
          );
          await tester.pump();
          await tester.pump();

          // The printer is an H2D: the second file is sliced for a P1S, so its
          // dialog carries the longest line the dialog can have, and the last
          // file is a model, which has another.
          for (final name in [
            'a_rather_long_file_name_1.gcode.3mf',
            'raw_model_file.stl',
          ]) {
            await tester.tap(find.text(name));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));

            final dialog = find.byType(Dialog);
            expect(dialog, findsOneWidget, reason: name);
            expect(tester.takeException(), isNull, reason: name);
            for (final e
                in find
                    .descendant(of: dialog, matching: find.byType(Text))
                    .evaluate()) {
              final paragraph = e.renderObject! as RenderParagraph;
              final text = paragraph.text.toPlainText();
              if (text.contains('name') || text.contains('.stl')) continue;
              expect(
                paragraph.didExceedMaxLines,
                isFalse,
                reason: '"$text" is cut short',
              );
              // A button says its word on one line.
              final words = lookupAppLocalizations(locale);
              if (text == words.fmPrint || text == words.fmDelete) {
                expect(
                  paragraph.getBoxesForSelection(
                    TextSelection(baseOffset: 0, extentOffset: text.length),
                  ),
                  hasLength(1),
                  reason: '"$text" wraps',
                );
              }
            }
            await tester.tap(byLogId('controller.files.dialog.close'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
          }
        });

        testWidgets('the search keeps its text its size in $where', (
          tester,
        ) async {
          await pump(
            tester,
            locale: locale,
            size: size,
            textScale: textScale,
            extra: [fileManagerProvider.overrideWith(_FixedLibrary.new)],
            child: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: ScaleToFit(child: ControllerFiles(printerId: 1)),
              ),
            ),
            status: _status(_threeHeaters, job: false),
          );
          await tester.pump();
          await tester.pump();

          await tester.tap(byLogId('controller.files.search'));
          await tester.pump();
          await tester.pump();
          expect(find.byType(TextField), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.enterText(find.byType(TextField), 'a_rather_long');
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pump();
          await tester.pump();

          // The chip is a server-free string, but it shares the card with the
          // path and the order: nothing overflows.
          expect(byLogId('controller.files.search_chip'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });

        testWidgets('the Overview keeps its text its size in $where', (
          tester,
        ) async {
          for (final temps in [_threeHeaters, _fourHeaters]) {
            await pump(
              tester,
              locale: locale,
              size: size,
              textScale: textScale,
              child: const Scaffold(
                body: Padding(
                  padding: EdgeInsets.all(16),
                  child: ScaleToFit(child: ControllerOverview(printerId: 1)),
                ),
              ),
              status: _status(temps),
            );

            expect(
              find.descendant(
                of: find.byType(ControllerOverview),
                matching: find.byType(FittedBox),
              ),
              findsNothing,
            );
            expect(tester.takeException(), isNull, reason: '$temps');
            for (final e
                in find
                    .descendant(
                      of: find.byType(ControllerOverview),
                      matching: find.byType(Text),
                    )
                    .evaluate()) {
              final paragraph = e.renderObject! as RenderParagraph;
              final text = paragraph.text.toPlainText();
              if (text.endsWith('.3mf')) continue; // server data, may be long
              expect(
                paragraph.didExceedMaxLines,
                isFalse,
                reason: '"$text" is cut short',
              );
            }
          }
        });

        testWidgets(
          'four fans and four heaters are cut only in the fan names in $where',
          (tester) async {
            // The P2S with both accessory kits: four fan cards in a row, the
            // enclosure one named "Exhaust".
            await pump(
              tester,
              locale: locale,
              size: size,
              textScale: textScale,
              child: const Scaffold(
                body: Padding(
                  padding: EdgeInsets.all(16),
                  child: ScaleToFit(child: ControllerHeat(printerId: 1)),
                ),
              ),
              status: const PrinterStatus(
                id: 1,
                connected: true,
                state: 'IDLE',
                coolingFanSpeed: 70,
                leftAuxFanSpeed: 30,
                bigFan1Speed: 40,
                bigFan2Speed: 20,
                exhaustFanPresent: true,
                temperatures: _fourHeaters,
              ),
            );

            for (final id in [
              'controller.fan.part',
              'controller.fan.aux2',
              'controller.fan.aux',
              'controller.fan.chamber',
            ]) {
              expect(byLogId(id), findsOneWidget, reason: id);
            }
            // A fan's name ends in an ellipsis where it does not fit; nothing
            // else on the Heat tab is cut.
            final l10n = lookupAppLocalizations(locale);
            final names = {
              l10n.ctrlFanPartLabel,
              l10n.ctrlFanAux2Label,
              l10n.ctrlFanAuxLabel,
              l10n.ctrlFanExhaustLabel,
              l10n.ctrlFanChamberLabel,
            };
            for (final e
                in find
                    .descendant(
                      of: find.byType(ControllerHeat),
                      matching: find.byType(Text),
                    )
                    .evaluate()) {
              final paragraph = e.renderObject! as RenderParagraph;
              final text = paragraph.text.toPlainText();
              if (names.contains(text)) {
                expect(
                  paragraph.overflow,
                  TextOverflow.ellipsis,
                  reason: '"$text" is cut with an ellipsis, not clipped',
                );
                continue;
              }
              expect(
                paragraph.didExceedMaxLines,
                isFalse,
                reason: '"$text" is cut short',
              );
            }
            expect(tester.takeException(), isNull);
          },
        );

        testWidgets('the top bar keeps its text its size in $where', (
          tester,
        ) async {
          await pump(
            tester,
            locale: locale,
            size: size,
            textScale: textScale,
            child: const ControllerScreen(printerId: 1),
            status: _status(_threeHeaters),
          );

          // The body's own scale is the one FittedBox; the tabs, the name and
          // the state are not scaled.
          expect(
            find.descendant(
              of: find.byType(ControllerScreen),
              matching: find.byType(FittedBox),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        });

        for (final job in [true, false]) {
          testWidgets(
            'the saver keeps its text its size, ${job ? 'with' : 'without'} '
            'a job, in $where',
            (tester) async {
              await pump(
                tester,
                locale: locale,
                size: size,
                textScale: textScale,
                child: const ControllerSaverHost(
                  printerId: 1,
                  child: Scaffold(body: SizedBox()),
                ),
                status: _status(_threeHeaters, job: job),
              );
              await tester.pump(const Duration(seconds: 62));

              expect(find.byType(ControllerSaver), findsOneWidget);
              expect(
                find.descendant(
                  of: find.byType(ControllerSaver),
                  matching: find.byType(FittedBox),
                ),
                findsNothing,
              );
              // Nothing runs out of its box, with a long name and the longest
              // language in it.
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  }
}
