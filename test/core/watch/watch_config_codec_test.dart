import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/watch/watch_config_sync.dart';
import 'package:flutter_test/flutter_test.dart';

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
      expect(
        WatchConfigCodec.decode(const {'foo': 1, 'bar': 'baz'}),
        isNull,
      );
    });
  });

  group('isSameServerAs', () {
    WatchConfig configFor(String url, AuthMode mode, {String? label}) =>
        WatchConfig(
          profile: ServerProfile(baseUrl: url, authMode: mode, label: label),
        );

    test('same url and mode → the same server, whatever the label says', () {
      final incoming = configFor('http://h:8000', AuthMode.apiKey, label: 'new');
      expect(
        incoming.isSameServerAs(const ServerProfile(
            baseUrl: 'http://h:8000', authMode: AuthMode.apiKey, label: 'old')),
        isTrue,
      );
    });

    test('another host → a switch, and the user decides that', () {
      expect(
        configFor('http://other:8000', AuthMode.apiKey).isSameServerAs(
            const ServerProfile(
                baseUrl: 'http://h:8000', authMode: AuthMode.apiKey)),
        isFalse,
      );
    });

    test('same host, other auth mode → a switch too', () {
      expect(
        configFor('http://h:8000', AuthMode.jwt).isSameServerAs(
            const ServerProfile(
                baseUrl: 'http://h:8000', authMode: AuthMode.apiKey)),
        isFalse,
      );
    });

    test('nothing configured yet → never "the same"', () {
      expect(configFor('http://h', AuthMode.none).isSameServerAs(null), isFalse);
    });
  });
}
