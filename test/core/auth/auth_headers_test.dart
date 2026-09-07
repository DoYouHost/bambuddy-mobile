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
}
