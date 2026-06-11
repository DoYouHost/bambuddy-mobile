import 'package:dio/dio.dart';

import '../api/api_exceptions.dart';
import '../api/endpoints.dart';
import 'credentials_store.dart';

/// Wynik sondy trybu auth serwera.
typedef AuthProbeResult = ({bool authEnabled, bool requiresSetup});

/// Logowanie JWT i detekcja trybu auth. Używa „gołego" Dio (bez
/// interceptora auth) — login z definicji idzie bez nagłówków,
/// a to przecina cykl AuthService ↔ ApiClient.
class AuthService {
  AuthService({required Dio bareDio, required this._credentials})
      : _dio = bareDio;

  final Dio _dio;
  final CredentialsStore _credentials;

  /// `GET /auth/status` → `{auth_enabled, requires_setup}`.
  /// Fallback dla starszych serwerów bez tego endpointu (404):
  /// nieuwierzytelniony `GET /printers` — 200 znaczy auth wyłączony.
  Future<AuthProbeResult> probeAuthStatus(String baseUrl) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$baseUrl${Endpoints.authStatus}',
      );
      final body = res.data ?? const {};
      return (
        authEnabled: body['auth_enabled'] == true,
        requiresSetup: body['requires_setup'] == true,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return _probeViaPrinters(baseUrl);
      }
      throw mapDioException(e);
    }
  }

  Future<AuthProbeResult> _probeViaPrinters(String baseUrl) async {
    try {
      await _dio.get<dynamic>('$baseUrl${Endpoints.printers}');
      return (authEnabled: false, requiresSetup: false);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        return (authEnabled: true, requiresSetup: false);
      }
      throw mapDioException(e);
    }
  }

  /// `POST /auth/login`. Zwraca JWT i zapisuje go w secure storage.
  /// Przy [remember] zapisuje też login+hasło (cichy re-login po 401).
  Future<String> login({
    required String baseUrl,
    required String username,
    required String password,
    bool remember = false,
  }) async {
    final Response<Map<String, dynamic>> res;
    try {
      res = await _dio.post<Map<String, dynamic>>(
        '$baseUrl${Endpoints.authLogin}',
        data: {'username': username, 'password': password},
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const AuthException('Nieprawidłowy login lub hasło');
      }
      throw mapDioException(e);
    }

    final body = res.data ?? const {};
    if (body['requires_2fa'] == true) {
      throw const AuthException(
          'Konto wymaga 2FA — nieobsługiwane w tej wersji. '
          'Użyj klucza API (Ustawienia → API Keys na serwerze).');
    }
    final token = body['access_token'];
    if (token is! String || token.isEmpty) {
      throw const ApiException('Odpowiedź logowania bez access_token');
    }

    await _credentials.writeJwt(token);
    if (remember) {
      await _credentials.writeRememberedLogin(username, password);
    }
    return token;
  }

  /// Weryfikuje klucz API próbnym `GET /printers` i zapisuje go.
  /// Rzuca [AuthException] przy odrzuconym kluczu.
  Future<void> verifyAndStoreApiKey({
    required String baseUrl,
    required String apiKey,
  }) async {
    try {
      await _dio.get<dynamic>(
        '$baseUrl${Endpoints.printers}',
        options: Options(headers: {'X-API-Key': apiKey}),
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        throw const AuthException(
            'Klucz API odrzucony — sprawdź klucz i jego scope '
            '(wymagany can_read_status)');
      }
      throw mapDioException(e);
    }
    await _credentials.writeApiKey(apiKey);
  }

  /// Cichy re-login zapamiętanymi poświadczeniami. `null` gdy nic nie
  /// zapamiętano albo logowanie się nie powiodło — wtedy UI ma łagodnie
  /// odesłać użytkownika do ekranu konfiguracji, nigdy crashować.
  Future<String?> silentReLogin(String baseUrl) async {
    final saved = await _credentials.readRememberedLogin();
    if (saved == null) return null;
    try {
      return await login(
        baseUrl: baseUrl,
        username: saved.username,
        password: saved.password,
      );
    } on AppApiException {
      return null;
    }
  }
}
