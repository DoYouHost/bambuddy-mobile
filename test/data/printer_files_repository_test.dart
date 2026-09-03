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

  group('download jobs', () {
    test('start sends the selection, its sizes and how to present it',
        () async {
      adapter.onPost(
        '/api/v1/printers/1/files/download-job',
        (s) => s.reply(200, const {
          'job_id': 'job-1',
          'printer_id': 1,
          'state': 'queued',
          'requested': 2,
          'filename': 'X1-files.zip',
        }),
        data: Matchers.any,
      );

      final job = await repo.startDownloadJob(
        1,
        paths: const ['/a.3mf', '/b.3mf'],
        sizes: const {'/a.3mf': 10, '/b.3mf': 20},
        filename: 'X1-files.zip',
      );

      expect(job?.jobId, 'job-1');
      expect(sent.single.data, {
        'paths': ['/a.3mf', '/b.3mf'],
        'sizes': {'/a.3mf': 10, '/b.3mf': 20},
        'filename': 'X1-files.zip',
        'as_zip': true,
      });
    });

    test('sizes it cannot vouch for are left out entirely', () async {
      // The schema wants one per path or none at all, and a made-up number
      // would pass the server's free-space check on a lie.
      adapter.onPost(
        '/api/v1/printers/1/files/download-job',
        (s) => s.reply(200, const {'job_id': 'job-1', 'state': 'queued'}),
        data: Matchers.any,
      );

      await repo.startDownloadJob(
        1,
        paths: const ['/a.3mf', '/b.3mf'],
        sizes: const {},
        filename: 'X1-files.zip',
      );

      expect(sent.single.data, isNot(contains('sizes')));
    });

    test('a server without the route answers null, and says so once', () async {
      adapter.onPost(
        '/api/v1/printers/1/files/download-job',
        (s) => s.reply(404, {'detail': 'Not Found'}),
        data: Matchers.any,
      );

      final job = await repo.startDownloadJob(
        1,
        paths: const ['/a.3mf'],
        sizes: const {},
        filename: 'a.3mf',
        asZip: false,
      );

      expect(job, isNull);
      // Latched, so the next download goes straight down the legacy path
      // instead of paying for the same 404 again.
      expect(await repo.supportsDownloadJobs(), isFalse);
    });

    test('a refusal is not the route being absent', () async {
      adapter.onPost(
        '/api/v1/printers/1/files/download-job',
        (s) => s.reply(403, {'detail': 'nope'}),
        data: Matchers.any,
      );

      // A 403 goes out as the app's refusal type, the same as everywhere else,
      // rather than being recorded as the route not existing.
      await expectLater(
        repo.startDownloadJob(
          1,
          paths: const ['/a.3mf'],
          sizes: const {},
          filename: 'a.3mf',
        ),
        throwsA(isA<AuthException>()
            .having((e) => e.code, 'code', AppErrorCode.forbidden)),
      );
      expect(await repo.supportsDownloadJobs(), isFalse);
    });

    test('polling a job the server no longer holds answers null', () async {
      adapter.onGet(
        '/api/v1/printers/1/files/download-jobs/gone',
        (s) => s.reply(404, {'detail': 'Printer download job not found'}),
      );

      expect(await repo.downloadJob(1, 'gone'), isNull);
    });

    test('a vanished job says nothing about the route family', () async {
      // The two 404s mean different things: one is "no such job", the other
      // "no such route", and recording the first as the second would send the
      // next download down the legacy path over an expired staging folder.
      adapter.onPost(
        '/api/v1/printers/1/files/download-job',
        (s) => s.reply(200, const {'job_id': 'job-1', 'state': 'preparing'}),
        data: Matchers.any,
      );
      adapter.onGet(
        '/api/v1/printers/1/files/download-jobs/job-1',
        (s) => s.reply(404, {'detail': 'Printer download job not found'}),
      );

      await repo.startDownloadJob(
        1,
        paths: const ['/a.3mf'],
        sizes: const {},
        filename: 'a.3mf',
      );
      await repo.downloadJob(1, 'job-1');

      expect(await repo.supportsDownloadJobs(), isTrue);
    });

    test('cancelling something already gone is the state that was asked for',
        () async {
      adapter.onDelete(
        '/api/v1/printers/1/files/download-jobs/job-1',
        (s) => s.reply(404, {'detail': 'Printer download job not found'}),
      );

      await expectLater(repo.cancelDownloadJob(1, 'job-1'), completes);
    });

    test('the prepared bundle is fetched by its token, without a deadline',
        () async {
      adapter.onGet(
        '/api/v1/printers/1/files/dl/tok%2F1/X1%20files.zip',
        (s) => s.reply(200, 'zip bytes'),
      );
      final target = '${scratch.path}/files.zip';

      await repo.downloadPreparedTo(
        1,
        token: 'tok/1',
        filename: 'X1 files.zip',
        savePath: target,
      );

      expect(File(target).readAsStringSync(), contains('zip bytes'));
      // Both are user data in a URL path: a token with a slash in it must not
      // address a different route, and a space must not break the request.
      expect(sent.single.path, contains('tok%2F1'));
      expect(sent.single.path, contains('X1%20files.zip'));
      expect(sent.single.receiveTimeout, Duration.zero);
    });

    test('nothing seen and no version known keeps the legacy path', () async {
      // `whenUnknown: false`: the fallback downloads the same bytes, so the
      // cost of guessing wrong is the progress bar, not the file.
      expect(await repo.supportsDownloadJobs(), isFalse);
    });
  });
}
