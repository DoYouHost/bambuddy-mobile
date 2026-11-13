import 'dart:io';

import 'package:bambuddy_mobile/core/api/client_cert.dart';
import 'package:bambuddy_mobile/core/api/custom_ca.dart';
import 'package:bambuddy_mobile/core/api/tls_overrides.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/features/settings/certificates_card.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

final _ca = CustomCa.parse(
  'root.pem',
  File('test/fixtures/tls/ca.pem').readAsBytesSync(),
);
final _cert = ClientCert.parse(
  'phone.p12',
  File('test/fixtures/tls/client.p12').readAsBytesSync(),
  'fixture',
).cert;

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    addTearDown(() {
      useTls(null, null);
    });
  });

  /// Stored as the app would have stored them, so removing has something to
  /// remove.
  Future<void> pump(
    WidgetTester tester, {
    bool ca = false,
    bool cert = false,
    double scale = 1.0,
  }) async {
    final settings = SettingsRepository(prefs);
    if (ca) await settings.saveCustomCa(_ca);
    if (cert) {
      await ClientCertStore().write(_cert);
      await settings.saveHasClientCert(true);
    }
    await pumpPhone(
      tester,
      const Scaffold(body: SingleChildScrollView(child: CertificatesCard())),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialClientCertProvider.overrideWithValue(cert ? _cert : null),
      ],
      builder: textScaled(scale),
    );
  }

  final removeAll = byLogId('app_settings.certificates_remove_all');

  testWidgets('offers the import and no "remove all" while empty', (
    tester,
  ) async {
    await pump(tester);

    expect(byLogId('app_settings.cert_import'), findsOneWidget);
    expect(removeAll, findsNothing);
  });

  testWidgets('one certificate is removed by its own button only', (
    tester,
  ) async {
    await pump(tester, cert: true);

    expect(find.byTooltip(pl.clientCertRemove), findsOneWidget);
    expect(removeAll, findsNothing);
  });

  testWidgets('"remove all" asks first, then removes both', (tester) async {
    await pump(tester, ca: true, cert: true);

    await tester.tap(removeAll);
    await tester.pumpAndSettle();
    await tester.tap(
      byLogId('app_settings.certificates_remove_all_confirm.cancel'),
    );
    await tester.pumpAndSettle();
    expect(SettingsRepository(prefs).loadCustomCa(), isNotNull);
    expect(SettingsRepository(prefs).loadHasClientCert(), isTrue);

    await tester.tap(removeAll);
    await tester.pumpAndSettle();
    await tester.tap(
      byLogId('app_settings.certificates_remove_all_confirm.confirm'),
    );
    await tester.pumpAndSettle();

    expect(SettingsRepository(prefs).loadCustomCa(), isNull);
    expect(await loadClientCert(SettingsRepository(prefs)), isNull);
    expect(await ClientCertStore().read(), isNull);
    expect(removeAll, findsNothing);
    expect(byLogId('app_settings.cert_import'), findsOneWidget);
  });

  testWidgets('each row logs under the settings screen', (tester) async {
    await pump(tester, ca: true, cert: true);

    expect(byLogId('app_settings.ca_remove'), findsOneWidget);
    expect(byLogId('app_settings.client_cert_remove'), findsOneWidget);
  });

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('fits with both at text scale $scale', (tester) async {
      await pump(tester, ca: true, cert: true, scale: scale);

      expect(tester.takeException(), isNull);
      expect(removeAll, findsOneWidget);
    });
  }
}
