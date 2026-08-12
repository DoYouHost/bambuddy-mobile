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
    test('parsuje rozwiązane wartości i włącza wsparcie nadpisań', () async {
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

    test('404 → null i wsparcie wyłączone (serwer < 1.2.6)', () async {
      adapter.onGet(
        '/api/v1/slicer/preset-values',
        (s) => s.reply(404, {'detail': 'Not Found'}),
        queryParameters: {'source': 'local', 'id': '12', 'slot': 'process'},
      );

      expect(await repo.presetValues(preset), isNull);
      expect(await repo.supportsProcessOverrides(), isFalse);
    });

    test('resolved:false to NIE brak wsparcia — trasa odpowiedziała', () async {
      // Nieodczytane wartości i nieistniejąca trasa to dwie różne rzeczy:
      // pierwsza zostawia panel otwarty z domyślnymi ze schematu, druga chowa
      // go w całości. Najczęstsza przyczyna to sidecar starszy niż endpoint.
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

    test('inna awaria degraduje do „nierozwiązane", nie rzuca', () async {
      adapter.onGet(
        '/api/v1/slicer/preset-values',
        (s) => s.reply(500, {'detail': 'boom'}),
        queryParameters: {'source': 'local', 'id': '12', 'slot': 'process'},
      );

      final values = await repo.presetValues(preset);

      expect(values, isNotNull);
      expect(values!.resolved, isFalse);
    });
  });
}
