import '../settings/server_profile.dart';
import 'credentials_store.dart';

/// One reader, because this switch was written three times — the REST
/// interceptor, the WebSocket handshake, the media credential — and a drift
/// between them shows only as one lane quietly authenticating differently.
Future<Map<String, String>> authHeaders(
  AuthMode mode,
  CredentialsStore credentials,
) async {
  switch (mode) {
    case AuthMode.none:
      return const {};
    case AuthMode.jwt:
      final jwt = await credentials.readJwt();
      return jwt == null ? const {} : {'Authorization': 'Bearer $jwt'};
    case AuthMode.apiKey:
      final key = await credentials.readApiKey();
      return key == null ? const {} : {'X-API-Key': key};
  }
}

/// Whether the profile promises a credential the store cannot produce.
///
/// The mirror image of [authHeaders]: every mode that would add a header here
/// has something to lose, and losing it is invisible — the request goes out
/// bare and comes back 401, which reads as a broken server rather than as a
/// session that ended.
///
/// A remembered login counts. Without a token but with a password the app signs
/// itself back in on the first 401, which is the whole point of "remember me" —
/// asking the user to do it by hand would break a feature that was working.
Future<bool> credentialMissing(
  AuthMode mode,
  CredentialsStore credentials,
) async => switch (mode) {
  AuthMode.none => false,
  AuthMode.jwt =>
    await credentials.readJwt() == null &&
        await credentials.readRememberedLogin() == null,
  AuthMode.apiKey => await credentials.readApiKey() == null,
};
