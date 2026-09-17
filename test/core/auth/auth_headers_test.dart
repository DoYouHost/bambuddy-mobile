import 'package:bambuddy_mobile/core/auth/auth_headers.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The one switch over [AuthMode] the app has left. It feeds the REST
/// interceptor, the WebSocket handshake and the media credential, so a
/// regression here is a regression in all three at once — which is exactly why
/// the three copies were folded into it.
void main() {
  late InMemoryCredentialsStore store;

  setUp(() {
    store = InMemoryCredentialsStore()
      ..jwt = 'jwt-value'
      ..apiKey = 'bb_key';
  });

  test(
    'none sends nothing, even with credentials sitting in the store',
    () async {
      // A server with auth off refuses nothing, so a stale token would go
      // unnoticed — and it is still the user's credential on the wire.
      expect(await authHeaders(AuthMode.none, store), isEmpty);
    },
  );

  test('jwt sends the bearer token', () async {
    expect(await authHeaders(AuthMode.jwt, store), {
      'Authorization': 'Bearer jwt-value',
    });
  });

  test('apiKey sends the key header', () async {
    expect(await authHeaders(AuthMode.apiKey, store), {'X-API-Key': 'bb_key'});
  });

  test(
    'an empty store sends nothing rather than a header with no value',
    () async {
      final empty = InMemoryCredentialsStore();

      expect(await authHeaders(AuthMode.jwt, empty), isEmpty);
      expect(await authHeaders(AuthMode.apiKey, empty), isEmpty);
    },
  );

  test('one mode never leaks the other mode credential', () async {
    expect(
      await authHeaders(AuthMode.jwt, store),
      isNot(contains('X-API-Key')),
    );
    expect(
      await authHeaders(AuthMode.apiKey, store),
      isNot(contains('Authorization')),
    );
  });

  group('credentialMissing', () {
    test('a server with auth off is never missing anything', () async {
      expect(
        await credentialMissing(AuthMode.none, InMemoryCredentialsStore()),
        isFalse,
      );
    });

    test('sees the credential each mode actually uses', () async {
      final onlyJwt = InMemoryCredentialsStore()..jwt = 'jwt-value';
      final onlyKey = InMemoryCredentialsStore()..apiKey = 'bb_key';

      expect(await credentialMissing(AuthMode.jwt, onlyJwt), isFalse);
      expect(await credentialMissing(AuthMode.apiKey, onlyJwt), isTrue);
      expect(await credentialMissing(AuthMode.apiKey, onlyKey), isFalse);
      expect(await credentialMissing(AuthMode.jwt, onlyKey), isTrue);
    });

    test('a remembered login is enough on its own', () async {
      // No token, but a password the app can sign itself back in with on the
      // first 401 — which is what "remember me" is for. Asking the user to do
      // it by hand would break a feature that still works.
      final remembered = InMemoryCredentialsStore()
        ..username = 'morgan'
        ..password = 'hunter2';

      expect(await credentialMissing(AuthMode.jwt, remembered), isFalse);
      expect(await credentialMissing(AuthMode.apiKey, remembered), isTrue);
    });

    test('an emptied store is missing what the profile promised', () async {
      // What a secure store that could not read its own format leaves behind:
      // no error, no value.
      final emptied = InMemoryCredentialsStore();

      expect(await credentialMissing(AuthMode.jwt, emptied), isTrue);
      expect(await credentialMissing(AuthMode.apiKey, emptied), isTrue);
    });
  });
}
