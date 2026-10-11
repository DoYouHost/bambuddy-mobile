import 'dart:typed_data';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/data/label_printer_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late LabelPrinterRepository repo;

  setUp(() {
    dio = testDio();
    adapter = mockServer(dio);
    repo = LabelPrinterRepository(dio);
  });

  test('info() is null for a service that is not a label printer', () async {
    adapter.onGet('/info', (s) => s.reply(200, {'service': 'something-else'}));
    expect(await repo.info(), isNull);
  });

  test('info() is null when nothing answers', () async {
    adapter.onGet(
      '/info',
      (s) => s.throws(
        500,
        DioException(requestOptions: RequestOptions(path: '/info')),
      ),
    );
    expect(await repo.info(), isNull);
  });

  test('printPdf() posts the file and the copies as multipart', () async {
    final log = captureRequests(dio);
    adapter.onPost(
      '/print',
      (s) => s.reply(200, {'status': 'ok'}),
      data: Matchers.any,
    );

    await repo.printPdf(
      Uint8List.fromList([1, 2, 3]),
      filename: 'a.pdf',
      copies: 2,
    );

    final form = log.requests.single.data as FormData;
    expect(form.files.single.key, 'files');
    expect(form.files.single.value.filename, 'a.pdf');
    expect(
      {for (final f in form.fields) f.key: f.value},
      {'copies': '2', 'cut_at_end': 'true', 'cut_every': '0'},
    );
  });

  test('printPdf() passes the cut options on', () async {
    final log = captureRequests(dio);
    adapter.onPost(
      '/print',
      (s) => s.reply(200, {'status': 'ok'}),
      data: Matchers.any,
    );

    await repo.printPdf(
      Uint8List(1),
      filename: 'a.pdf',
      cutAtEnd: false,
      cutEvery: 5,
    );

    final form = log.requests.single.data as FormData;
    expect(
      {for (final f in form.fields) f.key: f.value},
      {'copies': '1', 'cut_at_end': 'false', 'cut_every': '5'},
    );
  });

  test('a 400 keeps the server sentence', () async {
    adapter.onPost(
      '/print',
      (s) => s.reply(400, {'detail': 'a.pdf p1: wrong_format 4000 × 3000 px'}),
      data: Matchers.any,
    );

    await expectLater(
      repo.printPdf(Uint8List(0), filename: 'a.pdf'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.detail,
          'detail',
          contains('wrong_format'),
        ),
      ),
    );
  });
}
