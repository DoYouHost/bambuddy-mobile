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

  setUp(() {
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
    test('a single file carries no receive deadline', () async {
      adapter.onGet(
        '/api/v1/printers/1/files/download',
        (s) => s.reply(200, [1, 2, 3]),
        queryParameters: {'path': '/a.3mf'},
      );

      final bytes = await repo.downloadFile(1, '/a.3mf');

      expect(bytes, isNotEmpty);
      expect(sent.single.receiveTimeout, Duration.zero);
    });

    test('the ZIP body stays {paths} and both deadlines are lifted', () async {
      adapter.onPost(
        '/api/v1/printers/1/files/download-zip',
        (s) => s.reply(200, [1]),
        data: {
          'paths': ['/a.3mf', '/b.3mf']
        },
      );

      await repo.downloadZip(1, const ['/a.3mf', '/b.3mf']);

      expect(sent.single.data, {
        'paths': ['/a.3mf', '/b.3mf']
      });
      expect(sent.single.receiveTimeout, Duration.zero);
      expect(sent.single.sendTimeout, Duration.zero);
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
          repo.downloadFile(1, '/big.3mf'),
          throwsA(isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', status)),
        );
      }
    });
  });
}
