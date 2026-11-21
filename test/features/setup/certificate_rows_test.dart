import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bambuddy_mobile/core/api/client_cert.dart';
import 'package:bambuddy_mobile/core/api/custom_ca.dart';
import 'package:bambuddy_mobile/core/api/tls_overrides.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/features/setup/certificate_rows.dart';
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
    const Scaffold(body: CertificateRows()),
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );

  CustomCa? storedCa() => SettingsRepository(prefs).loadCustomCa();
  Future<ClientCert?> storedCert() => loadClientCert(SettingsRepository(prefs));

  final importButton = byLogId('setup.cert_import');

  Future<void> import(WidgetTester tester) async {
    await tester.tap(importButton);
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

  group('tells the two apart', () {
    for (final (fixture, kind) in [
      ('ca.der', 'CA'),
      ('ca.pem', 'CA'),
      ('client.pem', 'CA'),
      ('client-nopass.p12', 'client'),
      ('client-bundle.pem', 'client'),
    ]) {
      testWidgets('$fixture is taken as the $kind certificate', (tester) async {
        picker.answer = _file(fixture);
        await pump(tester);
        await import(tester);

        expect(find.byType(SnackBar), findsNothing);
        expect(storedCa()?.name, kind == 'CA' ? fixture : isNull);
        expect((await storedCert())?.name, kind == 'client' ? fixture : null);
      });
    }
  });

  testWidgets('the button stays, and a second import of a kind replaces it', (
    tester,
  ) async {
    await pump(tester);
    picker.answer = _file('ca.pem', name: 'old-root.pem');
    await import(tester);
    picker.answer = _file('client-nopass.p12', name: 'phone.p12');
    await import(tester);

    expect(find.text(pl.customCaTrusted('old-root.pem')), findsOneWidget);
    expect(find.text(pl.clientCertInUse('phone.p12')), findsOneWidget);
    expect(importButton, findsOneWidget);

    picker.answer = _file('ca.der', name: 'new-root.crt');
    await import(tester);

    expect(find.text(pl.customCaTrusted('new-root.crt')), findsOneWidget);
    expect(find.text(pl.customCaTrusted('old-root.pem')), findsNothing);
    expect(storedCa()?.name, 'new-root.crt');
    expect((await storedCert())?.name, 'phone.p12', reason: 'untouched');

    picker.answer = _file('client-bundle.pem', name: 'tablet.pem');
    await import(tester);

    expect(find.text(pl.clientCertInUse('tablet.pem')), findsOneWidget);
    expect((await storedCert())?.name, 'tablet.pem');
    expect(storedCa()?.name, 'new-root.crt', reason: 'untouched');
  });

  testWidgets('disabled, nothing can be imported or removed', (tester) async {
    await SettingsRepository(prefs).saveCustomCa(
      CustomCa.parse(
        'root.pem',
        File('test/fixtures/tls/ca.pem').readAsBytesSync(),
      ),
    );
    await pumpPhone(
      tester,
      const Scaffold(body: CertificateRows(enabled: false)),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialClientCertProvider.overrideWithValue(
          ClientCert.parse(
            'phone.p12',
            File('test/fixtures/tls/client-nopass.p12').readAsBytesSync(),
            '',
          ).cert,
        ),
      ],
    );

    await tester.tap(importButton);
    await tester.tap(find.byTooltip(pl.customCaRemove));
    await tester.tap(find.byTooltip(pl.clientCertRemove));
    await tester.pumpAndSettle();

    expect(picker.opened, 0);
    expect(byLogId('setup.ca_remove_confirm.confirm'), findsNothing);
    expect(byLogId('setup.client_cert_remove_confirm.confirm'), findsNothing);
  });

  for (final fixture in [
    'client.p12',
    'client-encrypted.pem',
    'client-encrypted-legacy.pem',
  ]) {
    testWidgets('$fixture asks for its password, and refuses a wrong one', (
      tester,
    ) async {
      picker.answer = _file(fixture);
      await pump(tester);
      await import(tester);
      await typePassword(tester, 'wrong');

      expect(find.text(pl.clientCertWrongPassword), findsOneWidget);
      expect(await storedCert(), isNull);
      expect(storedCa(), isNull, reason: 'never taken as a CA');

      await import(tester);
      await typePassword(tester, 'fixture');

      expect(find.text(pl.clientCertInUse(fixture)), findsOneWidget);
      expect((await storedCert())?.password, 'fixture');
    });
  }

  for (final (fixture, password) in [
    ('client-mismatch.pem', null),
    ('client-nokey.p12', 'fixture'),
  ]) {
    testWidgets('$fixture is a client certificate that fails, not a CA', (
      tester,
    ) async {
      await pump(tester);
      picker.answer = _file('ca.pem', name: 'root.pem');
      await import(tester);
      picker.answer = _file(fixture);
      await import(tester);
      if (password != null) await typePassword(tester, password);

      expect(find.text(pl.clientCertInvalid), findsOneWidget);
      expect(storedCa()?.name, 'root.pem', reason: 'the CA slot is untouched');
      expect(await storedCert(), isNull);
    });
  }

  testWidgets('cancelling the password stores nothing and says nothing', (
    tester,
  ) async {
    picker.answer = _file('client.p12');
    await pump(tester);
    await import(tester);
    await tester.tap(byLogId('setup.client_cert_password.cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(await storedCert(), isNull);
    expect(storedCa(), isNull);
  });

  testWidgets('removing a CA asks first', (tester) async {
    picker.answer = _file('ca.der', name: 'home-root.crt');
    await pump(tester);
    await import(tester);

    await tester.tap(find.byTooltip(pl.customCaRemove));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('setup.ca_remove_confirm.cancel'));
    await tester.pumpAndSettle();
    expect(storedCa()?.name, 'home-root.crt', reason: 'cancelled');

    await tester.tap(find.byTooltip(pl.customCaRemove));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('setup.ca_remove_confirm.confirm'));
    await tester.pumpAndSettle();

    expect(find.byTooltip(pl.customCaRemove), findsNothing);
    expect(storedCa(), isNull);
  });

  testWidgets('removing a client certificate asks first', (tester) async {
    picker.answer = _file('client-nopass.p12');
    await pump(tester);
    await import(tester);

    await tester.tap(find.byTooltip(pl.clientCertRemove));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('setup.client_cert_remove_confirm.cancel'));
    await tester.pumpAndSettle();
    expect(await storedCert(), isNotNull, reason: 'cancelled');

    await tester.tap(find.byTooltip(pl.clientCertRemove));
    await tester.pumpAndSettle();
    await tester.tap(byLogId('setup.client_cert_remove_confirm.confirm'));
    await tester.pumpAndSettle();

    expect(find.byTooltip(pl.clientCertRemove), findsNothing);
    expect(await storedCert(), isNull);
  });

  testWidgets('reads a picked file from its path', (tester) async {
    picker.answer = PlatformFile(
      name: 'root.pem',
      path: 'test/fixtures/tls/ca.pem',
      size: 0,
    );
    await pump(tester);
    await tester.tap(importButton);
    await settleDisk(tester);

    expect(storedCa()?.name, 'root.pem');
  });

  testWidgets('a file over the cap is refused', (tester) async {
    final big = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('cert_rows');
      addTearDown(() => dir.delete(recursive: true));
      // Sparse, so it costs no disk; reading it whole would not survive.
      // A real certificate up front, so only the cap can refuse it.
      final f = File('${dir.path}/huge.pem');
      final raf = await f.open(mode: FileMode.write);
      await raf.writeFrom(File('test/fixtures/tls/ca.pem').readAsBytesSync());
      await raf.truncate(3 << 30);
      await raf.close();
      return f.path;
    });
    picker.answer = PlatformFile(name: 'huge.pem', path: big, size: 0);
    await pump(tester);
    await tester.tap(importButton);
    await settleDisk(tester);

    expect(find.text(pl.certificateInvalid), findsOneWidget);
    expect(storedCa(), isNull);
    expect(await storedCert(), isNull);
  });

  testWidgets('a file that is not a certificate is refused', (tester) async {
    picker.answer = PlatformFile(
      name: 'notes.txt',
      size: 0,
      bytes: Uint8List.fromList(utf8.encode('hello')),
    );
    await pump(tester);
    await import(tester);

    expect(find.text(pl.certificateInvalid), findsOneWidget);
    expect(storedCa(), isNull);
    expect(await storedCert(), isNull);
  });

  testWidgets('backing out of the picker says nothing', (tester) async {
    await pump(tester);
    await import(tester);

    expect(find.byType(SnackBar), findsNothing);
    expect(storedCa(), isNull);
  });

  testWidgets('a picker that fails says so', (tester) async {
    picker.fails = true;
    await pump(tester);
    await import(tester);

    expect(find.text(pl.customCaPickFailed), findsOneWidget);
  });

  testWidgets('a second tap while the picker opens is dropped', (tester) async {
    picker.gate = Completer<void>();
    await pump(tester);
    // Both in one frame: the button has not been rebuilt disabled yet.
    await tester.tap(importButton);
    await tester.tap(importButton);
    await tester.pump();
    picker.gate!.complete();
    await tester.pumpAndSettle();

    expect(picker.opened, 1);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('leaving while the picker is open stores nothing', (
    tester,
  ) async {
    picker
      ..gate = Completer<void>()
      ..answer = _file('ca.pem');
    await pump(tester);
    await tester.tap(importButton);
    await tester.pump();
    await pumpPhone(
      tester,
      const SizedBox(),
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    picker.gate!.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(storedCa(), isNull);
  });

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('long file names fit at text scale $scale', (tester) async {
      await SettingsRepository(prefs).saveCustomCa(
        CustomCa.parse(
          'my-very-long-home-lab-root-certificate-authority-2026.pem',
          File('test/fixtures/tls/ca.pem').readAsBytesSync(),
        ),
      );
      await pumpPhone(
        tester,
        const Scaffold(body: CertificateRows()),
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
      expect(find.byTooltip(pl.customCaRemove), findsOneWidget);
      expect(find.byTooltip(pl.clientCertRemove), findsOneWidget);
      expect(importButton, findsOneWidget);
    });
  }
}
