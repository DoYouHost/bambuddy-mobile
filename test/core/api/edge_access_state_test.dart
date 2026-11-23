import 'dart:async';
import 'dart:io';

import 'package:bambuddy_mobile/core/api/custom_ca.dart';
import 'package:bambuddy_mobile/core/api/client_cert.dart';
import 'package:bambuddy_mobile/core/api/edge_access.dart';
import 'package:bambuddy_mobile/core/api/tls_overrides.dart';
import 'package:bambuddy_mobile/core/notifications/background_api.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/namespaced_secure_storage.dart';

// The state behind #72: Cloudflare Access credential in `TlsIdentity`, how it
// is stored, and that a client built from it presents it. What the headers do
// on the wire is `edge_access_test.dart`.

final _token = ServiceToken(
  host: '127.0.0.1',
  clientId: 'abc.access',
  clientSecret: 's3cret',
);

final _other = ServiceToken(
  host: '127.0.0.1',
  clientId: 'second.access',
  clientSecret: 'another',
);

ClientCert _cert() =>
    ClientCert(name: 'phone.p12', data: 'AAAA', password: 'pw');

List<int> _fixture(String name) =>
    File('test/fixtures/tls/$name').readAsBytesSync();

CustomCa _ca() => CustomCa.parse('ca.pem', _fixture('ca.pem'))!;

void main() {
  late SharedPreferences prefs;
  late ProviderContainer container;
  late HttpServer server;

  /// The Cloudflare headers each request carried, in order.
  final heard = <String?>[];

  setUp(() async {
    // The test binding answers every HttpClient with a canned 400.
    final mocked = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = mocked);
    addTearDown(() => useTls(null, null));
    heard.clear();
    final context = SecurityContext()
      ..useCertificateChainBytes(_fixture('server.pem'))
      ..usePrivateKeyBytes(_fixture('server.key'));
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      heard.add(request.headers.value('cf-access-client-id'));
      request.response.close();
    });
  });

  Future<void> start([List<Override> overrides = const []]) async {
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
  }

  TlsIdentityNotifier notifier() =>
      container.read(tlsIdentityProvider.notifier);

  /// A request through the app's own bare Dio, as sign-in makes it.
  Future<void> request() => container
      .read(bareDioProvider)
      .get<void>('https://127.0.0.1:${server.port}/');

  group('setting', () {
    test('stores it, flags it, and the app\'s Dio presents it', () async {
      await start();
      await notifier().setCa(_ca());
      await notifier().setEdge(_token);

      expect(container.read(edgeAccessProvider), _token);
      expect(SettingsRepository(prefs).loadHasEdgeAccess(), isTrue);
      expect(await EdgeAccessStore().read(), _token);
      await request();
      expect(heard, ['abc.access']);
    });

    test('removing it clears the store, the flag and the header', () async {
      await start();
      await notifier().setCa(_ca());
      await notifier().setEdge(_token);
      await notifier().setEdge(null);

      expect(container.read(edgeAccessProvider), isNull);
      expect(SettingsRepository(prefs).loadHasEdgeAccess(), isFalse);
      expect(await EdgeAccessStore().read(), isNull);
      await request();
      expect(heard, [null]);
    });

    test('a replacement is what the Dio read after it presents', () async {
      await start();
      await notifier().setCa(_ca());
      await notifier().setEdge(_token);
      // The first Dio makes its client now and keeps it, as Dio does.
      await request();
      await notifier().setEdge(_other);
      await request();
      expect(heard, ['abc.access', 'second.access']);
    });

    test('the same credential again keeps the client', () async {
      await start([initialEdgeAccessProvider.overrideWithValue(_token)]);
      final before = container.read(bareDioProvider);
      await notifier().setEdge(_token);
      expect(container.read(bareDioProvider), same(before));
    });

    test('a changed one gives sign-in a fresh Dio', () async {
      await start([initialEdgeAccessProvider.overrideWithValue(_token)]);
      final before = container.read(bareDioProvider);
      await notifier().setEdge(_other);
      expect(container.read(bareDioProvider), isNot(same(before)));
    });

    test('two calls started together end as the later one', () async {
      final store = _GatedStore();
      addTearDown(store.open);
      await start([edgeAccessStoreProvider.overrideWithValue(store)]);
      final added = notifier().setEdge(_token);
      final removed = notifier().setEdge(null);
      await Future<void>.delayed(Duration.zero);
      store.open();
      await Future.wait([added, removed]);

      expect(container.read(edgeAccessProvider), isNull);
      expect(SettingsRepository(prefs).loadHasEdgeAccess(), isFalse);
      expect(await store.read(), isNull);
    });

    test('a write that fails leaves everything as it was', () async {
      await start([
        edgeAccessStoreProvider.overrideWithValue(_FailingStore()),
        initialEdgeAccessProvider.overrideWithValue(_token),
      ]);
      await SettingsRepository(prefs).saveHasEdgeAccess(true);

      await expectLater(
        notifier().setEdge(_other),
        throwsA(isA<PlatformException>()),
      );

      expect(container.read(edgeAccessProvider), _token);
      expect(SettingsRepository(prefs).loadHasEdgeAccess(), isTrue);
    });

    test(
      'a credential that fails takes back the certificate it wrote',
      () async {
        await start([
          edgeAccessStoreProvider.overrideWithValue(_FailingStore()),
        ]);

        await expectLater(
          notifier().setAll(null, _cert(), _token),
          throwsA(isA<PlatformException>()),
        );

        expect(container.read(tlsIdentityProvider), (
          ca: null,
          cert: null,
          edge: null,
        ));
        expect(SettingsRepository(prefs).loadHasClientCert(), isFalse);
        expect(await ClientCertStore().read(), isNull);
      },
    );

    test(
      'a secret being replaced is not deleted before the new one is stored',
      () async {
        // Certificate out, credential in, and the Keystore refuses every write:
        // a certificate deleted first could not be put back.
        await start([
          edgeAccessStoreProvider.overrideWithValue(_FailingStore()),
          clientCertStoreProvider.overrideWithValue(_NoWriteCertStore()),
          initialClientCertProvider.overrideWithValue(_cert()),
        ]);
        await ClientCertStore().write(_cert());
        await SettingsRepository(prefs).saveHasClientCert(true);

        await expectLater(
          notifier().setAll(null, null, _token),
          throwsA(isA<PlatformException>()),
        );

        expect(await ClientCertStore().read(), _cert());
        expect(SettingsRepository(prefs).loadHasClientCert(), isTrue);
        expect(container.read(clientCertProvider), _cert());
      },
    );

    test('a failed undo does not hide the error that caused it', () async {
      await start([
        clientCertStoreProvider.overrideWithValue(_UndoFailsCertStore()),
        edgeAccessStoreProvider.overrideWithValue(_FailingStore()),
      ]);

      await expectLater(
        notifier().setAll(null, _cert(), _token),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'keystore'),
        ),
      );

      // The certificate could not be taken back, so its flag must still say it
      // is there.
      expect(await ClientCertStore().read(), _cert());
      expect(SettingsRepository(prefs).loadHasClientCert(), isTrue);
    });

    test('a CA that cannot be saved takes both secrets back', () async {
      await start([
        settingsRepositoryProvider.overrideWith(
          (ref) => _NoCaSettings(ref.watch(sharedPreferencesProvider)),
        ),
      ]);

      await expectLater(
        notifier().setAll(_ca(), _cert(), _token),
        throwsA(isA<PlatformException>()),
      );

      expect(await ClientCertStore().read(), isNull);
      expect(await EdgeAccessStore().read(), isNull);
      expect(SettingsRepository(prefs).loadHasClientCert(), isFalse);
      expect(SettingsRepository(prefs).loadHasEdgeAccess(), isFalse);
      expect(container.read(tlsIdentityProvider), (
        ca: null,
        cert: null,
        edge: null,
      ));
    });

    test('a refused write leaves a secret that is still on disk', () async {
      // A Keystore that failed to read at start leaves the entry on disk and
      // this state empty; a change that is then refused must not "undo" by
      // deleting what it never replaced.
      await start([
        edgeAccessStoreProvider.overrideWithValue(_FailingStore()),
        clientCertStoreProvider.overrideWithValue(_NoWriteCertStore()),
      ]);
      final settings = SettingsRepository(prefs);
      await EdgeAccessStore().write(_other);
      await settings.saveHasEdgeAccess(true);
      await ClientCertStore().write(_cert());
      await settings.saveHasClientCert(true);

      await expectLater(
        notifier().setEdge(_token),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        notifier().setCert(_cert()),
        throwsA(isA<PlatformException>()),
      );

      expect(await EdgeAccessStore().read(), _other);
      expect(settings.loadHasEdgeAccess(), isTrue);
      expect(await ClientCertStore().read(), _cert());
      expect(settings.loadHasClientCert(), isTrue);
    });

    test('a flag that cannot be saved takes its secret back', () async {
      await start([
        settingsRepositoryProvider.overrideWith(
          (ref) => _NoFlagSettings(ref.watch(sharedPreferencesProvider)),
        ),
      ]);

      await expectLater(
        notifier().setEdge(_token),
        throwsA(isA<PlatformException>()),
      );

      expect(await EdgeAccessStore().read(), isNull);
      expect(SettingsRepository(prefs).loadHasEdgeAccess(), isFalse);
      expect(container.read(edgeAccessProvider), isNull);
    });

    test('a CA already saved is put back when a later step fails', () async {
      // The CA is written first, then the certificate is deleted; the delete
      // fails, so the old CA must come back.
      final old = CustomCa.parse('old.pem', _fixture('ca.pem'))!;
      await start([
        clientCertStoreProvider.overrideWithValue(_NoDeleteCertStore()),
        initialClientCertProvider.overrideWithValue(_cert()),
      ]);
      await SettingsRepository(prefs).saveCustomCa(old);
      container.invalidate(tlsIdentityProvider);

      await expectLater(
        notifier().setAll(_ca(), null, null),
        throwsA(isA<PlatformException>()),
      );

      expect(SettingsRepository(prefs).loadCustomCa(), old);
      expect(container.read(customCaProvider), old);
    });

    test('a listener asks for a client and gets the new one', () async {
      await start([initialEdgeAccessProvider.overrideWithValue(_token)]);
      final before = container.read(bareDioProvider);
      final seen = <Object>[];
      container.listen(
        tlsIdentityProvider,
        (_, _) => seen.add(container.read(bareDioProvider)),
      );

      await notifier().setEdge(_other);

      expect(seen, hasLength(1));
      expect(seen.single, isNot(same(before)));
    });

    test(
      'a call queued behind one that outlived the container is dropped',
      () async {
        final store = _GatedStore();
        addTearDown(store.open);
        await start([edgeAccessStoreProvider.overrideWithValue(store)]);
        final first = notifier().setEdge(_token);
        final second = notifier().setEdge(null);
        await Future<void>.delayed(Duration.zero);
        container.dispose();
        store.open();

        await first;
        await second;

        // What `first` stored stays: `second` was dropped, not run.
        expect(await store.read(), _token);
        expect(SettingsRepository(prefs).loadHasEdgeAccess(), isTrue);
      },
    );

    test('all three at once are one change, not three', () async {
      await start();
      final changes = <TlsIdentity>[];
      container.listen(tlsIdentityProvider, (_, next) => changes.add(next));

      await notifier().setAll(_ca(), _cert(), _token);

      expect(changes, [(ca: _ca(), cert: _cert(), edge: _token)]);
      expect(await EdgeAccessStore().read(), _token);
      expect(await ClientCertStore().read(), _cert());
    });

    test('removing the certificates leaves the credential alone', () async {
      await start([initialEdgeAccessProvider.overrideWithValue(_token)]);
      await notifier().setBoth(_ca(), _cert());
      await notifier().setBoth(null, null);
      expect(container.read(edgeAccessProvider), _token);
    });
  });

  test('starts from what main read', () async {
    await start([initialEdgeAccessProvider.overrideWithValue(_token)]);
    expect(container.read(tlsIdentityProvider), (
      ca: null,
      cert: null,
      edge: _token,
    ));
  });

  test('signing out keeps it, as it belongs to the proxy', () async {
    final storage = NamespacedSecureStorage.install();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    await notifier().setEdge(_token);
    await container.read(credentialsStoreProvider).writeApiKey('bb_secret');

    await container.read(serverProfileProvider.notifier).clear();

    expect(await container.read(credentialsStoreProvider).readApiKey(), isNull);
    expect(await loadEdgeAccess(SettingsRepository(prefs)), _token);
    expect(storage.namespaces.keys, containsAll(['', 'edge_access']));
  });

  test('a background isolate presents the stored credential', () async {
    // The foreground service, the notification buttons and the watch relay
    // have no providers: this is the call each of them makes.
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    final settings = SettingsRepository(prefs);
    await EdgeAccessStore().write(_token);
    await settings.saveHasEdgeAccess(true);
    await settings.saveCustomCa(_ca());
    await settings.saveProfile(
      ServerProfile(
        baseUrl: 'https://127.0.0.1:${server.port}',
        authMode: AuthMode.none,
      ),
    );
    useTls(null, null);

    final client = await buildBackgroundApiClient(prefs);
    await client!.dio.get<void>('/');

    expect(heard, ['abc.access']);
  });
}

/// Secure storage refusing to store a credential, as a Keystore that is not
/// ready does; a delete still goes through.
class _FailingStore extends EdgeAccessStore {
  @override
  Future<void> write(EdgeAccess? access) async {
    if (access != null) throw PlatformException(code: 'keystore');
    await super.write(access);
  }
}

/// A certificate store that takes a certificate and then fails to give it
/// back, as a Keystore that stopped answering would.
class _UndoFailsCertStore extends ClientCertStore {
  @override
  Future<void> write(ClientCert? cert) async {
    if (cert == null) throw PlatformException(code: 'undo');
    await super.write(cert);
  }
}

/// A certificate store that cannot store a certificate at all.
class _NoWriteCertStore extends ClientCertStore {
  @override
  Future<void> write(ClientCert? cert) async {
    if (cert != null) throw PlatformException(code: 'keystore');
    await super.write(cert);
  }
}

/// A certificate store that cannot delete.
class _NoDeleteCertStore extends ClientCertStore {
  @override
  Future<void> write(ClientCert? cert) async {
    if (cert == null) throw PlatformException(code: 'delete');
    await super.write(cert);
  }
}

/// Preferences that cannot set the credential's flag.
class _NoFlagSettings extends SettingsRepository {
  _NoFlagSettings(super.prefs);

  @override
  Future<void> saveHasEdgeAccess(bool has) async {
    if (has) throw PlatformException(code: 'prefs');
    await super.saveHasEdgeAccess(has);
  }
}

/// Preferences that cannot save a CA.
class _NoCaSettings extends SettingsRepository {
  _NoCaSettings(super.prefs);

  @override
  Future<void> saveCustomCa(CustomCa? ca) async {
    if (ca != null) throw PlatformException(code: 'prefs');
    await super.saveCustomCa(ca);
  }
}

/// Secure storage whose writes of a credential wait for [open].
class _GatedStore extends EdgeAccessStore {
  final _gate = Completer<void>();

  void open() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<void> write(EdgeAccess? access) async {
    if (access != null) await _gate.future;
    await super.write(access);
  }
}
