import 'package:bambuddy_mobile/core/models/printer_download_job.dart';
import 'package:bambuddy_mobile/data/printer_files_repository.dart';
import 'package:bambuddy_mobile/features/files/printer_download_job.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// A repository that answers from a script instead of from a server: the run's
/// whole job is to react to a sequence of states, and the sequence is what a
/// real server makes hardest to arrange.
class _ScriptedRepo extends PrinterFilesRepository {
  _ScriptedRepo({required this.start, required this.polls}) : super(Dio());

  /// Null stands for the 404 an older server answers.
  final PrinterDownloadJob? start;

  /// One entry per poll; a null entry is the job having vanished.
  final List<PrinterDownloadJob?> polls;

  final List<String> calls = [];
  String? downloadedToken;
  String? downloadedFilename;

  @override
  Future<PrinterDownloadJob?> startDownloadJob(
    int printerId, {
    required List<String> paths,
    required Map<String, int> sizes,
    required String filename,
    bool asZip = true,
  }) async {
    calls.add('start');
    return start;
  }

  @override
  Future<PrinterDownloadJob?> downloadJob(int printerId, String jobId) async {
    calls.add('poll');
    return polls.isEmpty ? null : polls.removeAt(0);
  }

  @override
  Future<void> cancelDownloadJob(int printerId, String jobId) async {
    calls.add('cancel');
  }

  @override
  Future<void> downloadPreparedTo(
    int printerId, {
    required String token,
    required String filename,
    required String savePath,
    void Function(int received, int total)? onProgress,
  }) async {
    calls.add('download');
    downloadedToken = token;
    downloadedFilename = filename;
    onProgress?.call(10, 10);
  }
}

PrinterDownloadJob _job(
  String state, {
  int requested = 2,
  int successful = 0,
  int failed = 0,
  String? token,
  String? message,
  String? filename,
}) =>
    PrinterDownloadJob(
      jobId: 'j1',
      printerId: 1,
      state: switch (state) {
        'queued' => PrinterDownloadJobState.queued,
        'preparing' => PrinterDownloadJobState.preparing,
        'ready' => PrinterDownloadJobState.ready,
        'failed' => PrinterDownloadJobState.failed,
        'cancelled' => PrinterDownloadJobState.cancelled,
        _ => PrinterDownloadJobState.unknown,
      },
      requested: requested,
      successful: successful,
      failed: failed,
      token: token,
      message: message,
      filename: filename,
    );

Future<bool> _run(
  _ScriptedRepo repo, {
  void Function(PrinterDownloadJob job)? onJob,
  PrinterDownloadRun? using,
}) =>
    (using ?? PrinterDownloadRun(repo, printerId: 1, pollInterval: Duration.zero))
        .download(
      paths: const ['/a.3mf', '/b.3mf'],
      sizes: const {'/a.3mf': 10, '/b.3mf': 20},
      filename: 'X1-files.zip',
      asZip: true,
      savePath: '/tmp/x.zip',
      onJob: onJob,
    );

void main() {
  test('a server without the route downloads nothing and says so', () async {
    // The caller reads this as "use the legacy download-zip", so it must not
    // throw and must not have touched anything.
    final repo = _ScriptedRepo(start: null, polls: []);

    expect(await _run(repo), isFalse);
    expect(repo.calls, ['start']);
  });

  test('polls until ready, then streams what was staged', () async {
    final repo = _ScriptedRepo(
      start: _job('queued'),
      polls: [
        _job('preparing', successful: 1),
        _job('ready', successful: 2, token: 'tok', filename: 'ready.zip'),
      ],
    );
    final seen = <PrinterDownloadJob>[];

    expect(await _run(repo, onJob: seen.add), isTrue);
    expect(repo.calls, ['start', 'poll', 'poll', 'download']);
    expect(repo.downloadedToken, 'tok');
    // The name the job carries wins over the one asked for: it is what the
    // server sanitised and prepared under.
    expect(repo.downloadedFilename, 'ready.zip');
    // Every state reaches the UI, including the one it started in.
    expect(
      seen.map((j) => j.state),
      [
        PrinterDownloadJobState.queued,
        PrinterDownloadJobState.preparing,
        PrinterDownloadJobState.ready,
      ],
    );
  });

  test('a phase this app does not know keeps it polling', () async {
    final repo = _ScriptedRepo(
      start: _job('queued'),
      polls: [
        _job('compressing'),
        _job('ready', successful: 2, token: 'tok'),
      ],
    );

    expect(await _run(repo), isTrue);
    expect(repo.calls, ['start', 'poll', 'poll', 'download']);
  });

  test('a failed job carries the server\'s reason out', () async {
    final repo = _ScriptedRepo(
      start: _job('preparing'),
      polls: [_job('failed', message: 'No room to prepare this download')],
    );

    await expectLater(
      _run(repo),
      throwsA(isA<PrinterDownloadFailure>()
          .having((e) => e.reason, 'reason', PrinterDownloadStopped.failed)
          .having((e) => e.detail, 'detail', contains('No room'))),
    );
    expect(repo.calls, isNot(contains('download')));
  });

  test('a job that vanishes mid-preparation is lost, not failed', () async {
    // The server prunes abandoned staging and drops every job on restart, so
    // this is a preparation that will never finish rather than one that broke.
    final repo = _ScriptedRepo(start: _job('preparing'), polls: [null]);

    await expectLater(
      _run(repo),
      throwsA(isA<PrinterDownloadFailure>()
          .having((e) => e.reason, 'reason', PrinterDownloadStopped.lost)),
    );
  });

  test('a job cancelled elsewhere ends as cancelled here too', () async {
    final repo = _ScriptedRepo(start: _job('preparing'), polls: [_job('cancelled')]);

    await expectLater(
      _run(repo),
      throwsA(isA<PrinterDownloadFailure>()
          .having((e) => e.reason, 'reason', PrinterDownloadStopped.cancelled)),
    );
  });

  test('ready without a token cannot be fetched and is not retried', () async {
    final repo = _ScriptedRepo(
      start: _job('preparing'),
      polls: [_job('ready', successful: 2)],
    );

    await expectLater(
      _run(repo),
      throwsA(isA<PrinterDownloadFailure>()
          .having((e) => e.reason, 'reason', PrinterDownloadStopped.lost)),
    );
    expect(repo.calls, isNot(contains('download')));
  });

  test('cancel stops the preparation and tells the server', () async {
    // Enough polls that the run would go on without the cancel.
    final repo = _ScriptedRepo(
      start: _job('preparing'),
      polls: [
        _job('preparing', successful: 1),
        _job('ready', successful: 2, token: 'tok'),
      ],
    );
    final run =
        PrinterDownloadRun(repo, printerId: 1, pollInterval: Duration.zero);

    final result = _run(repo, using: run, onJob: (job) {
      // Cancel the moment the server reports it is working, which is when the
      // button appears on screen.
      if (job.state == PrinterDownloadJobState.preparing) run.cancel();
    });

    await expectLater(
      result,
      throwsA(isA<PrinterDownloadFailure>()
          .having((e) => e.reason, 'reason', PrinterDownloadStopped.cancelled)),
    );
    expect(repo.calls, contains('cancel'));
    expect(repo.calls, isNot(contains('download')));
  });

  test('cancel before a job exists asks the server for nothing', () async {
    final repo = _ScriptedRepo(start: null, polls: []);
    final run = PrinterDownloadRun(repo, printerId: 1);

    await run.cancel();

    expect(repo.calls, isEmpty);
  });

  test('cancel after the bundle is fetched has nothing left to stop', () async {
    // The token is spent and the server has deleted the staging copy, so a
    // DELETE here would only 404.
    final repo = _ScriptedRepo(
      start: _job('ready', successful: 2, token: 'tok'),
      polls: [],
    );
    final run =
        PrinterDownloadRun(repo, printerId: 1, pollInterval: Duration.zero);

    expect(await _run(repo, using: run), isTrue);
    await run.cancel();

    expect(repo.calls, ['start', 'download']);
  });
}
