import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/library_file_detail.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:bambuddy_mobile/features/files/file_details_screen.dart';
import 'package:bambuddy_mobile/features/files/file_manager_providers.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../helpers.dart';

/// A listing that is never read; the screen only asks it to refresh.
class _QuietListing extends FileManagerNotifier {
  @override
  Future<FileManagerState> build() async => const FileManagerState();

  @override
  Future<void> refresh() async {}
}

void main() {
  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(Scaffold).first));

  Future<DioAdapter> pumpDetails(
    WidgetTester tester,
    LibraryFileDetail detail,
  ) async {
    final dio = testDio();
    final adapter = mockServer(dio);
    await pumpPhone(
      tester,
      const FileDetailsScreen(fileId: 5, title: 'Benchy'),
      overrides: [
        noServerProfileOverride,
        mediaAuthOverride(),
        libraryRepositoryProvider.overrideWithValue(LibraryRepository(dio)),
        libraryFileDetailProvider(5).overrideWith((ref) async => detail),
        fileManagerProvider.overrideWith(_QuietListing.new),
      ],
    );
    await tester.pumpAndSettle();
    return adapter;
  }

  testWidgets('shows the link, the import source, notes and each photo', (
    tester,
  ) async {
    await pumpDetails(
      tester,
      const LibraryFileDetail(
        externalUrl: 'https://example.com/benchy',
        sourceUrl: 'https://makerworld.com/models/1',
        notes: 'Printed in PETG',
        photos: ['a1b2.jpg', 'c3d4.png'],
      ),
    );

    expect(find.text('https://example.com/benchy'), findsOneWidget);
    expect(find.text('https://makerworld.com/models/1'), findsOneWidget);
    expect(find.text('Printed in PETG'), findsOneWidget);
    expect(byLogId('file_details.photo'), findsNWidgets(2));
  });

  testWidgets('an empty file says so instead of showing blanks', (
    tester,
  ) async {
    await pumpDetails(tester, const LibraryFileDetail());

    final l = l10n(tester);
    expect(find.text(l.fmLinkNone), findsOneWidget);
    expect(find.text(l.fmNotesNone), findsOneWidget);
    expect(find.text(l.fmPhotosEmpty), findsOneWidget);
    expect(find.text(l.fmSource), findsNothing);
  });

  testWidgets('saving an emptied link clears it on the server', (tester) async {
    final adapter = await pumpDetails(
      tester,
      const LibraryFileDetail(externalUrl: 'https://example.com/old'),
    );
    adapter.onPut(
      '/api/v1/library/files/5',
      (s) => s.reply(200, {}),
      data: {'external_url': ''},
    );

    await tester.tap(byLogId('file_details.edit_link'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(byLogId('file_details.link_prompt.save'));
    await tester.pumpAndSettle();

    expect(find.text(l10n(tester).fmLinkSaved), findsOneWidget);
  });

  group('fileWriteMessage', () {
    testWidgets('names the two refusals a user can fix', (tester) async {
      await pumpDetails(tester, const LibraryFileDetail());
      final l = l10n(tester);

      expect(
        fileWriteMessage(
          l,
          const ApiException(AppErrorCode.badResponse, statusCode: 413),
        ),
        l.fmPhotoErrTooLarge,
      );
      expect(
        fileWriteMessage(
          l,
          const ApiException(
            AppErrorCode.badResponse,
            statusCode: 400,
            detail: 'File must be an image (.jpg, .jpeg, .png, .webp)',
          ),
        ),
        l.fmPhotoErrType,
      );
      expect(
        fileWriteMessage(
          l,
          const ApiException(
            AppErrorCode.badResponse,
            statusCode: 422,
            detail: 'external_url must start with http:// or https://',
          ),
        ),
        l.fmLinkErrScheme,
      );
    });
  });

  testWidgets('the photo viewer opens on the photo that was tapped', (
    tester,
  ) async {
    await pumpPhone(
      tester,
      const FilePhotosScreen(fileId: 5, start: 1),
      overrides: [
        noServerProfileOverride,
        mediaAuthOverride(),
        libraryFileDetailProvider(5).overrideWith(
          (ref) async =>
              const LibraryFileDetail(photos: ['a.jpg', 'b.jpg', 'c.jpg']),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('2 / 3'), findsOneWidget);
  });
}
