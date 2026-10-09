import 'dart:typed_data';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/demo/demo_config.dart';
import 'package:bambuddy_mobile/core/demo/demo_label_printer.dart';
import 'package:bambuddy_mobile/core/models/spool_label.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/label_printer_repository.dart';
import 'package:bambuddy_mobile/features/label_printer/label_printer_providers.dart';
import 'package:bambuddy_mobile/features/label_printer/label_printer_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DemoProfile extends ServerProfileNotifier {
  @override
  ServerProfile? build() =>
      const ServerProfile(baseUrl: DemoConfig.baseUrl, authMode: AuthMode.none);
}

/// The demo's label print server: found by a search, answering `/info`, taking
/// a job and refusing what the real one refuses.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('pl'));
  });

  LabelPrinterRepository demoPrinter() =>
      LabelPrinterRepository(createLabelPrinterDio(demoLabelPrinterUrl));

  /// Runs [body] on a real clock — the adapter waits a moment, like a network
  /// would — and hands its error back to the test instead of leaving it to the
  /// zone `runAsync` ran it in.
  Future<R> real<R>(WidgetTester tester, Future<R> Function() body) async {
    final outcome = await tester.runAsync<({R? value, Object? error})>(
      () async {
        try {
          return (value: await body(), error: null);
        } on Object catch (e) {
          return (value: null, error: e);
        }
      },
    );
    if (outcome!.error != null) throw outcome.error!;
    return outcome.value as R;
  }

  testWidgets('answers /info as a 62 x 29 mm printer, connected', (
    tester,
  ) async {
    final info = await real(tester, demoPrinter().info);

    expect(info, isNotNull);
    expect(info!.connected, isTrue);
    expect(info.takes(SpoolLabelTemplate.box62x29), isTrue);
    expect(info.takes(SpoolLabelTemplate.box40x30), isFalse);
  });

  testWidgets('takes a 62 x 29 job', (tester) async {
    await real(
      tester,
      () => demoPrinter().printPdf(
        Uint8List(8),
        filename: 'bambuddy-labels-box_62x29.pdf',
        copies: 2,
      ),
    );
  });

  testWidgets('refuses another shape with the reason, as the real one does', (
    tester,
  ) async {
    await expectLater(
      real(
        tester,
        () => demoPrinter().printPdf(
          Uint8List(8),
          filename: 'bambuddy-labels-box_40x30.pdf',
        ),
      ),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'status', 400)
            .having((e) => e.detail, 'detail', contains('wrong_format')),
      ),
    );
  });

  testWidgets('refuses copies the real one would', (tester) async {
    await expectLater(
      real(
        tester,
        () => demoPrinter().printPdf(
          Uint8List(8),
          filename: 'bambuddy-labels-box_62x29.pdf',
          copies: 51,
        ),
      ),
      throwsA(isA<ApiException>()),
    );
  });

  test('a search finds it, and ends', () async {
    final rounds = await demoDiscoverLabelPrinters().toList();
    expect(rounds.single.single.baseUrl, demoLabelPrinterUrl);
    expect(rounds.single.single.model, 'QL-600');
  });

  test('only its own host is the demo printer', () {
    expect(isDemoLabelPrinter(demoLabelPrinterUrl), isTrue);
    expect(isDemoLabelPrinter('http://192.168.1.40:8000'), isFalse);
    expect(isDemoLabelPrinter('http://demo'), isFalse);
  });

  testWidgets('in demo the search screen finds it and keeps it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          serverProfileProvider.overrideWith(_DemoProfile.new),
        ],
        child: MaterialApp(
          locale: const Locale('pl'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LabelPrinterScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.labelPrinterSearch));
    // The search and the answers are timed, on the test's clock here.
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('Demo label printer'), findsOneWidget);

    await tester.tap(find.text('Demo label printer'));
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();

    expect(prefs.getString('label_printer_url'), demoLabelPrinterUrl);
    expect(prefs.getString('label_printer_name'), 'Demo label printer');
  });
}
