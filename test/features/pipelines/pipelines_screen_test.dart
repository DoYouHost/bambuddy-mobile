import 'package:bambuddy_mobile/core/models/pipeline_run.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/slicer_pipeline.dart';
import 'package:bambuddy_mobile/core/models/slicer_preset.dart';
import 'package:bambuddy_mobile/features/pipelines/pipeline_eligibility_view.dart';
import 'package:bambuddy_mobile/features/pipelines/pipelines_providers.dart';
import 'package:bambuddy_mobile/features/pipelines/pipelines_screen.dart';
import 'package:bambuddy_mobile/features/slicer/slice_providers.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

SlicerPipeline _pipeline({
  int id = 7,
  String name = 'Gridfinity PETG',
  String? description,
  PipelineTargetKind targetKind = PipelineTargetKind.printerClass,
  int? targetPrinterId,
  String? targetModelClass = 'X1C',
}) =>
    SlicerPipeline(
      id: id,
      name: name,
      description: description,
      printerPreset: const PresetRef(source: 'local', id: '3'),
      processPreset: const PresetRef(source: 'local', id: '9'),
      filamentPresets: const [PresetRef(source: 'local', id: '11')],
      bedType: 'Engineering Plate',
      targetKind: targetKind,
      targetPrinterId: targetPrinterId,
      targetModelClass: targetModelClass,
    );

const _presets = UnifiedPresets(
  printers: [SlicerPreset(source: 'local', id: '3', name: 'X1C 0.4')],
  processes: [SlicerPreset(source: 'local', id: '9', name: '0.20mm Standard')],
  filaments: [SlicerPreset(source: 'local', id: '11', name: 'Generic PETG')],
);

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('pl'));
  });

  Future<void> pump(
    WidgetTester tester, {
    List<SlicerPipeline> pipelines = const [],
    bool canWrite = true,
    List<Printer> printers = const [],
    TextScaler scaler = TextScaler.noScaling,
    Size size = const Size(360, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        noServerProfileOverride,
        pipelinesProvider.overrideWith((ref) async => pipelines),
        canWritePipelinesProvider.overrideWith((ref) async => canWrite),
        canRunPipelinesProvider.overrideWith((ref) async => true),
        pipelinesSupportedProvider.overrideWith((ref) async => true),
        pipelineTargetPrintersProvider.overrideWith((ref) async => printers),
        pipelinePrinterClassesProvider.overrideWith((ref) async => ['X1C']),
        slicerPresetsProvider.overrideWith((ref) async => _presets),
      ],
      child: plApp(
        const PipelinesScreen(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scaler),
          child: child!,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('the pipeline card', () {
    testWidgets('names what the bundle holds and what it runs on',
        (tester) async {
      await pump(tester, pipelines: [_pipeline()]);

      expect(find.text('Gridfinity PETG'), findsOneWidget);
      expect(find.textContaining('X1C 0.4'), findsOneWidget);
      expect(find.textContaining('0.20mm Standard'), findsOneWidget);
      expect(find.textContaining('Generic PETG'), findsOneWidget);
    });

    testWidgets('an untargeted pipeline says so instead of offering a run',
        (tester) async {
      // What every pipeline saved from the slice form looks like: the create
      // schema carries no target, so this is the normal first state.
      await pump(tester, pipelines: [
        _pipeline(targetModelClass: null),
      ]);

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('a pinned printer that is gone is named by its id',
        (tester) async {
      // Better than an empty line: the id is the only handle left on a printer
      // the fleet no longer lists.
      await pump(
        tester,
        pipelines: [
          _pipeline(
            targetKind: PipelineTargetKind.specificPrinter,
            targetPrinterId: 41,
            targetModelClass: null,
          ),
        ],
      );

      expect(find.textContaining('41'), findsOneWidget);
    });

    testWidgets('a session that may not author sees no edit or delete',
        (tester) async {
      await pump(tester, pipelines: [_pipeline()], canWrite: false);

      expect(find.byIcon(Icons.more_vert), findsNothing);
      expect(find.byIcon(Icons.history_rounded), findsWidgets,
          reason: 'reading the history is not authoring');
    });

    testWidgets('a long name still gets most of the row on a 360 dp screen',
        (tester) async {
      // Three action buttons sit beside the name. If they crowd it the name
      // ellipsizes early, and the name is the only thing telling two pipelines
      // apart.
      await pump(tester, pipelines: [
        _pipeline(name: 'Production PETG 0.6 nozzle, engineering plate'),
      ]);

      final name = tester.getSize(
          find.text('Production PETG 0.6 nozzle, engineering plate'));
      expect(name.width, greaterThan(180),
          reason: 'the title keeps more than half of a 360 dp row');
    });

    testWidgets('authoring is behind the overflow menu, not beside the name',
        (tester) async {
      await pump(tester, pipelines: [_pipeline()]);

      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text(l10n.pipelineEditTitle), findsOneWidget);
      expect(find.text(l10n.pipelineDelete), findsOneWidget);
    });

    testWidgets('every row grows with the system font size', (tester) async {
      // `RichText` takes `TextScaler.noScaling` by default, so these rows —
      // the presets, the plate, each filament slot — ignored the setting while
      // the name above them grew. `Text.rich` reads the ambient MediaQuery.
      double heightOf(String needle) => tester
          .getSize(find.ancestor(
            of: find.textContaining(needle),
            matching: find.byType(Padding),
          ).first)
          .height;

      await pump(tester, pipelines: [_pipeline()]);
      final plain = heightOf('0.20mm Standard');

      await pump(
        tester,
        pipelines: [_pipeline()],
        scaler: const TextScaler.linear(2),
      );
      final scaled = heightOf('0.20mm Standard');

      expect(scaled, greaterThan(plain * 1.5),
          reason: 'a row that ignores the scaler stays the same height');
    });
  });

  group('what a screen reader gets', () {
    testWidgets('a printer verdict is one utterance, name and all',
        (tester) async {
      // The icon carries the whole verdict — without a label on it a reader
      // hears the printer's name and nothing about whether it can take the job.
      await tester.pumpWidget(plApp(Scaffold(
        body: EligibilityView(
          report: EligibilityReport(
            ok: true,
            targetKind: PipelineTargetKind.printerClass,
            printerReports: const [
              PerPrinterReport(printerId: 1, printerName: 'X1C left', ok: true),
              PerPrinterReport(
                printerId: 2,
                printerName: 'X1C right',
                ok: false,
                issues: [
                  EligibilityIssue(
                    kind: EligibilityIssueKind.printerOffline,
                    rawKind: 'printer_offline',
                  ),
                ],
              ),
            ],
          ),
        ),
      )));
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
          tester.element(find.byType(EligibilityView)));

      expect(
        tester.getSemantics(find.text('X1C left')),
        matchesSemantics(label: '${l10n.pipelineEligible}\nX1C left'),
      );
      expect(
        tester.getSemantics(find.text('X1C right')),
        matchesSemantics(label: '${l10n.pipelineIneligible}\nX1C right'),
      );
    });

    testWidgets("each printer's problems sit under that printer", (tester) async {
      // Pooled into one list, three printers with the same complaint read as
      // three anonymous complaints and the operator cannot tell which is which.
      await tester.pumpWidget(plApp(Scaffold(
        body: EligibilityView(
          report: EligibilityReport(
            ok: true,
            targetKind: PipelineTargetKind.printerClass,
            printerReports: const [
              PerPrinterReport(printerId: 1, printerName: 'Alpha', ok: true),
              PerPrinterReport(
                printerId: 2,
                printerName: 'Beta',
                ok: false,
                issues: [
                  EligibilityIssue(
                    kind: EligibilityIssueKind.printerOffline,
                    rawKind: 'printer_offline',
                  ),
                ],
              ),
            ],
          ),
        ),
      )));
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
          tester.element(find.byType(EligibilityView)));

      final offline = find.text(l10n.pipelineIssuePrinterOffline);
      expect(offline, findsOneWidget);
      // Indented past the printer rows, which is what says it belongs to one.
      expect(
        tester.getTopLeft(offline).dx,
        greaterThan(tester.getTopLeft(find.text('Beta')).dx),
      );
    });
  });

  group('the runs filter sheet', () {
    Future<void> openFilters(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.history_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.filter_list_rounded));
      await tester.pumpAndSettle();
    }

    testWidgets('fits a short screen at a doubled font size', (tester) async {
      // Three combos, each with a two-line helper, plus a title and two
      // actions. As an unscrollable Column that is a RenderFlex overflow and
      // the actions go off the bottom of the glass.
      await pump(
        tester,
        pipelines: [_pipeline()],
        scaler: const TextScaler.linear(2),
        size: const Size(360, 640),
      );
      await openFilters(tester);

      expect(tester.takeException(), isNull,
          reason: 'the sheet must scroll rather than overflow');
    });

    testWidgets('the actions stay reachable at that size', (tester) async {
      // Not just "no exception": the point is that Done can still be pressed.
      await pump(
        tester,
        pipelines: [_pipeline()],
        scaler: const TextScaler.linear(2),
        size: const Size(360, 640),
      );
      await openFilters(tester);

      // The pipeline combo identifies the sheet; the screen behind it has
      // FilledButtons of its own, so a bare byType finder is ambiguous.
      final sheet = find.byType(DropdownMenu<int?>);
      expect(sheet, findsOneWidget, reason: 'the sheet is open');

      final done = find.widgetWithText(FilledButton, l10n.pipelineRunsDone);
      await tester.ensureVisible(done);
      await tester.pumpAndSettle();
      await tester.tap(done);
      await tester.pumpAndSettle();

      expect(sheet, findsNothing, reason: 'Done closed the sheet');
    });
  });
}
