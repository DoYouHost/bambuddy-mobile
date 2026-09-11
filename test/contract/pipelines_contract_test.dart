import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/pipeline_run.dart';
import 'package:bambuddy_mobile/core/models/slicer_pipeline.dart';
import 'package:bambuddy_mobile/core/models/slicer_preset.dart';
import 'package:bambuddy_mobile/data/pipelines_repository.dart';
import 'package:bambuddy_mobile/data/slicer_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

void main() {
  group('pipelines contract', skip: contractSkipReason, () {
    late Dio dio;
    late PipelinesRepository pipelinesRepo;
    late SlicerRepository slicerRepo;

    setUpAll(() async {
      dio = await authenticatedDio();
      pipelinesRepo = PipelinesRepository(dio);
      slicerRepo = SlicerRepository(dio);
    });

    test('GET /slicer/presets and /slicer/printer-models decode', () async {
      final presets = await slicerRepo.presets();
      expect(presets, isA<UnifiedPresets>());

      final modelsRes = await dio.get<dynamic>(Endpoints.slicerPrinterModels);
      expect(modelsRes.data, isA<Map<String, dynamic>>());
    });

    test('GET /slicer-pipelines/ decodes into SlicerPipeline list if supported', () async {
      final supported = await pipelinesRepo.probe();
      if (!supported) return;

      final pipelines = await pipelinesRepo.list();
      expect(pipelines, isA<List<SlicerPipeline>>());
      for (final p in pipelines) {
        expect(p.id, greaterThan(0));
        expect(p.name, isNotEmpty);
      }
    });

    test('GET /pipeline-runs decodes into PipelineRunPage if supported', () async {
      final supported = await pipelinesRepo.probe();
      if (!supported) return;

      final runsPage = await pipelinesRepo.runs();
      expect(runsPage.runs, isA<List<PipelineRun>>());
      expect(runsPage.total, greaterThanOrEqualTo(0));
      for (final run in runsPage.runs) {
        expect(run.id, greaterThan(0));
        expect(run.status, isNotNull);
      }
    });
  });
}
