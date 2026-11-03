import 'package:bambuddy_mobile/core/models/pipeline_run.dart';
import 'package:bambuddy_mobile/core/models/slicer_pipeline.dart';
import 'package:bambuddy_mobile/data/pipelines_repository.dart';
import 'package:bambuddy_mobile/features/pipelines/pipeline_edit_screen.dart';
import 'package:bambuddy_mobile/features/pipelines/pipeline_run_screen.dart';
import 'package:bambuddy_mobile/features/pipelines/pipelines_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';

/// A server answer the app cannot read: the write fails with something that is
/// not an `AppApiException`.
class _UnreadablePipelines extends PipelinesRepository {
  _UnreadablePipelines() : super(Dio());

  @override
  Future<SlicerPipeline> update(
    int pipelineId, {
    String? name,
    String? description,
    PresetRef? printerPreset,
    PresetRef? processPreset,
    List<PresetRef>? filamentPresets,
    String? bedType,
    PipelineTargetKind? targetKind,
    int? targetPrinterId,
    String? targetModelClass,
    FanoutStrategy? fanoutStrategy,
  }) async => throw StateError('unreadable answer');

  @override
  Future<EligibilityReport> checkEligibility(
    int pipelineId, {
    required PipelineSource source,
  }) async => const EligibilityReport(ok: true);

  @override
  Future<PipelineRun> run(
    int pipelineId, {
    required PipelineSource source,
    int copies = 1,
    bool force = false,
  }) async => throw StateError('unreadable answer');
}

final _pipeline = SlicerPipeline.fromJson(const {
  'id': 1,
  'name': 'Gridfinity PETG',
  'printer_preset': {'source': 'local', 'id': 'p-x1c-04'},
  'process_preset': {'source': 'local', 'id': 'q-020-std'},
  'filament_presets': [
    {'source': 'local', 'id': 'f-petg-white'},
  ],
  'target_kind': 'printer_class',
  'target_model_class': 'X1C',
  'fanout_strategy': 'max_parallel',
});

void main() {
  testWidgets('a run that fails with an unexpected error unlocks the screen, '
      'and still reports it', (tester) async {
    await pumpPhone(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showPipelineRunScreen(
              context,
              source: const PipelineSource.archive(5),
              sourceName: 'thing.3mf',
            ),
            child: const Text('open'),
          ),
        ),
      ),
      overrides: [
        noServerProfileOverride,
        pipelinesRepositoryProvider.overrideWithValue(_UnreadablePipelines()),
        pipelinesProvider.overrideWith((ref) async => [_pipeline]),
      ],
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('pipeline_run.pick'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gridfinity PETG').last);
    await tester.pumpAndSettle();

    final errors = await tapCapturingErrors(
      tester,
      byLogId('pipeline_run.start'),
    );

    expect(errors.single, isA<StateError>());
    expect(buttonAt(tester, 'pipeline_run.start').onPressed, isNotNull);
  });

  testWidgets('a save that fails with an unexpected error unlocks the form, '
      'and still reports it', (tester) async {
    await pumpPhone(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PipelineEditScreen(pipeline: _pipeline),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
      overrides: [
        noServerProfileOverride,
        pipelinesRepositoryProvider.overrideWithValue(_UnreadablePipelines()),
      ],
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final errors = await tapCapturingErrors(
      tester,
      byLogId('pipeline_edit.save'),
    );

    expect(errors.single, isA<StateError>());
    expect(buttonAt(tester, 'pipeline_edit.save').onPressed, isNotNull);
  });
}
