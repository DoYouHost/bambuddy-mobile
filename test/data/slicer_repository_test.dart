import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/slicer_preset.dart';
import 'package:bambuddy_mobile/data/slicer_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late SlicerRepository repo;

  const preset = SlicerPreset(source: 'local', id: '12', name: '0.20 mm');

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    repo = SlicerRepository(dio);
  });

  group('presetValues', () {
    test('parses resolved values and turns override support on', () async {
      adapter.onGet(
        '/api/v1/slicer/preset-values',
        (s) => s.reply(200, {
          'resolved': true,
          'values': {'layer_height': '0.2', 'wall_loops': 3},
          'reason': 'ok',
        }),
        queryParameters: {'source': 'local', 'id': '12', 'slot': 'process'},
      );

      final values = await repo.presetValues(preset);

      expect(values!.resolved, isTrue);
      expect(values.values['layer_height'], '0.2');
      expect(values.cause, PresetValuesCause.ok);
      expect(await repo.supportsProcessOverrides(), isTrue);
    });

    test('404 → null, support off (server < 1.2.6)', () async {
      adapter.onGet(
        '/api/v1/slicer/preset-values',
        (s) => s.reply(404, {'detail': 'Not Found'}),
        queryParameters: {'source': 'local', 'id': '12', 'slot': 'process'},
      );

      expect(await repo.presetValues(preset), isNull);
      expect(await repo.supportsProcessOverrides(), isFalse);
    });

    test('resolved:false is NOT missing support — the route answered', () async {
      // Unreadable values and a missing route are different things: the first
      // leaves the panel open on schema defaults, the second hides it entirely.
      // The usual cause is a sidecar older than the endpoint.
      adapter.onGet(
        '/api/v1/slicer/preset-values',
        (s) => s.reply(200, {
          'resolved': false,
          'values': <String, dynamic>{},
          'reason': 'sidecar_outdated',
        }),
        queryParameters: {'source': 'local', 'id': '12', 'slot': 'process'},
      );

      final values = await repo.presetValues(preset);

      expect(values!.resolved, isFalse);
      expect(values.cause, PresetValuesCause.sidecarOutdated);
      expect(await repo.supportsProcessOverrides(), isTrue);
    });

    test('any other failure degrades to unresolved rather than throwing', () async {
      adapter.onGet(
        '/api/v1/slicer/preset-values',
        (s) => s.reply(500, {'detail': 'boom'}),
        queryParameters: {'source': 'local', 'id': '12', 'slot': 'process'},
      );

      final values = await repo.presetValues(preset);

      expect(values, isNotNull);
      expect(values!.resolved, isFalse);
    });

    test('an expired session throws instead of degrading', () async {
      // The one failure that must not be absorbed: swallowed here, nothing
      // redirects to the login and the panel just sits there empty.
      adapter.onGet(
        '/api/v1/slicer/preset-values',
        (s) => s.reply(401, {'detail': 'Not authenticated'}),
        queryParameters: {'source': 'local', 'id': '12', 'slot': 'process'},
      );

      await expectLater(
        repo.presetValues(preset),
        throwsA(isA<AuthException>()
            .having((e) => e.code, 'code', AppErrorCode.unauthorized)),
      );
      expect(repo.supportsProcessOverrides(), completion(isFalse),
          reason: 'a rejected call proves nothing about the route');
    });
  });
}
