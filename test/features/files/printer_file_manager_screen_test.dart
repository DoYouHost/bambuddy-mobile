import 'dart:convert';
import 'dart:io';

import 'package:bambuddy_mobile/core/diagnostics/diagnostic_recorder.dart';
import 'package:bambuddy_mobile/core/diagnostics/session_facts.dart';
import 'package:bambuddy_mobile/core/models/printer_download_job.dart';
import 'package:bambuddy_mobile/core/models/printer_file.dart';
import 'package:bambuddy_mobile/data/printer_files_repository.dart';
import 'package:bambuddy_mobile/features/common/dash_progress.dart';
import 'package:bambuddy_mobile/features/files/printer_file_manager_screen.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// A listing this test decides, and a storage read that answers nothing — the
/// screen fires it on init and a real one would leave a hanging Dio timer.
class _FakeRepo extends PrinterFilesRepository {
  _FakeRepo(this.listing) : super(Dio());

  final PrinterFileListing listing;

  @override
  Future<PrinterFileListing> listFiles(int printerId, String path) async =>
      listing;

  @override
  Future<PrinterStorage> fetchStorage(int printerId) async =>
      const PrinterStorage();

  /// Writes something where the real one streams the printer's bytes — the
  /// point of these tests is the file that lands, not how it got there.
  @override
  Future<void> downloadFileTo(
    int printerId,
    String path,
    String savePath, {
    void Function(int received, int total)? onProgress,
  }) async {
    await File(savePath).writeAsString('a printed thing');
  }
}

/// A server that prepares downloads (server #2850). [poll] decides what each
/// poll reports, so a test can hold the job in `preparing` for as long as it
/// needs to look at the screen.
class _JobRepo extends _FakeRepo {
  _JobRepo(
    super.listing, {
    required this.started,
    required this.poll,
  });

  final PrinterDownloadJob started;
  final PrinterDownloadJob Function() poll;

  bool cancelled = false;
  bool fetched = false;

  @override
  Future<bool> supportsDownloadJobs() async => true;

  @override
  Future<PrinterDownloadJob?> startDownloadJob(
    int printerId, {
    required List<String> paths,
    required Map<String, int> sizes,
    required String filename,
    bool asZip = true,
  }) async =>
      started;

  @override
  Future<PrinterDownloadJob?> downloadJob(int printerId, String jobId) async =>
      poll();

  @override
  Future<void> cancelDownloadJob(int printerId, String jobId) async {
    cancelled = true;
  }

  @override
  Future<void> downloadPreparedTo(
    int printerId, {
    required String token,
    required String filename,
    required String savePath,
    void Function(int received, int total)? onProgress,
  }) async {
    fetched = true;
    await File(savePath).writeAsString('a prepared bundle');
  }
}

PrinterDownloadJob _job(
  PrinterDownloadJobState state, {
  int requested = 1,
  int successful = 0,
  int failed = 0,
  String? token,
}) =>
    PrinterDownloadJob(
      jobId: 'j1',
      printerId: 1,
      state: state,
      requested: requested,
      successful: successful,
      failed: failed,
      token: token,
    );

void main() {
  Future<AppLocalizations> pumpWith(
    WidgetTester tester,
    PrinterFileListing listing, {
    PrinterFilesRepository? repo,
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        printerFilesRepositoryProvider
            .overrideWithValue(repo ?? _FakeRepo(listing)),
      ],
      child: plApp(const PrinterFileManagerScreen(
        printerId: 1,
        printerName: 'Ultron',
      )),
    ));
    await tester.pumpAndSettle();
    return AppLocalizations.of(
      tester.element(find.byType(PrinterFileManagerScreen)),
    );
  }

  testWidgets('an empty folder still reads as an empty folder', (tester) async {
    final l10n = await pumpWith(tester, const PrinterFileListing());

    expect(find.text(l10n.pfmEmpty), findsOneWidget);
    expect(find.text(l10n.pfmPrinterUnavailable), findsNothing);
  });

  testWidgets('the unavailable warning says so, and offers a retry',
      (tester) async {
    final l10n = await pumpWith(
      tester,
      const PrinterFileListing(printerUnavailable: true),
    );

    expect(find.text(l10n.pfmPrinterUnavailable), findsOneWidget);
    expect(find.text(l10n.pfmEmpty), findsNothing);
    expect(find.widgetWithText(FilledButton, l10n.retry), findsOneWidget);
  });

  testWidgets('files render whatever the warnings say', (tester) async {
    await pumpWith(
      tester,
      const PrinterFileListing(
        files: [
          PrinterFile(
            name: 'a.3mf',
            path: '/a.3mf',
            isDirectory: false,
            size: 1024,
          ),
        ],
        printerUnavailable: true,
      ),
    );

    expect(find.text('a.3mf'), findsOneWidget);
  });

  /// A download lands in the app's private cache only so the save dialog has a
  /// path to copy from. `flutter_file_dialog` finishes that copy before it
  /// returns, so the copy is dead the moment it does — and left behind, it was
  /// one duplicate per distinct file name until Android ran short of storage.
  ///
  /// Nothing here goes near the printer: `deleteFile` is a separate, confirmed
  /// action, and a download never removed the original.
  /// The screen's own answer to "am I done": the ring is on screen exactly
  /// while the download and the dialog are.
  bool stillWorking(WidgetTester tester) =>
      find.byType(DashSpinner).evaluate().isNotEmpty;

  group('the cache copy does not outlive the save dialog', () {
    const channel = MethodChannel('flutter_file_dialog');
    late Directory cache;
    String? savedTo;

    setUp(() async {
      cache = await Directory.systemTemp.createTemp('pfm-cache');
      PathProviderPlatform.instance = TempDirProvider(cache.path);
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => savedTo);
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      if (cache.existsSync()) await cache.delete(recursive: true);
    });

    /// Selects the one file on screen and downloads it.
    Future<AppLocalizations> downloadTheFile(WidgetTester tester) async {
      final l10n = await pumpWith(
        tester,
        const PrinterFileListing(
          files: [
            PrinterFile(
              name: 'benchy.3mf',
              path: '/benchy.3mf',
              isDirectory: false,
              size: 15,
            ),
          ],
        ),
      );
      await tester.tap(find.text('benchy.3mf'));
      await tester.pumpAndSettle();
      // Real disk writes and a real platform reply, neither of which the test
      // framework's clock drives — and the progress ring keeps scheduling
      // frames meanwhile, so `pumpAndSettle` alone would only ever time out.
      await tester.runAsync(() async {
        await tester.tap(find.text(l10n.pfmDownload));
        // One frame first, or the ring the loop waits on is not in the tree yet
        // and the wait ends before the download has begun.
        await tester.pump();
        for (var i = 0; i < 50 && stillWorking(tester); i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
      return l10n;
    }

    testWidgets('a saved file leaves nothing behind', (tester) async {
      savedTo = '/storage/emulated/0/Download/benchy.3mf';

      final l10n = await downloadTheFile(tester);

      expect(find.text(l10n.pfmDownloadSaved), findsOneWidget);
      expect(cache.listSync(), isEmpty,
          reason: 'the copy the dialog already took stayed in the cache');
    });

    testWidgets('backing out of the dialog leaves nothing behind either',
        (tester) async {
      // A cancel is where this leaked worst: nothing was saved, so nothing told
      // the user a full-size copy had been kept.
      savedTo = null;

      await downloadTheFile(tester);

      expect(cache.listSync(), isEmpty);
    });

    testWidgets('a dialog that throws leaves nothing behind either',
        (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              channel, (call) async => throw PlatformException(code: 'no_room'));

      final l10n = await downloadTheFile(tester);

      expect(find.text(l10n.pfmDownloadNotSaved), findsOneWidget);
      expect(cache.listSync(), isEmpty);
    });
  });

  group('a download the server prepares first', () {
    const channel = MethodChannel('flutter_file_dialog');
    late Directory cache;
    String? savedTo;

    const oneFile = PrinterFileListing(
      files: [
        PrinterFile(
          name: 'benchy.3mf',
          path: '/benchy.3mf',
          isDirectory: false,
          size: 15,
        ),
      ],
    );

    setUp(() async {
      cache = await Directory.systemTemp.createTemp('pfm-job-cache');
      PathProviderPlatform.instance = TempDirProvider(cache.path);
      TestWidgetsFlutterBinding.ensureInitialized();
      savedTo = '/storage/emulated/0/Download/benchy.3mf';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => savedTo);
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      if (cache.existsSync()) await cache.delete(recursive: true);
    });

    /// Selects the file and presses Download, then lets real asynchronous work
    /// run for up to [budget] — the transfer, the platform reply and the poll
    /// delays are all real time, which the test clock does not drive.
    Future<void> startDownload(
      WidgetTester tester,
      AppLocalizations l10n, {
      Duration budget = const Duration(milliseconds: 400),
      bool Function()? until,
    }) async {
      await tester.tap(find.text('benchy.3mf'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text(l10n.pfmDownload));
        await tester.pump();
        final deadline = DateTime.now().add(budget);
        while (DateTime.now().isBefore(deadline)) {
          if (until != null && until()) return;
          await tester.pump(const Duration(milliseconds: 20));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
    }

    testWidgets('a bundle that is ready at once is fetched by its token',
        (tester) async {
      final repo = _JobRepo(
        oneFile,
        started: _job(PrinterDownloadJobState.ready, token: 'tok'),
        poll: () => _job(PrinterDownloadJobState.ready, token: 'tok'),
      );
      final l10n = await pumpWith(tester, oneFile, repo: repo);

      await startDownload(tester, l10n);
      await tester.pumpAndSettle();

      expect(repo.fetched, isTrue);
      expect(find.text(l10n.pfmDownloadSaved), findsOneWidget);
      expect(cache.listSync(), isEmpty);
    });

    testWidgets('the wait says the server is preparing, and can be called off',
        (tester) async {
      // Held in `preparing`: the legacy route would be a silent socket here,
      // which is the whole reason this path exists.
      final repo = _JobRepo(
        oneFile,
        started: _job(PrinterDownloadJobState.preparing, requested: 3),
        poll: () => _job(PrinterDownloadJobState.preparing, requested: 3),
      );
      final l10n = await pumpWith(tester, oneFile, repo: repo);

      await startDownload(tester, l10n);

      expect(find.text(l10n.pfmPreparingOnServer), findsOneWidget);
      expect(find.text(l10n.pfmSelected(1)), findsNothing);

      final cancel = find.byIcon(Icons.close);
      expect(cancel, findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(cancel);
        await tester.pump();
        // Long enough for the poll the run is sleeping on to come round and
        // notice the cancellation.
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (DateTime.now().isBefore(deadline)) {
          if (find.text(l10n.pfmDownloadCancelled).evaluate().isNotEmpty) break;
          await tester.pump(const Duration(milliseconds: 50));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pump();

      expect(repo.cancelled, isTrue);
      expect(repo.fetched, isFalse);
      expect(find.text(l10n.pfmDownloadCancelled), findsOneWidget);
      expect(cache.listSync(), isEmpty);
    });

    testWidgets('a bundle short of the selection says what was left out',
        (tester) async {
      final repo = _JobRepo(
        oneFile,
        started: _job(
          PrinterDownloadJobState.ready,
          requested: 3,
          successful: 1,
          failed: 2,
          token: 'tok',
        ),
        poll: () => _job(PrinterDownloadJobState.ready, token: 'tok'),
      );
      final l10n = await pumpWith(tester, oneFile, repo: repo);

      await startDownload(tester, l10n);
      await tester.pumpAndSettle();

      expect(
        find.textContaining(l10n.pfmDownloadPartial(2)),
        findsOneWidget,
        reason: 'a ZIP two files short must not read as a clean save',
      );
    });

    testWidgets('a preparation the server gives up on says why',
        (tester) async {
      final repo = _JobRepo(
        oneFile,
        started: _job(PrinterDownloadJobState.preparing),
        poll: () => PrinterDownloadJob.fromJson(const {
          'job_id': 'j1',
          'printer_id': 1,
          'state': 'failed',
          'requested': 1,
          'message': 'The server has no room to prepare this download',
        }),
      );
      final l10n = await pumpWith(tester, oneFile, repo: repo);

      await startDownload(
        tester,
        l10n,
        budget: const Duration(seconds: 3),
        until: () => find.textContaining('no room').evaluate().isNotEmpty,
      );
      await tester.pump();

      expect(find.textContaining('no room'), findsOneWidget);
      expect(repo.fetched, isFalse);
    });

    testWidgets('a server without the route still downloads the file',
        (tester) async {
      // The legacy path, which every server generation serves: no phase to
      // report and no Cancel, but the same bytes on disk at the end.
      final l10n = await pumpWith(tester, oneFile);

      await startDownload(tester, l10n);
      await tester.pumpAndSettle();

      expect(find.text(l10n.pfmDownloadSaved), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
    });
  });

  testWidgets('a cancelled preparation is recorded, without the file names',
      (tester) async {
    // The report this exists for says "I pressed Download and nothing came".
    // What settles it is the state and the counts — and what must never be in
    // there is what the user called their models.
    SharedPreferences.setMockInitialValues({});
    final recorder = DiagnosticRecorder(
      settings: SettingsRepository(await SharedPreferences.getInstance()),
      loadFacts: () async =>
          const SessionFacts(app: '0.12.1+1201000', flavor: 'mobile'),
      resolveDirectory: () async => null,
    );
    addTearDown(recorder.discard);
    await recorder.start();

    const listing = PrinterFileListing(
      files: [
        PrinterFile(
          name: 'Mum birthday present.3mf',
          path: '/model/Mum birthday present.3mf',
          isDirectory: false,
          size: 15,
        ),
      ],
    );
    final repo = _JobRepo(
      listing,
      started: _job(PrinterDownloadJobState.preparing, requested: 4),
      poll: () => _job(PrinterDownloadJobState.preparing, requested: 4),
    );
    final l10n = await pumpWith(tester, listing, repo: repo);

    await tester.tap(find.text('Mum birthday present.3mf'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text(l10n.pfmDownload));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (DateTime.now().isBefore(deadline)) {
        if (find.text(l10n.pfmDownloadCancelled).evaluate().isNotEmpty) break;
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();

    final jsonl = await recorder.stop();
    final records = [
      for (final line in const LineSplitter().convert(jsonl))
        if (jsonDecode(line) case final Map<String, dynamic> row
            when row['evt'] == 'printer_download')
          row,
    ];

    expect(records, hasLength(1));
    expect(records.single['state'], 'cancelled');
    expect(records.single['requested'], 4);
    expect(jsonl, isNot(contains('Mum birthday present')));
  });
}
