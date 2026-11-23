import 'dart:convert';
import 'dart:io';

import 'package:bambuddy_mobile/core/api/client_cert.dart';
import 'package:bambuddy_mobile/core/api/custom_ca.dart';
import 'package:bambuddy_mobile/core/api/edge_access.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/watch/watch_config_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';
import '../../helpers/fake_watch_connectivity.dart';

void main() {
  group('WatchConfigCodec.encode', () {
    test('api-key profile carries only the key, no login fields', () {
      final map = WatchConfigCodec.encode(
        profile: const ServerProfile(
          baseUrl: 'http://host:8000',
          authMode: AuthMode.apiKey,
          label: 'Home',
        ),
        apiKey: 'bb_secret',
      );
      expect(map['v'], WatchConfigCodec.version);
      expect(map['baseUrl'], 'http://host:8000');
      expect(map['authMode'], 'apiKey');
      expect(map['label'], 'Home');
      expect(map['apiKey'], 'bb_secret');
      expect(map.containsKey('jwt'), isFalse);
      expect(map.containsKey('username'), isFalse);
    });

    test('null/empty secrets are omitted (Data Layer rejects null values)', () {
      final map = WatchConfigCodec.encode(
        profile: const ServerProfile(
          baseUrl: 'http://host',
          authMode: AuthMode.none,
        ),
        apiKey: null,
        jwt: '',
      );
      expect(map.containsKey('apiKey'), isFalse);
      expect(map.containsKey('jwt'), isFalse);
      expect(map.containsKey('label'), isFalse);
    });

    test('jwt profile with remembered login carries both', () {
      final map = WatchConfigCodec.encode(
        profile: const ServerProfile(
          baseUrl: 'https://host',
          authMode: AuthMode.jwt,
        ),
        jwt: 'tok',
        login: (username: 'ada', password: 'pw'),
      );
      expect(map['jwt'], 'tok');
      expect(map['username'], 'ada');
      expect(map['password'], 'pw');
    });
  });

  group('WatchConfigCodec.decode', () {
    test('round-trips an encoded api-key config', () {
      final map = WatchConfigCodec.encode(
        profile: const ServerProfile(
          baseUrl: 'http://host:8000',
          authMode: AuthMode.apiKey,
          label: 'Home',
        ),
        apiKey: 'bb_secret',
      );
      final cfg = WatchConfigCodec.decode(map)!;
      expect(cfg.profile.baseUrl, 'http://host:8000');
      expect(cfg.profile.authMode, AuthMode.apiKey);
      expect(cfg.profile.label, 'Home');
      expect(cfg.apiKey, 'bb_secret');
      expect(cfg.jwt, isNull);
    });

    test('empty map (no push yet) decodes to null → watch keeps own setup', () {
      expect(WatchConfigCodec.decode(const {}), isNull);
    });

    test('missing baseUrl → null', () {
      expect(WatchConfigCodec.decode(const {'authMode': 'apiKey'}), isNull);
    });

    test('unknown authMode → null (never guess an auth mode)', () {
      expect(
        WatchConfigCodec.decode(const {'baseUrl': 'http://h', 'authMode': 'x'}),
        isNull,
      );
    });

    test('foreign context (other app keys) → null', () {
      expect(WatchConfigCodec.decode(const {'foo': 1, 'bar': 'baz'}), isNull);
    });
  });

  group('isSameServerAs', () {
    WatchConfig configFor(String url, AuthMode mode, {String? label}) =>
        WatchConfig(
          profile: ServerProfile(baseUrl: url, authMode: mode, label: label),
        );

    test('same url and mode → the same server, whatever the label says', () {
      final incoming = configFor(
        'http://h:8000',
        AuthMode.apiKey,
        label: 'new',
      );
      expect(
        incoming.isSameServerAs(
          const ServerProfile(
            baseUrl: 'http://h:8000',
            authMode: AuthMode.apiKey,
            label: 'old',
          ),
        ),
        isTrue,
      );
    });

    test('another host → a switch, and the user decides that', () {
      expect(
        configFor('http://other:8000', AuthMode.apiKey).isSameServerAs(
          const ServerProfile(
            baseUrl: 'http://h:8000',
            authMode: AuthMode.apiKey,
          ),
        ),
        isFalse,
      );
    });

    test('same host, other auth mode → a switch too', () {
      expect(
        configFor('http://h:8000', AuthMode.jwt).isSameServerAs(
          const ServerProfile(
            baseUrl: 'http://h:8000',
            authMode: AuthMode.apiKey,
          ),
        ),
        isFalse,
      );
    });

    test('nothing configured yet → never "the same"', () {
      expect(
        configFor('http://h', AuthMode.none).isSameServerAs(null),
        isFalse,
      );
    });
  });

  group('accent', () {
    const profile = ServerProfile(
      baseUrl: 'http://host',
      authMode: AuthMode.none,
    );

    test('travels with its variant', () {
      const accent = (
        seed: Color(0xFF607D8B),
        variant: DynamicSchemeVariant.monochrome,
      );
      final config = WatchConfigCodec.decode(
        WatchConfigCodec.encode(
          profile: profile,
          theme: (accent: accent, face: false),
        ),
      );
      expect(config?.accent, accent);
      expect(config?.watchFace, isFalse);
    });

    // The accent rides along for a watch whose face gives no colours.
    test('the face choice travels with the accent behind it', () {
      const accent = (
        seed: Color(0xFF2E7DD7),
        variant: DynamicSchemeVariant.tonalSpot,
      );
      final config = WatchConfigCodec.decode(
        WatchConfigCodec.encode(
          profile: profile,
          theme: (accent: accent, face: true),
        ),
      );
      expect(config?.watchFace, isTrue);
      expect(config?.accent, accent);
    });

    // An older phone, or the green brand, which the watch draws untold.
    test('absent is no accent', () {
      final map = WatchConfigCodec.encode(profile: profile);
      expect(map.containsKey('accentSeed'), isFalse);
      expect(map.containsKey('watchFace'), isFalse);
      expect(WatchConfigCodec.decode(map)?.accent, isNull);
      expect(WatchConfigCodec.decode(map)?.watchFace, isFalse);
    });

    test('a variant this build does not know draws as tonalSpot', () {
      final config = WatchConfigCodec.decode({
        'baseUrl': 'http://host',
        'authMode': 'none',
        'accentSeed': 0xFF2E7DD7,
        'accentVariant': 'fromTheFuture',
      });
      expect(config?.accent?.variant, DynamicSchemeVariant.tonalSpot);
      expect(config?.accent?.seed, const Color(0xFF2E7DD7));
    });

    test('a seed that is not a number is no accent, not a broken config', () {
      final config = WatchConfigCodec.decode({
        'baseUrl': 'http://host',
        'authMode': 'none',
        'accentSeed': '#2E7DD7',
      });
      expect(config, isNotNull);
      expect(config!.accent, isNull);
    });
  });

  group('the CA', () {
    const profile = ServerProfile(
      baseUrl: 'https://host',
      authMode: AuthMode.none,
    );
    final ca = CustomCa.parse(
      'root.pem',
      File('test/fixtures/tls/ca.pem').readAsBytesSync(),
    )!;

    test('round-trips with its name', () {
      final config = WatchConfigCodec.decode(
        WatchConfigCodec.encode(profile: profile, ca: ca),
      );
      expect(config?.ca?.name, 'root.pem');
      expect(config?.ca?.pem, ca.pem);
    });

    test('a phone without one sends no CA keys, and the watch reads none', () {
      final map = WatchConfigCodec.encode(profile: profile);
      expect(map.keys, isNot(contains('caPem')));
      expect(WatchConfigCodec.decode(map)?.ca, isNull);
    });

    test('a PEM that holds no certificate is no CA, not a broken config', () {
      final config = WatchConfigCodec.decode({
        'baseUrl': 'https://host',
        'authMode': 'none',
        'caName': 'root.pem',
        'caPem': 'not a certificate',
      });
      expect(config, isNotNull);
      expect(config!.ca, isNull);
    });

    test('the phone pushes the CA it trusts', () async {
      final watch = FakeWatchConnectivity();
      await WatchConfigSync(
        watch: watch,
        credentials: InMemoryCredentialsStore(),
      ).push(profile, ca: ca);
      expect(watch.contexts.single['caPem'], ca.pem);
    });

    test('a PEM without its name is dropped', () {
      final config = WatchConfigCodec.decode({
        'baseUrl': 'https://host',
        'authMode': 'none',
        'caPem': ca.pem,
      });
      expect(config!.ca, isNull);
    });
  });
  group('the client certificate', () {
    const profile = ServerProfile(
      baseUrl: 'https://host',
      authMode: AuthMode.none,
    );
    final cert = ClientCert.parse(
      'phone.p12',
      File('test/fixtures/tls/client.p12').readAsBytesSync(),
      'fixture',
    ).cert!;

    test('round-trips with its name and password', () {
      final config = WatchConfigCodec.decode(
        WatchConfigCodec.encode(profile: profile, clientCert: cert),
      );
      expect(config?.clientCert, cert);
    });

    test('a phone without one sends no keys, and the watch reads none', () {
      final map = WatchConfigCodec.encode(profile: profile);
      expect(map.keys, isNot(contains('certData')));
      expect(WatchConfigCodec.decode(map)?.clientCert, isNull);
    });

    test('bytes that are not one are no certificate, not a broken config', () {
      for (final data in ['%%% not base64', base64.encode(utf8.encode('x'))]) {
        final config = WatchConfigCodec.decode({
          'baseUrl': 'https://host',
          'authMode': 'none',
          'certName': 'phone.p12',
          'certData': data,
          'certPassword': 'fixture',
        });
        expect(config, isNotNull);
        expect(config!.clientCert, isNull);
      }
    });

    test('the phone pushes the certificate it presents', () async {
      final watch = FakeWatchConnectivity();
      await WatchConfigSync(
        watch: watch,
        credentials: InMemoryCredentialsStore(),
      ).push(profile, clientCert: cert);
      expect(watch.contexts.single['certData'], cert.data);
    });
  });

  group('the Cloudflare Access credential', () {
    const profile = ServerProfile(
      baseUrl: 'https://printers.example.com',
      authMode: AuthMode.none,
    );
    final token = ServiceToken(
      host: 'printers.example.com',
      clientId: 'abc.access',
      clientSecret: 's3cret',
    );
    // Expires in 2100; the payload is all that is read.
    final cookie = [
      base64Url.encode(utf8.encode('{"alg":"RS256"}')),
      base64Url.encode(utf8.encode('{"exp":4102444800}')),
      'sig',
    ].map((p) => p.replaceAll('=', '')).join('.');
    final session = BrowserSession.fromCookie(
      host: 'printers.example.com',
      cookie: cookie,
    )!;

    test('a service token round-trips', () {
      final config = WatchConfigCodec.decode(
        WatchConfigCodec.encode(profile: profile, edge: token),
      );
      expect(config!.edge, isA<ServiceToken>());
      final back = config.edge! as ServiceToken;
      expect(back.host, 'printers.example.com');
      expect(back.clientId, 'abc.access');
      expect(back.clientSecret, 's3cret');
    });

    test('a browser session round-trips with the expiry of its cookie', () {
      final config = WatchConfigCodec.decode(
        WatchConfigCodec.encode(profile: profile, edge: session),
      );
      final back = config!.edge! as BrowserSession;
      expect(back.cookie, cookie);
      expect(back.expiresAt, session.expiresAt);
    });

    test('the expiry is the cookie\'s, not what the wire says', () {
      final map = WatchConfigCodec.encode(profile: profile, edge: session);
      final json = jsonDecode(map['edge']! as String) as Map<String, dynamic>;
      json['expiresAt'] = 1; // a lie
      map['edge'] = jsonEncode(json);
      final back = WatchConfigCodec.decode(map)!.edge! as BrowserSession;
      expect(back.expiresAt, session.expiresAt);
    });

    test('a phone without one sends no key, and the watch reads none', () {
      final map = WatchConfigCodec.encode(profile: profile);
      expect(map.keys, isNot(contains('edge')));
      expect(WatchConfigCodec.decode(map)?.edge, isNull);
    });

    test('anything unreadable is no credential, not a broken config', () {
      for (final raw in <Object?>[
        'not json',
        '[]',
        '{"kind":"service_token","host":"h"}',
        '{"kind":"newer_kind","host":"h"}',
        '{"kind":"browser_session","host":"h","cookie":"opaque"}',
        42,
      ]) {
        final config = WatchConfigCodec.decode({
          'baseUrl': 'https://host',
          'authMode': 'none',
          'edge': raw,
        });
        expect(config, isNotNull, reason: '$raw');
        expect(config!.edge, isNull, reason: '$raw');
      }
    });

    test('one for another server is not sent, and not read', () {
      const other = ServerProfile(
        baseUrl: 'https://garage.example.com',
        authMode: AuthMode.none,
      );
      expect(
        WatchConfigCodec.encode(profile: other, edge: token).keys,
        isNot(contains('edge')),
        reason: 'a stale one from the server the phone has left',
      );
      // And what arrives naming a host the profile is not on is dropped.
      final map = WatchConfigCodec.encode(profile: profile, edge: token);
      map['baseUrl'] = 'https://garage.example.com';
      expect(WatchConfigCodec.decode(map)!.edge, isNull);
    });

    test('one is for https only, as it is on the phone', () {
      const lan = ServerProfile(
        baseUrl: 'http://printers.example.com',
        authMode: AuthMode.none,
      );
      expect(
        WatchConfigCodec.encode(profile: lan, edge: token).keys,
        isNot(contains('edge')),
      );
      final map = WatchConfigCodec.encode(profile: profile, edge: token);
      map['baseUrl'] = 'http://printers.example.com';
      expect(WatchConfigCodec.decode(map)!.edge, isNull);
    });

    test('a host with a port or odd case is not the same host', () {
      final map = WatchConfigCodec.encode(profile: profile, edge: token);
      final json = jsonDecode(map['edge']! as String) as Map<String, dynamic>;
      json['host'] = 'printers.example.com:8443';
      map['edge'] = jsonEncode(json);
      expect(WatchConfigCodec.decode(map)!.edge, isNull);
    });

    test('the phone pushes the credential it presents', () async {
      final watch = FakeWatchConnectivity();
      await WatchConfigSync(
        watch: watch,
        credentials: InMemoryCredentialsStore(),
      ).push(profile, edge: token);
      expect(watch.contexts.single['edge'], contains('abc.access'));
    });
  });
}
