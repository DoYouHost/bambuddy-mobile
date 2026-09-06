import 'dart:async';
import 'dart:io';

import 'package:bambuddy_mobile/core/models/printer_download_job.dart';
import 'package:bambuddy_mobile/data/printer_files_repository.dart';
import 'package:bambuddy_mobile/features/files/printer_download_job.dart';
import 'package:bambuddy_mobile/features/files/printer_selection_download.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../helpers.dart';

/// The step between "Download was pressed" and "there is a file on disk", now
/// that both the printer's file manager and the archive's media sheet go
/// through it: a regression here breaks two screens, so it is pinned directly
/// rather than only through either of them.

/// A repository that records what it was asked for and writes the bytes itself.
class _Repo extends PrinterFilesRepository {
  _Repo({this.hasJobs = true, this.jobsAnswer}) : super(Dio());

  /// Whether this stands for a server with the preparation routes.
  final bool hasJobs;

  /// Holds the capability answer open, for the window between "Download" and
  /// there being a run to cancel.
  final Completer<void>? jobsAnswer;

  final List<String> calls = [];
  Map<String, int>? sentSizes;
  bool? sentAsZip;

  @override
  Future<bool> supportsDownloadJobs() async {
    await jobsAnswer?.future;
    return hasJobs;
  }

  @override
  Future<PrinterDownloadJob?> startDownloadJob(
    int printerId, {
    required List<String> paths,
    required Map<String, int> sizes,
    required String filename,
    bool asZip = true,
  }) async {
    calls.add('start');
    sentSizes = sizes;
    sentAsZip = asZip;
    return PrinterDownloadJob(
      jobId: 'job-1',
      printerId: printerId,
      state: PrinterDownloadJobState.ready,
      requested: paths.length,
      successful: paths.length,
      token: 'tok',
      filename: filename,
    );
  }

  @override
  Future<void> downloadPreparedTo(
    int printerId, {
    required String token,
    required String filename,
    required String savePath,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    calls.add('prepared');
    await File(savePath).writeAsString('bundle');
  }

  @override
  Future<void> downloadFileTo(
    int printerId,
    String path,
    String savePath, {
    void Function(int received, int total)? onProgress,
  }) async {
    calls.add('legacy-file');
    await File(savePath).writeAsString('one');
  }

  @override
  Future<void> downloadZipTo(
    int printerId,
    List<String> paths,
    String savePath, {
    void Function(int received, int total)? onProgress,
  }) async {
    calls.add('legacy-zip');
    await File(savePath).writeAsString('zip');
  }
}

void main() {
  setUp(() {
    final dir = Directory.systemTemp.createTempSync('selection-download');
    PathProviderPlatform.instance = TempDirProvider(dir.path);
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  test('one file is asked for natively, not as a ZIP of one', () async {
    final repo = _Repo();

    final file = await PrinterSelectionDownload(repo, printerId: 1).run(
      files: const [(path: '/a.3mf', size: 10)],
      fileName: 'a.3mf',
      scratchName: 'test.download',
    );

    expect(repo.sentAsZip, isFalse);
    expect(await file.readAsString(), 'bundle');
    // Named after what was downloaded, not after the scratch file.
    expect(file.path, endsWith('/a.3mf'));
  });

  test('several files are bundled', () async {
    final repo = _Repo();

    await PrinterSelectionDownload(repo, printerId: 1).run(
      files: const [(path: '/a.3mf', size: 10), (path: '/b.3mf', size: 20)],
      fileName: 'files.zip',
      scratchName: 'test.download',
    );

    expect(repo.sentAsZip, isTrue);
  });

  test('the sizes go to the repository whole, zeroes and all', () async {
    // Vouching for them is the repository's rule (`_vouchedSizes`), so a screen
    // that could not size an entry must not paper over it here — that decision
    // was written out once per caller before it moved down there.
    final repo = _Repo();

    await PrinterSelectionDownload(repo, printerId: 1).run(
      files: const [(path: '/a.3mf', size: 10), (path: '/b.3mf', size: 0)],
      fileName: 'files.zip',
      scratchName: 'test.download',
    );

    expect(repo.sentSizes, {'/a.3mf': 10, '/b.3mf': 0});
  });

  test(
    'a server without the preparation routes downloads the same bytes',
    () async {
      final single = _Repo(hasJobs: false);
      await PrinterSelectionDownload(single, printerId: 1).run(
        files: const [(path: '/a.3mf', size: 10)],
        fileName: 'a.3mf',
        scratchName: 'test.download',
      );
      expect(single.calls, ['legacy-file']);

      final many = _Repo(hasJobs: false);
      await PrinterSelectionDownload(many, printerId: 1).run(
        files: const [(path: '/a.3mf', size: 10), (path: '/b.3mf', size: 20)],
        fileName: 'files.zip',
        scratchName: 'test.download',
      );
      expect(many.calls, ['legacy-zip']);
    },
  );

  test('cancelling before anything started is not an error', () async {
    // The Cancel that arrives while the screen is still deciding whether this
    // server has the route has nothing to name yet, and must not throw on the
    // way out of a disposed screen.
    await PrinterSelectionDownload(_Repo(), printerId: 1).cancel();
  });

  test(
    'a cancellation inside the capability window still stops the download',
    () async {
      // The window: the screen is dismissed while `supportsDownloadJobs()` is
      // still awaiting the server's version. Nothing exists to cancel yet, and
      // without the latch the preparation started afterwards and ran to
      // completion — the server pulling files off a printer for a screen that had
      // gone.
      final answer = Completer<void>();
      final repo = _Repo(jobsAnswer: answer);
      final download = PrinterSelectionDownload(repo, printerId: 1);

      final running = download.run(
        files: const [(path: '/a.3mf', size: 10)],
        fileName: 'a.3mf',
        scratchName: 'test.download',
      );
      await download.cancel();
      answer.complete();

      await expectLater(
        running,
        throwsA(
          isA<PrinterDownloadFailure>().having(
            (e) => e.reason,
            'reason',
            PrinterDownloadStopped.cancelled,
          ),
        ),
      );
      expect(repo.calls, isEmpty, reason: 'no job was ever started');
    },
  );

  test('the same holds for a server that has no preparation routes', () async {
    // The legacy route cannot be called off once it is in flight, which is all
    // the more reason not to start one nobody wants.
    final answer = Completer<void>();
    final repo = _Repo(hasJobs: false, jobsAnswer: answer);
    final download = PrinterSelectionDownload(repo, printerId: 1);

    final running = download.run(
      files: const [(path: '/a.3mf', size: 10)],
      fileName: 'a.3mf',
      scratchName: 'test.download',
    );
    await download.cancel();
    answer.complete();

    await expectLater(running, throwsA(isA<PrinterDownloadFailure>()));
    expect(repo.calls, isEmpty);
  });
}
