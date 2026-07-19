import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/spool_label.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sorts colours the way the label sheet does, so a test can assert on the
/// resulting order rather than on raw key tuples.
List<Color?> _sortByColor(List<Color?> colors) {
  final list = [...colors];
  list.sort((a, b) {
    final ka = spoolColorSortKey(a);
    final kb = spoolColorSortKey(b);
    final byBucket = ka.bucket.compareTo(kb.bucket);
    return byBucket != 0 ? byBucket : ka.pos.compareTo(kb.pos);
  });
  return list;
}

/// Minimal stand-in for the PDF stream the endpoint returns — enough to carry
/// the `%PDF` magic number the source validates before handing bytes to the
/// platform printer.
final _pdfBytes = utf8.encode('%PDF-1.4\n%stub\n');

void main() {
  const red = Color(0xFFFF0000);
  const green = Color(0xFF00FF00);
  const blue = Color(0xFF0000FF);
  const black = Color(0xFF000000);
  const grey = Color(0xFF808080);
  const white = Color(0xFFFFFFFF);

  group('spoolColorSortKey', () {
    test('kolory chromatyczne idą przed neutralnymi', () {
      expect(spoolColorSortKey(red).bucket, 0);
      expect(spoolColorSortKey(green).bucket, 0);
      expect(spoolColorSortKey(blue).bucket, 0);
      for (final neutral in [black, grey, white]) {
        expect(spoolColorSortKey(neutral).bucket, 1);
      }
    });

    test('chromatyczne układają się po odcieniu: R → G → B', () {
      expect(_sortByColor([blue, red, green]), [red, green, blue]);
      expect(spoolColorSortKey(red).pos, closeTo(0, 0.001));
      expect(spoolColorSortKey(green).pos, closeTo(120, 0.001));
      expect(spoolColorSortKey(blue).pos, closeTo(240, 0.001));
    });

    test('neutralne układają się od ciemnych do jasnych, na końcu listy', () {
      expect(_sortByColor([white, red, black, grey]), [
        red,
        black,
        grey,
        white,
      ]);
    });

    test('brak koloru trafia do neutralnych na pozycji czerni', () {
      final key = spoolColorSortKey(null);
      expect(key.bucket, 1);
      expect(key.pos, 0);
      // Nie wywala się i nie ląduje przed kolorami chromatycznymi.
      expect(_sortByColor([null, red]), [red, null]);
    });

    test('ciemny granat zostaje chromatyczny, nie wpada do neutralnych', () {
      expect(spoolColorSortKey(const Color(0xFF001F3F)).bucket, 0);
    });
  });

  group('renderLabels', () {
    late Dio dio;
    late _FakeAdapter adapter;

    /// Wires a Dio whose adapter answers every request with [bytes].
    void serve(List<int> bytes, {int status = 200}) {
      dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
      adapter = _FakeAdapter(status: status, bytes: bytes);
      dio.httpClientAdapter = adapter;
    }

    test(
      'natywny backend POSTuje ids/template/monochrome i zwraca PDF',
      () async {
        serve(_pdfBytes);

        final bytes = await NativeInventorySource(dio).renderLabels(
          [7, 3, 11],
          SpoolLabelTemplate.averyL7160,
          monochrome: true,
        );

        expect(bytes, _pdfBytes);
        expect(adapter.captured!.path, '/api/v1/inventory/labels');
        final body = adapter.captured!.data as Map<String, dynamic>;
        // Kolejność ids musi przetrwać — serwer drukuje w kolejności wysyłki.
        expect(body['spool_ids'], [7, 3, 11]);
        expect(body['template'], 'avery_l7160');
        expect(body['monochrome'], isTrue);
      },
    );

    test('monochrome domyślnie false', () async {
      serve(_pdfBytes);
      await NativeInventorySource(
        dio,
      ).renderLabels([1], SpoolLabelTemplate.box40x30);
      expect((adapter.captured!.data as Map)['monochrome'], isFalse);
    });

    test(
      'Spoolman uderza w /spoolman/labels, nie w /spoolman/inventory/...',
      () async {
        serve(_pdfBytes);
        final bytes = await SpoolmanInventorySource(
          dio,
        ).renderLabels([5], SpoolLabelTemplate.amsHolderSmall);

        expect(bytes, _pdfBytes);
        expect(adapter.captured!.path, '/api/v1/spoolman/labels');
      },
    );

    test('nieznane id → 404 mapowane na AppApiException', () async {
      serve(utf8.encode('{"detail":"Spool(s) not found: [99]"}'), status: 404);
      await expectLater(
        NativeInventorySource(
          dio,
        ).renderLabels([99], SpoolLabelTemplate.box62x29),
        throwsA(isA<AppApiException>()),
      );
    });

    // Regresja: demo backend (i każdy starszy serwer bez tras etykiet) odpowiada
    // na nieznany POST statusem 200 i ciałem `{}`. Bez walidacji nagłówka PDF te
    // bajty trafiały do androidowego dialogu druku, który wywalał aplikację
    // natywnym wyjątkiem "Cannot print a malformed PDF file" — nie do złapania
    // z Darta.
    test(
      '200 z ciałem innym niż PDF → AppApiException, nie surowe bajty',
      () async {
        serve(utf8.encode('{}'));
        await expectLater(
          NativeInventorySource(
            dio,
          ).renderLabels([1], SpoolLabelTemplate.amsHolderLarge),
          throwsA(
            isA<AppApiException>().having(
              (e) => e.code,
              'code',
              AppErrorCode.malformedResponse,
            ),
          ),
        );
      },
    );

    test('pusta odpowiedź 200 też nie przechodzi', () async {
      serve(const []);
      await expectLater(
        NativeInventorySource(
          dio,
        ).renderLabels([1], SpoolLabelTemplate.box62x29),
        throwsA(isA<AppApiException>()),
      );
    });

    test('każdy szablon ma wartość zgodną z kontraktem backendu', () {
      expect(
        SpoolLabelTemplate.values.map((t) => t.wire),
        containsAll([
          'ams_holder_74x33',
          'ams_holder_75x55',
          'box_40x30',
          'box_62x29',
          'avery_l7160',
          'avery_5160',
        ]),
      );
    });
  });
}

/// Adapter returning raw bytes, so tests exercise the real `ResponseType.bytes`
/// path. `http_mock_adapter` JSON-encodes every reply, which cannot express a
/// binary body starting with the `%PDF` magic number.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.status, required this.bytes});

  final int status;
  final List<int> bytes;

  /// Request the source actually sent — for asserting path and body.
  RequestOptions? captured;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    captured = options;
    return ResponseBody.fromBytes(bytes, status);
  }

  @override
  void close({bool force = false}) {}
}
