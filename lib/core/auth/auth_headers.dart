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
