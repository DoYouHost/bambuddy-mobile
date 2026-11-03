import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/features/files/printer_download_job.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  group('prepareFailureText', () {
    test('cancelled maps to the cancelled line', () {
      expect(
        prepareFailureText(
          const PrinterDownloadFailure(PrinterDownloadStopped.cancelled),
          l10n,
        ),
        l10n.pfmDownloadCancelled,
      );
    });

    test(
      'failed with the server detail shows the detail, not the generic line',
      () {
        expect(
          prepareFailureText(
            const PrinterDownloadFailure(
              PrinterDownloadStopped.failed,
              detail: 'Selection exceeds the limit',
            ),
            l10n,
          ),
          'Selection exceeds the limit',
        );
      },
    );

    test('failed without a detail falls back to the prepare-failed line', () {
      expect(
        prepareFailureText(
          const PrinterDownloadFailure(PrinterDownloadStopped.failed),
          l10n,
        ),
        l10n.pfmDownloadPrepareFailed,
      );
    });

    test('failed with an empty detail still shows the empty string', () {
      // An empty string is not null, so the `??` keeps it. Pinned so a later
      // "treat empty as absent" change is a conscious one.
      expect(
        prepareFailureText(
          const PrinterDownloadFailure(
            PrinterDownloadStopped.failed,
            detail: '',
          ),
          l10n,
        ),
        '',
      );
    });

    test('lost maps to the prepare-failed line, ignoring any detail', () {
      expect(
        prepareFailureText(
          const PrinterDownloadFailure(
            PrinterDownloadStopped.lost,
            detail: 'ignored',
          ),
          l10n,
        ),
        l10n.pfmDownloadPrepareFailed,
      );
    });
  });

  group('downloadRefusalText', () {
    String? refusalFor(int? statusCode) => downloadRefusalText(
      ApiException(AppErrorCode.badResponse, statusCode: statusCode),
      l10n,
    );

    test('413 maps to the too-large line', () {
      expect(refusalFor(413), l10n.pfmDownloadTooLarge);
    });

    test('504 maps to the took-too-long line', () {
      expect(refusalFor(504), l10n.pfmDownloadTookTooLong);
    });

    test('507 maps to the no-server-space line', () {
      expect(refusalFor(507), l10n.pfmDownloadNoServerSpace);
    });

    test('500 has no specific line', () {
      expect(refusalFor(500), isNull);
    });

    test('a missing status has no specific line', () {
      expect(refusalFor(null), isNull);
    });
  });
}
