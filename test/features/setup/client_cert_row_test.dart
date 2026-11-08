import 'dart:io';

import 'package:bambuddy_mobile/core/api/client_cert.dart';
import 'package:bambuddy_mobile/core/api/tls_overrides.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/features/setup/client_cert_row.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';
import '../../helpers/fake_file_picker.dart';

PlatformFile _file(String fixture, {String? name}) => PlatformFile(
  name: name ?? fixture,
  size: 0,
  bytes: Uint8List.fromList(
    File('test/fixtures/tls/$fixture').readAsBytesSync(),
  ),
);

void main() {
  late SharedPreferences prefs;
  late FakeFilePicker picker;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    picker = FakeFilePicker();
    FilePicker.platform = picker;
    addTearDown(() => useTls(null, null));
  });

  Future<void> pump(WidgetTester tester) => pumpPhone(
    tester,
    const Scaffold(body: ClientCertRow()),
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );

  Future<ClientCert?> stored(WidgetTester _) =>
      loadClientCert(SettingsRepository(prefs));

  Future<void> import(WidgetTester tester) async {
    await tester.tap(find.text(pl.clientCertImport));
    await tester.pumpAndSettle();
  }

  Future<void> typePassword(WidgetTester tester, String password) async {
    await tester.enterText(
      byLogId('setup.client_cert_password.field'),
      password,
    );
    await tester.tap(byLogId('setup.client_cert_password.save'));
    await tester.pumpAndSettle();
  }

  testWidgets('a file without a password goes in without asking', (
    tester,
  ) async {
    picker.answer = _file('client-nopass.p12', name: 'phone.p12');
    await pump(tester);
    await import(tester);

    expect(byLogId('setup.client_cert_password.field'), findsNothing);
    expect(find.text(pl.clientCertInUse('phone.p12')), findsOneWidget);
    expect((await stored(tester))?.name, 'phone.p12');
  });

  testWidgets('asks for the password, and refuses a wrong one', (tester) async {
    picker.answer = _file('client.p12');
    await pump(tester);
    await import(tester);
    await typePassword(tester, 'wrong');

    expect(find.text(pl.clientCertWrongPassword), findsOneWidget);
    expect(await stored(tester), isNull);

    await import(tester);
    await typePassword(tester, 'fixture');

    expect(find.text(pl.clientCertInUse('client.p12')), findsOneWidget);
    expect((await stored(tester))?.password, 'fixture');
  });

  testWidgets('cancelling the password stores nothing and says nothing', (
    tester,
  ) async {
    picker.answer = _file('client.p12');
    await pump(tester);
    await import(tester);
    await tester.tap(byLogId('setup.client_cert_password.cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(await stored(tester), isNull);
  });

  testWidgets('a certificate without its key is refused', (tester) async {
    picker.answer = _file('client.pem');
    await pump(tester);
    await import(tester);

    expect(find.text(pl.clientCertInvalid), findsOneWidget);
    expect(await stored(tester), isNull);
  });

  testWidgets('removing asks first', (tester) async {
    picker.answer = _file('client-nopass.p12');
    await pump(tester);
    await import(tester);

    await tester.tap(find.byTooltip(pl.clientCertRemove));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('setup.client_cert_remove_confirm.cancel'));
    await tester.pumpAndSettle();
    expect(await stored(tester), isNotNull, reason: 'cancelled');

    await tester.tap(find.byTooltip(pl.clientCertRemove));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('setup.client_cert_remove_confirm.confirm'));
    await tester.pumpAndSettle();

    expect(find.text(pl.clientCertImport), findsOneWidget);
    expect(await stored(tester), isNull);
  });

  testWidgets('a picker that fails says so', (tester) async {
    picker.fails = true;
    await pump(tester);
    await import(tester);

    expect(find.text(pl.customCaPickFailed), findsOneWidget);
  });

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('a long file name fits at text scale $scale', (tester) async {
      await pumpPhone(
        tester,
        const Scaffold(body: ClientCertRow()),
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          initialClientCertProvider.overrideWithValue(
            ClientCert.parse(
              'workshop-reverse-proxy-client-certificate-2026-11.p12',
              File('test/fixtures/tls/client.p12').readAsBytesSync(),
              'fixture',
            ).cert,
          ),
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byTooltip(pl.clientCertRemove), findsOneWidget);
    });
  }
}
