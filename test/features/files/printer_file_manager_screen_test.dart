import 'dart:io';

import 'package:bambuddy_mobile/core/models/printer_file.dart';
import 'package:bambuddy_mobile/data/printer_files_repository.dart';
import 'package:bambuddy_mobile/features/common/dash_progress.dart';
import 'package:bambuddy_mobile/features/files/printer_file_manager_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

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


void main() {
  Future<AppLocalizations> pumpWith(
    WidgetTester tester,
    PrinterFileListing listing,
  ) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        printerFilesRepositoryProvider.overrideWithValue(_FakeRepo(listing)),
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
}
