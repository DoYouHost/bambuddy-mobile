import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/spool_label.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

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
    test('chromatic colours come before neutrals', () {
      expect(spoolColorSortKey(red).bucket, 0);
      expect(spoolColorSortKey(green).bucket, 0);
      expect(spoolColorSortKey(blue).bucket, 0);
      for (final neutral in [black, grey, white]) {
        expect(spoolColorSortKey(neutral).bucket, 1);
      }
    });

    test('chromatic colours order by hue: R → G → B', () {
      expect(_sortByColor([blue, red, green]), [red, green, blue]);
      expect(spoolColorSortKey(red).pos, closeTo(0, 0.001));
      expect(spoolColorSortKey(green).pos, closeTo(120, 0.001));
      expect(spoolColorSortKey(blue).pos, closeTo(240, 0.001));
    });

    test('neutrals order dark to light, trailing the list', () {
      expect(_sortByColor([white, red, black, grey]), [
        red,
        black,
        grey,
        white,
      ]);
    });

    test('a missing colour lands among the neutrals, where black sits', () {
      final key = spoolColorSortKey(null);
      expect(key.bucket, 1);
      expect(key.pos, 0);
      // Does not throw, and does not land ahead of the chromatic colours.
      expect(_sortByColor([null, red]), [red, null]);
    });

    test(
      'a dark navy stays chromatic instead of falling into the neutrals',
      () {
        expect(spoolColorSortKey(const Color(0xFF001F3F)).bucket, 0);
      },
    );
  });

  group('renderLabels', () {
    late Dio dio;
    late _FakeAdapter adapter;

    /// Wires a Dio whose adapter answers every request with [bytes].
    void serve(List<int> bytes, {int status = 200}) {
      dio = testDio();
      adapter = _FakeAdapter(status: status, bytes: bytes);
      dio.httpClientAdapter = adapter;
    }

    test(
      'the native backend POSTs ids/template/monochrome and gets a PDF back',
      () async {
        serve(_pdfBytes);

        final bytes = await NativeInventorySource(dio).renderLabels(
          const SpoolLabelRequest(
            spoolIds: [7, 3, 11],
            template: SpoolLabelTemplate.averyL7160,
            monochrome: true,
          ),
        );

        expect(bytes, _pdfBytes);
        expect(adapter.captured!.path, '/api/v1/inventory/labels');
        final body = adapter.captured!.data as Map<String, dynamic>;
        // The id order has to survive: the server prints in the order it is sent.
        expect(body['spool_ids'], [7, 3, 11]);
        expect(body['template'], 'avery_l7160');
        expect(body['monochrome'], isTrue);
      },
    );

    test('monochrome defaults to false', () async {
      serve(_pdfBytes);
      await NativeInventorySource(dio).renderLabels(
        const SpoolLabelRequest(
          spoolIds: [1],
          template: SpoolLabelTemplate.box40x30,
        ),
      );
      expect((adapter.captured!.data as Map)['monochrome'], isFalse);
    });

    test(
      'Spoolman hits /spoolman/labels, not /spoolman/inventory/...',
      () async {
        serve(_pdfBytes);
        final bytes = await SpoolmanInventorySource(dio).renderLabels(
          const SpoolLabelRequest(
            spoolIds: [5],
            template: SpoolLabelTemplate.amsHolderSmall,
          ),
        );

        expect(bytes, _pdfBytes);
        expect(adapter.captured!.path, '/api/v1/spoolman/labels');
      },
    );

    test('an unknown id → 404 mapped to AppApiException', () async {
      serve(utf8.encode('{"detail":"Spool(s) not found: [99]"}'), status: 404);
      await expectLater(
        NativeInventorySource(dio).renderLabels(
          const SpoolLabelRequest(
            spoolIds: [99],
            template: SpoolLabelTemplate.box62x29,
          ),
        ),
        throwsA(isA<AppApiException>()),
      );
    });

    // Regression: the demo backend (and any older server without the label
    // routes) answers an unrouted POST with 200 and a body of `{}`. Without the
    // PDF-header check those bytes reached Android's print dialog, which killed
    // the app with a native "Cannot print a malformed PDF file" — not catchable
    // from Dart.
    test(
      '200 with a body that is not a PDF → AppApiException, not raw bytes',
      () async {
        serve(utf8.encode('{}'));
        await expectLater(
          NativeInventorySource(dio).renderLabels(
            const SpoolLabelRequest(
              spoolIds: [1],
              template: SpoolLabelTemplate.amsHolderLarge,
            ),
          ),
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

    test('an empty 200 does not get through either', () async {
      serve(const []);
      await expectLater(
        NativeInventorySource(dio).renderLabels(
          const SpoolLabelRequest(
            spoolIds: [1],
            template: SpoolLabelTemplate.box62x29,
          ),
        ),
        throwsA(isA<AppApiException>()),
      );
    });

    test(
      'every template carries the wire value the backend contract names',
      () {
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
      },
    );
  });

  group('starting_position', () {
    late Dio dio;
    late _FakeAdapter adapter;

    setUp(() {
      dio = testDio();
      adapter = _FakeAdapter(status: 200, bytes: _pdfBytes);
      dio.httpClientAdapter = adapter;
    });

    Map<String, dynamic> body() =>
        adapter.captured!.data as Map<String, dynamic>;

    test('reaches the body when a part-used sheet is resumed', () async {
      await NativeInventorySource(dio).renderLabels(
        const SpoolLabelRequest(
          spoolIds: [1],
          template: SpoolLabelTemplate.averyL7160,
          startingPosition: 7,
        ),
      );
      expect(body()['starting_position'], 7);
    });

    test('is absent for a whole sheet', () async {
      // 1 is the server's own default, and an older server would drop the key
      // either way — sending it would prove nothing about who honoured it.
      await NativeInventorySource(dio).renderLabels(
        const SpoolLabelRequest(
          spoolIds: [1],
          template: SpoolLabelTemplate.averyL7160,
        ),
      );
      expect(body().containsKey('starting_position'), isFalse);
    });

    test('reaches the Spoolman route too', () async {
      await SpoolmanInventorySource(dio).renderLabels(
        const SpoolLabelRequest(
          spoolIds: [1],
          template: SpoolLabelTemplate.avery5160,
          startingPosition: 30,
        ),
      );
      expect(adapter.captured!.path, '/api/v1/spoolman/labels');
      expect(body()['starting_position'], 30);
    });

    test('only the sheet templates have a capacity to start within', () {
      // A roll template prints one label per page, and the server refuses any
      // starting position but 1 on one.
      expect(SpoolLabelTemplate.averyL7160.sheetCapacity, 21);
      expect(SpoolLabelTemplate.avery5160.sheetCapacity, 30);
      for (final roll in [
        SpoolLabelTemplate.amsHolderSmall,
        SpoolLabelTemplate.amsHolderLarge,
        SpoolLabelTemplate.box40x30,
        SpoolLabelTemplate.box62x29,
      ]) {
        expect(roll.sheetCapacity, isNull, reason: roll.wire);
      }
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
