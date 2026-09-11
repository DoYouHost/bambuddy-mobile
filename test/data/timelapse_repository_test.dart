import 'dart:convert';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/data/timelapse_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late TimelapseRepository repo;

  setUp(() {
    dio = testDio();
    adapter = DioAdapter(dio: dio);
    repo = TimelapseRepository(dio);
  });

  group('TimelapseRepository', () {
    test('info decodes video metadata correctly', () async {
      adapter.onGet(
        Endpoints.archiveTimelapseInfo(123),
        (s) => s.reply(200, {
          'duration': 142.5,
          'width': 1920,
          'height': 1080,
          'fps': 30.0,
          'codec': 'h264',
          'file_size': 5432100,
          'has_audio': false,
        }),
      );

      final info = await repo.info(123);
      expect(info.duration, 142.5);
      expect(info.width, 1920);
      expect(info.height, 1080);
      expect(info.fps, 30.0);
      expect(info.codec, 'h264');
      expect(info.fileSize, 5432100);
      expect(info.hasAudio, isFalse);
    });

    test('filmstrip decodes base64 thumbnails and timestamps', () async {
      final sampleBytes = utf8.encode('fake-jpeg-frame');
      final encodedFrame = base64Encode(sampleBytes);

      adapter.onGet(
        Endpoints.archiveTimelapseThumbnails(123),
        (s) => s.reply(200, {
          'thumbnails': [encodedFrame, 'not-valid-base64-!@#\$%^&*()'],
          'timestamps': [0.0, 10.5],
        }),
        queryParameters: {'count': 14, 'width': 160},
      );

      final strip = await repo.filmstrip(123, count: 14, width: 160);
      expect(strip.isEmpty, isFalse);
      expect(strip.frames, hasLength(1));
      expect(strip.frames.single, sampleBytes);
      expect(strip.timestamps, [0.0, 10.5]);
    });

    test('process posts form data with replace save_mode and decodes result', () async {
      adapter.onPost(
        Endpoints.archiveTimelapseProcess(123),
        (s) => s.reply(200, {
          'status': 'completed',
          'message': 'Render successful',
          'output_path': '/timelapses/123_processed.mp4',
        }),
        data: Matchers.any,
      );

      final result = await repo.process(
        123,
        trimStart: 2.0,
        trimEnd: 120.0,
        speed: 2.0,
      );

      expect(result.ok, isTrue);
      expect(result.status, 'completed');
      expect(result.message, 'Render successful');
      expect(result.outputPath, '/timelapses/123_processed.mp4');
    });

    test('handles 404 with ApiException via guard', () async {
      adapter.onGet(
        Endpoints.archiveTimelapseInfo(999),
        (s) => s.reply(404, {'detail': 'Timelapse not found'}),
      );

      expect(
        () => repo.info(999),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
