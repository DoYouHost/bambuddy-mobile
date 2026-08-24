import 'package:bambuddy_mobile/core/models/printer_file.dart';
import 'package:bambuddy_mobile/data/printer_files_repository.dart';
import 'package:bambuddy_mobile/features/files/printer_file_manager_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
