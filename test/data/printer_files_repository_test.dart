import 'dart:io';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/data/printer_files_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late PrinterFilesRepository repo;
  late List<RequestOptions> sent;
  late Directory scratch;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('printer-files-test');
    addTearDown(() => scratch.deleteSync(recursive: true));
    dio = Dio(BaseOptions(
      baseUrl: 'http://s.local:8000',
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
    ));
    sent = [];
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        sent.add(options);
        handler.next(options);
      },
    ));
    adapter = DioAdapter(dio: dio);
    repo = PrinterFilesRepository(dio);
  });

  group('listFiles', () {
    void replyWith(Map<String, dynamic> body) => adapter.onGet(
          '/api/v1/printers/1/files',
          (s) => s.reply(200, body),
          queryParameters: {'path': '/'},
        );

    test('parses entries and reports the printer as reachable', () async {
      replyWith(const {
        'path': '/',
        'files': [
          {'name': 'model', 'path': '/model', 'is_directory': true, 'size': 0},
          {'name': 'a.3mf', 'path': '/a.3mf', 'size': 1024},
        ],
      });

      final listing = await repo.listFiles(1, '/');

      expect(listing.files, hasLength(2));
      expect(listing.files.first.isDirectory, isTrue);
      expect(listing.files.last.size, 1024);
      expect(listing.printerUnavailable, isFalse);
    });

    test('an empty listing with the warning means the printer did not answer',
        () async {
      replyWith(const {
        'path': '/',
        'files': [],
        'warnings': ['printer_unavailable'],
      });

      final listing = await repo.listFiles(1, '/');

      expect(listing.files, isEmpty);
      expect(listing.printerUnavailable, isTrue);
    });

    test('a server that sends no warnings keeps reading as an empty folder',
        () async {
      replyWith(const {'path': '/', 'files': []});

      final listing = await repo.listFiles(1, '/');

      expect(listing.files, isEmpty);
      expect(listing.printerUnavailable, isFalse);
    });

    test('an unrelated warning is not the unavailable one', () async {
      replyWith(const {
        'path': '/',
        'files': [],
        'warnings': ['something_else'],
      });

      expect((await repo.listFiles(1, '/')).printerUnavailable, isFalse);
    });

    test('a body without a files key degrades to an empty listing', () async {
      replyWith(const {});

      final listing = await repo.listFiles(1, '/');

      expect(listing.files, isEmpty);
      expect(listing.printerUnavailable, isFalse);
    });
  });

  group('downloads', () {
    test('a single file lands on disk, never in memory, and cannot time out',
        () async {
      adapter.onGet(
        '/api/v1/printers/1/files/download',
        (s) => s.reply(200, 'model bytes'),
        queryParameters: {'path': '/a.3mf'},
      );
      final target = '${scratch.path}/a.3mf';

      await repo.downloadFileTo(1, '/a.3mf', target);

      // The adapter serves the reply JSON-encoded, so the quotes are the
      // mock's, not the route's: what matters is that the body reached the file.
      expect(File(target).readAsStringSync(), contains('model bytes'));
      expect(sent.single.receiveTimeout, Duration.zero);
      expect(sent.single.responseType, ResponseType.stream);
    });

    test('the ZIP is asked for with a POST and the body stays {paths}',
        () async {
      adapter.onPost(
        '/api/v1/printers/1/files/download-zip',
        (s) => s.reply(200, 'zip bytes'),
        data: {
          'paths': ['/a.3mf', '/b.3mf']
        },
      );
      final target = '${scratch.path}/files.zip';

      await repo.downloadZipTo(1, const ['/a.3mf', '/b.3mf'], target);

      expect(File(target).readAsStringSync(), contains('zip bytes'));
      expect(sent.single.method, 'POST');
      expect(sent.single.data, {
        'paths': ['/a.3mf', '/b.3mf']
      });
      expect(sent.single.receiveTimeout, Duration.zero);
    });

    test('progress is reported as it arrives', () async {
      adapter.onGet(
        '/api/v1/printers/1/files/download',
        (s) => s.reply(200, 'model bytes'),
        queryParameters: {'path': '/a.3mf'},
      );
      final seen = <int>[];

      await repo.downloadFileTo(
        1,
        '/a.3mf',
        '${scratch.path}/a.3mf',
        onProgress: (received, _) => seen.add(received),
      );

      expect(seen, isNotEmpty);
    });

    test('the refusals the file manager words itself keep their status',
        () async {
      for (final status in const [413, 504, 507]) {
        adapter.onGet(
          '/api/v1/printers/1/files/download',
          (s) => s.reply(status, {'detail': 'no'}),
          queryParameters: {'path': '/big.3mf'},
        );

        await expectLater(
          repo.downloadFileTo(1, '/big.3mf', '${scratch.path}/big.3mf'),
          throwsA(isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', status)),
        );
      }
    });
  });
}
