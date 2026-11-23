import 'dart:convert';

import 'package:bambuddy_mobile/core/api/dio_json.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

ResponseBody _json(Object? body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Dio _dio(Object Function(RequestOptions) reply) =>
    Dio(BaseOptions(baseUrl: 'http://s.local'))
      ..httpClientAdapter = ScriptedAdapter(reply);

int _id(Map<String, dynamic> json) => json['id'] as int? ?? -1;

void main() {
  group('getObject', () {
    test('decodes a map', () async {
      final dio = _dio((_) => _json({'id': 7}));
      expect(await dio.getObject('/x', _id), 7);
    });

    test('an empty 200 body decodes as an empty object', () async {
      final dio = _dio(
        (_) => ResponseBody.fromString(
          '',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      );
      expect(await dio.getObject('/x', _id), -1);
    });

    test('a 204 without a body decodes as an empty object', () async {
      final dio = _dio((_) => ResponseBody.fromString('', 204));
      expect(await dio.getObject('/x', _id), -1);
    });

    test('sends the path, the query and the options', () async {
      final dio = _dio((_) => _json({'id': 1}));
      final log = captureRequests(dio);
      await dio.getObject(
        '/x',
        _id,
        query: {'a': 1, 'b': 'two'},
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
      expect(log.calls, ['GET /x']);
      expect(log.requests.single.queryParameters, {'a': 1, 'b': 'two'});
      expect(log.requests.single.receiveTimeout, const Duration(seconds: 60));
    });

    test('a 404 stays a DioException', () async {
      final dio = _dio((_) => _json({'detail': 'Not Found'}, 404));
      await expectLater(
        dio.getObject('/x', _id),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            404,
          ),
        ),
      );
    });

    test('a list body is not decoded as an object', () async {
      final dio = _dio((_) => _json([1, 2]));
      await expectLater(dio.getObject('/x', _id), throwsA(isA<DioException>()));
    });
  });

  group('getList', () {
    test('decodes a list and drops a record that is no object', () async {
      final dio = _dio(
        (_) => _json([
          {'id': 1},
          'junk',
          {'id': 3},
        ]),
      );
      expect(await dio.getList('/x', _id), [1, 3]);
    });

    test('an empty list is empty', () async {
      final dio = _dio((_) => _json([]));
      expect(await dio.getList('/x', _id), isEmpty);
    });

    test('an empty body is empty', () async {
      final dio = _dio((_) => ResponseBody.fromString('', 204));
      expect(await dio.getList('/x', _id), isEmpty);
    });

    test('sends the query', () async {
      final dio = _dio((_) => _json([]));
      final log = captureRequests(dio);
      await dio.getList('/x', _id, query: {'printer_id': 4});
      expect(log.requests.single.queryParameters, {'printer_id': 4});
    });

    test('a 404 stays a DioException', () async {
      final dio = _dio((_) => _json({'detail': 'Not Found'}, 404));
      await expectLater(dio.getList('/x', _id), throwsA(isA<DioException>()));
    });

    test('a body that is an object is a cast failure, as before', () async {
      final dio = _dio((_) => _json({'id': 1}));
      await expectLater(dio.getList('/x', _id), throwsA(isA<DioException>()));
    });
  });

  // The three writers share one shape; each verb is checked on its own so a
  // helper that sends the wrong method fails by name.
  final writers = <String, Future<int> Function(Dio, {Object? data})>{
    'POST': (dio, {data}) => dio.postObject(
      '/x',
      _id,
      data: data,
      query: {'q': 1},
      options: Options(receiveTimeout: const Duration(seconds: 60)),
    ),
    'PUT': (dio, {data}) => dio.putObject(
      '/x',
      _id,
      data: data,
      query: {'q': 1},
      options: Options(receiveTimeout: const Duration(seconds: 60)),
    ),
    'PATCH': (dio, {data}) => dio.patchObject(
      '/x',
      _id,
      data: data,
      query: {'q': 1},
      options: Options(receiveTimeout: const Duration(seconds: 60)),
    ),
  };

  for (final MapEntry(key: verb, value: write) in writers.entries) {
    group('${verb.toLowerCase()}Object', () {
      test('sends the verb, body, query and options, decodes a map', () async {
        final dio = _dio((_) => _json({'id': 7}));
        final log = captureRequests(dio);
        expect(await write(dio, data: {'name': 'a'}), 7);
        expect(log.calls, ['$verb /x']);
        expect(log.requests.single.data, {'name': 'a'});
        expect(log.requests.single.queryParameters, {'q': 1});
        expect(log.requests.single.receiveTimeout, const Duration(seconds: 60));
      });

      test('an empty body decodes as an empty object', () async {
        final dio = _dio((_) => ResponseBody.fromString('', 204));
        expect(await write(dio), -1);
      });

      test('a 409 stays a DioException', () async {
        final dio = _dio((_) => _json({'detail': 'taken'}, 409));
        await expectLater(
          write(dio),
          throwsA(
            isA<DioException>().having(
              (e) => e.response?.statusCode,
              'status',
              409,
            ),
          ),
        );
      });

      test('a list body is not decoded as an object', () async {
        final dio = _dio((_) => _json([1, 2]));
        await expectLater(write(dio), throwsA(isA<DioException>()));
      });
    });
  }
}
