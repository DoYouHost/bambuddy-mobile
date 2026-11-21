import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bambuddy_mobile/core/api/api_client.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/client_cert.dart';
import 'package:bambuddy_mobile/core/api/custom_ca.dart';
import 'package:bambuddy_mobile/core/api/tls_overrides.dart';
import 'package:bambuddy_mobile/core/auth/auth_service.dart';
import 'package:bambuddy_mobile/core/auth/credentials_store.dart';
import 'package:bambuddy_mobile/core/notifications/background_api.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/namespaced_secure_storage.dart';

// Fixtures in test/fixtures/tls: a client certificate signed by a throwaway
// client CA (its key discarded), as `client.p12` (password "fixture", OpenSSL
// 3 defaults), `client-legacy.p12` (the same with `-legacy`, as older tools
// write it), `client-nopass.p12`, `client-bundle.pem` (key and certificate)
// and `client.pem` (the certificate alone).
List<int> _fixture(String name) =>
    File('test/fixtures/tls/$name').readAsBytesSync();

CustomCa? _rootCa() => CustomCa.parse('root.pem', _fixture('ca.pem'));

ClientCert _cert() =>
    ClientCert.parse('phone.p12', _fixture('client.p12'), 'fixture').cert!;

void main() {
  group('parse', () {
    test('takes a .p12 with its password', () {
      final r = ClientCert.parse(
        'phone.p12',
        _fixture('client.p12'),
        'fixture',
      );
      expect(r.cert?.name, 'phone.p12');
      expect(r.cert?.password, 'fixture');
      expect(r.wrongPassword, isFalse);
    });

    test('takes a .p12 in the legacy encryption', () {
      expect(
        ClientCert.parse(
          'old.pfx',
          _fixture('client-legacy.p12'),
          'fixture',
        ).cert,
        isNotNull,
      );
    });

    test('takes a .p12 without a password, and a PEM with its key', () {
      expect(
        ClientCert.parse('open.p12', _fixture('client-nopass.p12'), '').cert,
        isNotNull,
      );
      expect(
        ClientCert.parse('bundle.pem', _fixture('client-bundle.pem'), '').cert,
        isNotNull,
      );
    });

    test('a missing or wrong password is told apart from a bad file', () {
      for (final password in ['', 'wrong']) {
        final r = ClientCert.parse(
          'phone.p12',
          _fixture('client.p12'),
          password,
        );
        expect(r.cert, isNull);
        expect(r.wrongPassword, isTrue, reason: 'password "$password"');
      }
    });

    for (final fixture in [
      'client-encrypted.pem',
      'client-encrypted-legacy.pem',
    ]) {
      test('a PEM whose key is encrypted, $fixture, asks for its password', () {
        for (final password in ['', 'wrong']) {
          final r = ClientCert.parse('k.pem', _fixture(fixture), password);
          expect((r.cert, r.wrongPassword), (null, true), reason: password);
        }
        expect(
          ClientCert.parse('k.pem', _fixture(fixture), 'fixture').cert,
          isNotNull,
        );
      });
    }

    test('holdsKey sees a PEM key, plain or encrypted, and nothing else', () {
      for (final f in [
        'client-bundle.pem',
        'client-encrypted.pem',
        'client-encrypted-legacy.pem',
        'client-mismatch.pem',
      ]) {
        expect(ClientCert.holdsKey(_fixture(f)), isTrue, reason: f);
      }
      for (final f in ['ca.pem', 'ca.der', 'client.pem', 'client.p12']) {
        expect(ClientCert.holdsKey(_fixture(f)), isFalse, reason: f);
      }
    });

    test('refuses what holds no certificate with its key', () {
      for (final bytes in [
        _fixture('client.pem'),
        _fixture('client-mismatch.pem'),
        utf8.encode('hello'),
        const <int>[],
      ]) {
        final r = ClientCert.parse('x', bytes, '');
        expect((r.cert, r.wrongPassword), (null, false));
      }
    });

    test('refuses a file over the cap', () {
      final pem = _fixture('client-bundle.pem');
      final atCap = [
        ...pem,
        ...List.filled(ClientCert.maxBytes - pem.length, 10),
      ];
      expect(ClientCert.parse('b.pem', atCap, '').cert, isNotNull);
      expect(ClientCert.parse('b.pem', [...atCap, 10], '').cert, isNull);
    });

    test('survives a round trip through storage', () {
      final cert = _cert();
      final back = ClientCert.fromJson(
        jsonDecode(jsonEncode(cert.toJson())) as Map<String, dynamic>,
      );
      expect(back, cert);
    });
  });

  group('store', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('writes, reads back and clears', () async {
      final store = ClientCertStore();
      await store.write(_cert());
      expect(await store.read(), _cert());
      await store.write(null);
      expect(await store.read(), isNull);
    });

    test('an unreadable entry reads as none', () async {
      FlutterSecureStorage.setMockInitialValues({'client_cert': '{not json'});
      expect(await ClientCertStore().read(), isNull);
    });

    test('is not read while preferences say there is none', () async {
      FlutterSecureStorage.setMockInitialValues({
        'client_cert': jsonEncode(_cert().toJson()),
      });
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsRepository(
        await SharedPreferences.getInstance(),
      );
      expect(await loadClientCert(settings), isNull);
      await settings.saveHasClientCert(true);
      expect(await loadClientCert(settings), _cert());
    });
  });

  group('present', () {
    late HttpServer server;
    late Uri url;

    setUp(() async {
      // The test binding answers every HttpClient with a canned 400; these
      // tests need the real handshake.
      final mocked = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = mocked);
      // `dart:io` can ask for a certificate but not insist on one, so the
      // server answers with what it got, as nginx's `$ssl_client_s_dn` would.
      final context = SecurityContext()
        ..useCertificateChainBytes(_fixture('server.pem'))
        ..usePrivateKeyBytes(_fixture('server.key'))
        ..setTrustedCertificatesBytes(_fixture('client-ca.pem'));
      server = await HttpServer.bindSecure(
        '127.0.0.1',
        0,
        context,
        requestClientCertificate: true,
      );
      server.listen(
        (r) => r.response
          ..write(r.certificate?.subject ?? 'none')
          ..close(),
      );
      url = Uri.parse('https://127.0.0.1:${server.port}/');
      // The server's own certificate is signed by a private CA as well, so
      // every case here also proves the two share one context.
      useTls(_rootCa(), null);
    });

    tearDown(() async {
      useTls(null, null);
      await server.close(force: true);
    });

    Future<String> get() async {
      final client = HttpClient();
      try {
        final response = await (await client.getUrl(url)).close();
        return await response.transform(utf8.decoder).join();
      } finally {
        client.close(force: true);
      }
    }

    const subject = '/CN=bambuddy-mobile test client';

    test('is shown once set, and no longer after', () async {
      expect(await get(), 'none');
      useTls(_rootCa(), _cert());
      expect(await get(), subject);
      useTls(_rootCa(), null);
      expect(await get(), 'none');
    });

    test('a stored certificate that no longer loads is skipped', () async {
      useTls(
        _rootCa(),
        const ClientCert(name: 'broken.p12', data: 'AAAA', password: ''),
      );
      expect(await get(), 'none');
    });

    test('a background isolate presents the stored certificate', () async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsRepository(prefs);
      await ClientCertStore().write(_cert());
      await settings.saveHasClientCert(true);
      await settings.saveCustomCa(
        CustomCa.parse('root.pem', _fixture('ca.pem')),
      );
      useTls(null, null);
      await buildBackgroundApiClient(prefs);
      expect(await get(), subject);
    });
  });

  test(
    'setting the certificate stores it and gives sign-in a fresh Dio',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      addTearDown(() => useTls(null, null));
      final notifier = container.read(tlsIdentityProvider.notifier);
      final before = container.read(bareDioProvider);

      await notifier.setCert(_cert());
      expect(container.read(clientCertProvider), _cert());
      expect(await loadClientCert(SettingsRepository(prefs)), _cert());
      expect(container.read(bareDioProvider), isNot(same(before)));

      await notifier.setCert(null);
      expect(container.read(clientCertProvider), isNull);
      expect(SettingsRepository(prefs).loadHasClientCert(), isFalse);
      expect(await ClientCertStore().read(), isNull);
    },
  );

  test('signing out clears the sign-in and keeps the certificate', () async {
    // The certificate belongs to the proxy, not the account, so "change
    // server" must not cost the user a re-import.
    final storage = NamespacedSecureStorage.install();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    addTearDown(() => useTls(null, null));
    await container.read(tlsIdentityProvider.notifier).setCert(_cert());
    await container.read(credentialsStoreProvider).writeApiKey('bb_secret');

    await container.read(serverProfileProvider.notifier).clear();

    expect(await container.read(credentialsStoreProvider).readApiKey(), isNull);
    expect(await loadClientCert(SettingsRepository(prefs)), _cert());
    expect(storage.namespaces.keys, containsAll(['', 'client_cert']));
  });

  group('a refusal', () {
    DioException failed(Object error) => DioException(
      requestOptions: RequestOptions(path: '/api/v1/auth/status'),
      error: error,
    );

    // As `dart:io` reported them against `openssl s_server -Verify 1
    // -verify_return_error`.
    test('says it is the certificate, for the alerts a proxy sends', () {
      for (final error in [
        const HttpException(
          '\n\tTLSV1_ALERT_CERTIFICATE_REQUIRED(tls_record.cc:489) error 268436572',
        ),
        const HandshakeException(
          'Handshake error in client',
          OSError('\n\tTLSV1_ALERT_UNKNOWN_CA(tls_record.cc:489)'),
        ),
      ]) {
        expect(
          mapDioException(failed(error)).code,
          AppErrorCode.clientCertRefused,
          reason: '$error',
        );
      }
    });

    test('leaves what is not about the certificate alone', () {
      // TLS 1.2 without a certificate: a cipher mismatch says the same.
      expect(
        mapDioException(
          failed(
            const HandshakeException(
              'Handshake error in client',
              OSError('\n\tSSLV3_ALERT_HANDSHAKE_FAILURE(tls_record.cc:489)'),
            ),
          ),
        ).code,
        AppErrorCode.connectionError,
      );
      expect(
        mapDioException(
          failed(
            const HandshakeException(
              'Handshake error in client',
              OSError('CERTIFICATE_VERIFY_FAILED: unable to get local issuer'),
            ),
          ),
        ).code,
        AppErrorCode.badCertificate,
      );
    });

    group('from nginx', () {
      late HttpServer server;
      late String page;

      setUp(() async {
        final mocked = HttpOverrides.current;
        HttpOverrides.global = null;
        addTearDown(() => HttpOverrides.global = mocked);
        server = await HttpServer.bind('127.0.0.1', 0);
        server.listen(
          (r) => r.response
            ..statusCode = 400
            ..headers.contentType = ContentType.html
            ..write(page)
            ..close(),
        );
        addTearDown(() => server.close(force: true));
      });

      // nginx's page for `ssl_verify_client on`, as it ships it.
      String nginx(String reason) =>
          '<html>\r\n<head><title>400 $reason</title></head>\r\n<body>\r\n'
          '<center><h1>400 Bad Request</h1></center>\r\n'
          '<center>$reason</center>\r\n<hr><center>nginx</center>\r\n'
          '</body>\r\n</html>\r\n';

      Future<AppErrorCode?> probe() async {
        try {
          await AuthService(
            bareDio: createBareDio(),
            credentials: InMemoryCredentialsStore(),
          ).probeAuthStatus('http://127.0.0.1:${server.port}');
          return null;
        } on AppApiException catch (e) {
          return e.code;
        }
      }

      test('reaches the setup screen as the certificate', () async {
        for (final reason in [
          'No required SSL certificate was sent',
          'The SSL certificate error',
        ]) {
          page = nginx(reason);
          expect(await probe(), AppErrorCode.clientCertRefused, reason: reason);
        }
      });

      test('another 400 stays a bad response', () async {
        page = nginx('Request Header Or Cookie Too Large');
        expect(await probe(), AppErrorCode.badResponse);
      });
    });
  });

  group('setting', () {
    late SharedPreferences prefs;
    late ProviderContainer container;

    Future<void> start(List<Override> overrides) async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...overrides,
        ],
      );
      addTearDown(container.dispose);
      addTearDown(() => useTls(null, null));
    }

    test('two calls started together end as the later one', () async {
      // Two watch pushes a few milliseconds apart, added then removed, with
      // the Keystore slower to write the first than to delete.
      final store = _GatedStore();
      addTearDown(store.open);
      await start([clientCertStoreProvider.overrideWithValue(store)]);
      final notifier = container.read(tlsIdentityProvider.notifier);
      final added = notifier.setCert(_cert());
      final removed = notifier.setCert(null);
      await Future<void>.delayed(Duration.zero);
      store.open();
      await Future.wait([added, removed]);

      expect(container.read(clientCertProvider), isNull);
      expect(SettingsRepository(prefs).loadHasClientCert(), isFalse);
      expect(await store.read(), isNull);
    });

    test('a removal that fails leaves everything as it was', () async {
      final store = _FailingStore();
      await start([
        clientCertStoreProvider.overrideWithValue(store),
        initialClientCertProvider.overrideWithValue(_cert()),
      ]);
      await SettingsRepository(prefs).saveHasClientCert(true);

      await expectLater(
        container.read(tlsIdentityProvider.notifier).setCert(null),
        throwsA(isA<PlatformException>()),
      );

      expect(container.read(clientCertProvider), _cert());
      expect(SettingsRepository(prefs).loadHasClientCert(), isTrue);
    });

    test('both at once is one change, not two', () async {
      // "Remove all" on the phone, a watch adopting both: every listener —
      // the push to the watch, the clients — hears about it once.
      await start(const []);
      final heard = <TlsIdentity>[];
      container.listen(tlsIdentityProvider, (_, next) => heard.add(next));

      await container
          .read(tlsIdentityProvider.notifier)
          .setBoth(_rootCa(), _cert());

      expect(heard, [(ca: _rootCa(), cert: _cert())]);
      expect(SettingsRepository(prefs).loadCustomCa(), _rootCa());
      expect(await loadClientCert(SettingsRepository(prefs)), _cert());
    });

    test(
      'a certificate write that fails leaves the CA as it was too',
      () async {
        await start([
          clientCertStoreProvider.overrideWithValue(_FailingStore()),
        ]);

        await expectLater(
          container
              .read(tlsIdentityProvider.notifier)
              .setBoth(_rootCa(), _cert()),
          throwsA(isA<PlatformException>()),
        );

        expect(container.read(tlsIdentityProvider), (ca: null, cert: null));
        expect(SettingsRepository(prefs).loadCustomCa(), isNull);
      },
    );

    test('the same certificate again keeps the client', () async {
      await start([initialClientCertProvider.overrideWithValue(_cert())]);
      final before = container.read(bareDioProvider);
      await container.read(tlsIdentityProvider.notifier).setCert(_cert());
      expect(container.read(bareDioProvider), same(before));
    });
  });

  test('starts from what main read and the CA in preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await SettingsRepository(prefs).saveCustomCa(_rootCa());
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialClientCertProvider.overrideWithValue(_cert()),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(tlsIdentityProvider), (ca: _rootCa(), cert: _cert()));
  });
}

/// Secure storage refusing to delete, as a Keystore that is not ready does.
class _FailingStore extends ClientCertStore {
  @override
  Future<void> write(ClientCert? cert) async =>
      throw PlatformException(code: 'keystore');
}

/// Secure storage whose writes of a certificate wait for [open].
class _GatedStore extends ClientCertStore {
  final _gate = Completer<void>();

  void open() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<void> write(ClientCert? cert) async {
    if (cert != null) await _gate.future;
    await super.write(cert);
  }
}
