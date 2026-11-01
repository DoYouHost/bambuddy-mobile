import 'dart:io';

import 'package:bambuddy_mobile/data/streamed_download.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

ResponseBody _reply(int status) => ResponseBody.fromString(
  '{}',
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

void main() {
  late Directory tmp;
  late String filePath;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('upload_test');
    filePath = '${tmp.path}/on-disk-name.bin';
    await File(filePath).writeAsBytes([1, 2, 3]);
  });

  tearDown(() => tmp.delete(recursive: true));

  Dio dioWith(ScriptedAdapter adapter) =>
      Dio(BaseOptions(baseUrl: 'http://x'))..httpClientAdapter = adapter;

  test(
    'the file travels under the field name with the given filename',
    () async {
      final adapter = ScriptedAdapter((_) => _reply(200));
      await postFile<dynamic>(
        dioWith(adapter),
        '/up',
        filePath: filePath,
        filename: 'wanted.3mf',
      );
      await postFile<dynamic>(
        dioWith(adapter),
        '/up',
        filePath: filePath,
        filename: 'cover.png',
        fieldName: 'image',
      );

      final first = adapter.requests[0];
      final second = adapter.requests[1];
      expect(first.method, 'POST');
      expect(first.path, '/up');
      final files = (first.data as FormData).files;
      expect(files.map((f) => f.key), ['file']);
      expect(files.single.value.filename, 'wanted.3mf');
      expect(files.single.value.length, 3);
      expect((second.data as FormData).files.single.key, 'image');
    },
  );

  test(
    'the query reaches the request, and none is sent when not given',
    () async {
      final adapter = ScriptedAdapter((_) => _reply(200));
      final dio = dioWith(adapter);
      await postFile<dynamic>(
        dio,
        '/up',
        filePath: filePath,
        filename: 'a.stl',
        query: {'folder_id': 4, 'generate_stl_thumbnails': true},
      );
      await postFile<dynamic>(
        dio,
        '/up',
        filePath: filePath,
        filename: 'a.stl',
      );

      expect(adapter.requests[0].queryParameters, {
        'folder_id': 4,
        'generate_stl_thumbnails': true,
      });
      expect(adapter.requests[1].queryParameters, isEmpty);
    },
  );

  test('the upload has no deadline', () async {
    final adapter = ScriptedAdapter((_) => _reply(200));
    await postFile<dynamic>(
      dioWith(adapter),
      '/up',
      filePath: filePath,
      filename: 'a.stl',
    );

    expect(adapter.requests.single.sendTimeout, Duration.zero);
    expect(adapter.requests.single.receiveTimeout, Duration.zero);
  });

  test('progress is a fraction, and null while the total is unknown', () async {
    final seen = <double?>[];
    final adapter = ScriptedAdapter((options) {
      options.onSendProgress!(50, 200);
      options.onSendProgress!(10, -1);
      return _reply(200);
    });
    await postFile<dynamic>(
      dioWith(adapter),
      '/up',
      filePath: filePath,
      filename: 'a.stl',
      onProgress: seen.add,
    );

    expect(seen, [0.25, null]);
  });

  test('without a progress callback Dio is not asked to report', () async {
    final adapter = ScriptedAdapter((_) => _reply(200));
    await postFile<dynamic>(
      dioWith(adapter),
      '/up',
      filePath: filePath,
      filename: 'a.stl',
    );

    expect(adapter.requests.single.onSendProgress, isNull);
  });

  test('the decoded response is handed back', () async {
    final adapter = ScriptedAdapter(
      (_) => ResponseBody.fromString(
        '{"id": 7}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    );
    final res = await postFile<Map<String, dynamic>>(
      dioWith(adapter),
      '/up',
      filePath: filePath,
      filename: 'a.3mf',
    );

    expect(res.data, {'id': 7});
  });

  test('a refusal propagates, and so does a missing file', () async {
    final refused = dioWith(ScriptedAdapter((_) => _reply(413)));
    await expectLater(
      postFile<dynamic>(refused, '/up', filePath: filePath, filename: 'a.stl'),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'status',
          413,
        ),
      ),
    );

    final adapter = ScriptedAdapter((_) => _reply(200));
    await expectLater(
      postFile<dynamic>(
        dioWith(adapter),
        '/up',
        filePath: '${tmp.path}/missing.bin',
        filename: 'a.stl',
      ),
      throwsA(isA<Object>()),
    );
    expect(adapter.requests, isEmpty);
  });
}
