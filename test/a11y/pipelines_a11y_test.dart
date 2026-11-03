import 'dart:async';

import 'package:bambuddy_mobile/core/models/pipeline_run.dart';
import 'package:bambuddy_mobile/core/models/slicer_pipeline.dart';
import 'package:bambuddy_mobile/data/pipelines_repository.dart';
import 'package:bambuddy_mobile/features/pipelines/pipeline_edit_screen.dart';
import 'package:bambuddy_mobile/features/pipelines/pipeline_run_screen.dart';
import 'package:bambuddy_mobile/features/pipelines/pipeline_runs_screen.dart';
import 'package:bambuddy_mobile/features/pipelines/pipelines_providers.dart';
import 'package:bambuddy_mobile/features/pipelines/pipelines_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets for the slicer pipelines: the list and
/// its card menu and delete confirmation, the edit form in every target mode,
/// the runs dashboard with its filter sheet, confirmations and empty or failed
/// states, and the run screen with its pipeline picker and pre-flight report.
/// The harness and the rules are in a11y_harness.dart. The demo seeds two
/// pipelines (1: targeted at the X1C class, 2: no target) and thirty runs on
/// pipeline 1. The save-as-pipeline dialog belongs to the slice form and is
/// covered in slicer_a11y_test.dart.

/// The demo's second pipeline, which has no target yet.
final _untargeted = SlicerPipeline.fromJson(const {
  'id': 2,
  'name': 'Nightly ASA brackets',
  'printer_preset': {'source': 'local', 'id': 'p-x1c-04'},
  'process_preset': {'source': 'local', 'id': 'q-028-draft'},
  'filament_presets': [
    {'source': 'local', 'id': 'f-asa-black'},
  ],
  'target_kind': 'printer_class',
  'fanout_strategy': 'max_parallel',
});

/// The demo's first pipeline, targeted at the X1C class.
final _targeted = SlicerPipeline.fromJson(const {
  'id': 1,
  'name': 'Gridfinity PETG',
  'description': 'Bins and baseplates, 0.20mm, engineering plate.',
  'printer_preset': {'source': 'local', 'id': 'p-x1c-04'},
  'process_preset': {'source': 'local', 'id': 'q-020-std'},
  'filament_presets': [
    {'source': 'local', 'id': 'f-petg-white'},
  ],
  'bed_type': 'Engineering Plate',
  'target_kind': 'printer_class',
  'target_model_class': 'X1C',
  'fanout_strategy': 'max_parallel',
});

/// A pipeline pinned to one printer, which the demo does not seed.
final _pinned = SlicerPipeline.fromJson(const {
  'id': 1,
  'name': 'Gridfinity PETG',
  'printer_preset': {'source': 'local', 'id': 'p-x1c-04'},
  'process_preset': {'source': 'local', 'id': 'q-020-std'},
  'filament_presets': [
    {'source': 'local', 'id': 'f-petg-white'},
  ],
  'target_kind': 'specific_printer',
  'target_printer_id': 1,
  'fanout_strategy': 'max_parallel',
});

Future<void> _tapMenuItem(WidgetTester tester, String id) async {
  await tester.tap(byLogId('pipelines.actions').first);
  await tester.pumpAndSettle();
  await tester.tap(byLogId(id));
  await tester.pumpAndSettle();
}

Future<void> _pickPipeline(WidgetTester tester, String name) async {
  await tester.tap(byLogId('pipeline_run.pick'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

void main() {
  // --- The list ---

  a11ySurface(
    'pipelines',
    home: () => const PipelinesScreen(),
    shows: find.text('Gridfinity PETG'),
  );

  a11ySurface(
    'pipelines, empty',
    overrides: [pipelinesProvider.overrideWith((ref) async => const [])],
    home: () => const PipelinesScreen(),
    shows: find.textContaining(pl.pipelinesEmpty),
  );

  a11ySurface(
    'pipelines, load failed',
    overrides: [
      pipelinesProvider.overrideWith(
        (ref) async => throw StateError('unreachable'),
      ),
    ],
    home: () => const PipelinesScreen(),
    shows: find.text(pl.retry),
  );

  a11ySurface(
    'pipelines, a printer pinned',
    overrides: [
      pipelinesProvider.overrideWith((ref) async => [_pinned]),
    ],
    home: () => const PipelinesScreen(),
    shows: find.text('Gridfinity PETG'),
  );

  a11ySurface(
    'pipelines, card menu',
    home: () => const PipelinesScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('pipelines.actions').first);
      await tester.pumpAndSettle();
    },
    shows: byLogId('pipelines.delete'),
  );

  a11ySurface(
    'pipelines, delete confirmation',
    home: () => const PipelinesScreen(),
    arrange: (tester) => _tapMenuItem(tester, 'pipelines.delete'),
    shows: find.byType(AlertDialog),
  );

  // --- The edit form ---

  a11ySurface(
    'pipeline edit, class target',
    home: () => PipelineEditScreen(pipeline: _targeted),
    shows: byLogId('pipeline_edit.save'),
  );

  a11ySurface(
    'pipeline edit, no target yet',
    home: () => PipelineEditScreen(pipeline: _untargeted),
    shows: byLogId('pipeline_edit.save'),
  );

  a11ySurface(
    'pipeline edit, class select open',
    home: () => PipelineEditScreen(pipeline: _targeted),
    arrange: (tester) async {
      await tester.tap(byLogId('pipeline_edit.class'));
      await tester.pumpAndSettle();
    },
    shows: find.text(pl.pipelineTargetNone),
  );

  a11ySurface(
    'pipeline edit, fanout select open',
    home: () => PipelineEditScreen(pipeline: _targeted),
    arrange: (tester) async {
      await tester.tap(byLogId('pipeline_edit.fanout'));
      await tester.pumpAndSettle();
    },
    shows: byLogId('pipeline_edit.fanout_option'),
  );

  a11ySurface(
    'pipeline edit, printer target',
    home: () => PipelineEditScreen(pipeline: _pinned),
    shows: byLogId('pipeline_edit.printer'),
  );

  a11ySurface(
    'pipeline edit, printer select open',
    home: () => PipelineEditScreen(pipeline: _pinned),
    arrange: (tester) async {
      await tester.tap(byLogId('pipeline_edit.printer'));
      await tester.pumpAndSettle();
    },
    shows: find.text(pl.pipelineTargetNone),
  );

  a11ySurface(
    'pipeline edit, name cleared',
    home: () => PipelineEditScreen(pipeline: _targeted),
    arrange: (tester) async {
      await tester.enterText(byLogId('pipeline_edit.name'), '');
      await tester.pumpAndSettle();
    },
    shows: byLogId('pipeline_edit.save'),
  );

  // --- The runs dashboard ---

  a11ySurface(
    'pipeline runs',
    overrides: [_quietRuns],
    home: () => const PipelineRunsScreen(),
    shows: find.text('Gridfinity PETG'),
  );

  a11ySurface(
    'pipeline runs, everything loaded',
    overrides: [pipelineRunsProvider.overrideWith(_AllRuns.new)],
    home: () => const PipelineRunsScreen(),
    shows: find.text('Gridfinity PETG'),
  );

  a11ySurface(
    'pipeline runs, empty',
    overrides: [pipelineRunsProvider.overrideWith(_NoRuns.new)],
    home: () => const PipelineRunsScreen(),
    shows: find.text(pl.pipelineRunsEmpty),
  );

  a11ySurface(
    'pipeline runs, load failed',
    overrides: [pipelineRunsProvider.overrideWith(_FailingRuns.new)],
    home: () => const PipelineRunsScreen(),
    shows: find.text(pl.retry),
  );

  // The filter names a pipeline none of the demo's runs belongs to.
  a11ySurface(
    'pipeline runs, filter matches nothing',
    overrides: [
      _quietRuns,
      pipelineRunFilterSeedProvider.overrideWithValue(
        const PipelineRunFilter(pipelineId: 2),
      ),
    ],
    home: () => const PipelineRunsScreen(),
    shows: find.text(pl.pipelineRunsNoneMatch),
  );

  a11ySurface(
    'pipeline runs, filter sheet',
    overrides: [_quietRuns],
    home: () => const PipelineRunsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('pipeline_runs.filter'));
      await tester.pumpAndSettle();
    },
    shows: byLogId('pipeline_runs.filter_done'),
  );

  a11ySurface(
    'pipeline runs, filter sheet with a filter set',
    overrides: [
      _quietRuns,
      pipelineRunFilterSeedProvider.overrideWithValue(
        const PipelineRunFilter(pipelineId: 1, status: 'completed'),
      ),
    ],
    home: () => const PipelineRunsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('pipeline_runs.filter'));
      await tester.pumpAndSettle();
    },
    shows: byLogId('pipeline_runs.filter_clear'),
  );

  a11ySurface(
    'pipeline runs, status select open',
    overrides: [_quietRuns],
    home: () => const PipelineRunsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('pipeline_runs.filter'));
      await tester.pumpAndSettle();
      await tester.tap(byLogId('pipeline_runs.filter_status'));
      await tester.pumpAndSettle();
    },
    shows: byLogId('pipeline_runs.filter_done'),
  );

  a11ySurface(
    'pipeline runs, cancel confirmation',
    overrides: [_quietRuns],
    home: () => const PipelineRunsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('pipeline_runs.cancel').first);
      await tester.pumpAndSettle();
    },
    shows: find.text(pl.pipelineRunCancelConfirm),
  );

  a11ySurface(
    'pipeline runs, clear confirmation',
    overrides: [_quietRuns],
    home: () => const PipelineRunsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('pipeline_runs.clear'));
      await tester.pumpAndSettle();
    },
    shows: find.text(pl.pipelineRunsClearConfirm),
  );

  // --- Running a pipeline on a file ---

  a11ySurface(
    'pipeline run',
    home: () => _runLauncher(),
    arrange: a11yOpenLauncher,
    shows: byLogId('pipeline_run.pick'),
  );

  a11ySurface(
    'pipeline run, picker sheet',
    home: () => _runLauncher(),
    arrange: (tester) async {
      await a11yOpenLauncher(tester);
      await tester.tap(byLogId('pipeline_run.pick'));
      await tester.pumpAndSettle();
    },
    shows: byLogId('pipeline_run.option'),
  );

  a11ySurface(
    'pipeline run, class target checked',
    home: () => _runLauncher(),
    arrange: (tester) async {
      await a11yOpenLauncher(tester);
      await _pickPipeline(tester, 'Gridfinity PETG');
    },
    shows: byLogId('pipeline_run.copies'),
  );

  a11ySurface(
    'pipeline run, pipeline without a target',
    home: () => _runLauncher(),
    arrange: (tester) async {
      await a11yOpenLauncher(tester);
      await _pickPipeline(tester, 'Nightly ASA brackets');
    },
    shows: find.text(pl.pipelineNeedsTarget),
  );

  // Printer 5 loads PLA only, so the demo's pre-flight refuses an ASA pipeline
  // pinned to it and the run button turns into "run anyway".
  a11ySurface(
    'pipeline run, pre-flight blocked',
    home: () => _runLauncher(),
    arrange: (tester) async {
      await a11yOpenLauncher(tester);
      final context = tester.element(byLogId('pipeline_run.pick'));
      final providers = ProviderScope.containerOf(context);
      // Fired, not awaited: the test clock only moves when frames are pumped.
      unawaited(
        providers
            .read(pipelinesRepositoryProvider)
            .update(
              2,
              targetKind: PipelineTargetKind.specificPrinter,
              targetPrinterId: 5,
            ),
      );
      await a11ySettle(tester, const Duration(seconds: 1));
      providers.invalidate(pipelinesProvider);
      await a11ySettle(tester, const Duration(seconds: 1));
      await _pickPipeline(tester, 'Nightly ASA brackets');
    },
    shows: find.text(pl.pipelineRunAnyway),
  );
}

/// The demo's first page of runs, minus the two requests the screen would
/// send on its own: its 4 s poll (a run in flight makes it refresh) and the
/// next page the scroll pass asks for at the end of the list. Either is still
/// on the demo adapter's 120 ms timer when the test ends, which trips the
/// pending-timer check. Everything the screen draws is the demo's own.
class _QuietRuns extends PipelineRunsNotifier {
  @override
  Future<bool> refreshLoaded() async => true;

  @override
  Future<void> loadMore() async {}
}

/// Every demo run in one page, so the list ends in the "showing all" footer
/// and the scroll pass has no next page to ask for.
class _AllRuns extends _QuietRuns {
  @override
  Future<PipelineRunsView> build() async {
    final page = await ref
        .read(pipelinesRepositoryProvider)
        .runs(limit: PipelinesRepository.maxPageSize);
    return PipelineRunsView(runs: page.runs, total: page.total);
  }
}

final _quietRuns = pipelineRunsProvider.overrideWith(_QuietRuns.new);

class _NoRuns extends PipelineRunsNotifier {
  @override
  Future<PipelineRunsView> build() async => const PipelineRunsView();
}

class _FailingRuns extends PipelineRunsNotifier {
  @override
  Future<PipelineRunsView> build() async => throw StateError('unreachable');
}

/// A screen with one button that opens the pipeline run screen on a library file.
Widget _runLauncher() => A11yLauncher(
  (context) => showPipelineRunScreen(
    context,
    source: const PipelineSource.libraryFile(6),
    sourceName: 'Crimper 24 mm.3mf',
  ),
);
