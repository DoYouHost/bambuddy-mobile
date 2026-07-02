import 'package:dio/dio.dart';

import '../api/api_exceptions.dart';
import '../api/endpoints.dart';
import '../settings/server_profile.dart';
import 'credentials_store.dart';

/// Result of server auth mode probe. [baseUrl] is the URL actually reached —
/// it may differ from what the user typed when the server redirected the probe
/// (e.g. `http://host` → `https://host`), so the caller persists this one to
/// keep REST and WS (ws/wss) on the same scheme.
typedef AuthProbeResult = ({
  bool authEnabled,
  bool requiresSetup,
  String baseUrl,
});


/// JWT login and auth mode detection. Uses bare Dio (no auth interceptor) —
/// login by definition goes without headers, which breaks the AuthService ↔
/// ApiClient cycle.
class AuthService {
  AuthService({required Dio bareDio, required this._credentials})
      : _dio = bareDio;

  final Dio _dio;
  final CredentialsStore _credentials;

  /// `GET /auth/status` → `{auth_enabled, requires_setup}`.
  /// Fallback for older servers without this endpoint (404):
  /// unauthenticated `GET /printers` — 200 means auth disabled.
  Future<AuthProbeResult> probeAuthStatus(String baseUrl) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$baseUrl${Endpoints.authStatus}',
      );
      final body = res.data ?? const {};
      return (
        authEnabled: body['auth_enabled'] == true,
        requiresSetup: body['requires_setup'] == true,
        baseUrl: ServerProfile.baseUrlFromReached(
          res.realUri,
          requested: baseUrl,
          endpointSuffix: Endpoints.authStatus,
        ),
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
      final res = await _dio.get<dynamic>('$baseUrl${Endpoints.printers}');
      return (
        authEnabled: false,
        requiresSetup: false,
        baseUrl: ServerProfile.baseUrlFromReached(
          res.realUri,
          requested: baseUrl,
          endpointSuffix: Endpoints.printers,
        ),
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        return (
          authEnabled: true,
          requiresSetup: false,
          baseUrl: ServerProfile.baseUrlFromReached(
            e.response?.realUri,
            requested: baseUrl,
            endpointSuffix: Endpoints.printers,
          ),
        );
      }
      throw mapDioException(e);
    }
  }

  /// `POST /auth/login`. Returns JWT and stores in secure storage.
  /// When [remember] is true, also stores username+password (silent re-login after 401).
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
        throw const AuthException(AppErrorCode.invalidCredentials);
      }
      throw mapDioException(e);
    }

    final body = res.data ?? const {};
    if (body['requires_2fa'] == true) {
      throw const AuthException(AppErrorCode.twoFactorUnsupported);
    }
    final token = body['access_token'];
    if (token is! String || token.isEmpty) {
      throw const ApiException(AppErrorCode.malformedResponse);
    }

    await _credentials.writeJwt(token);
    if (remember) {
      await _credentials.writeRememberedLogin(username, password);
    }
    return token;
  }

  /// Verifies API key with a test `GET /printers` and stores it.
  /// Throws [AuthException] if key is rejected.
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
        throw const AuthException(AppErrorCode.apiKeyRejected);
      }
      throw mapDioException(e);
    }
    await _credentials.writeApiKey(apiKey);
  }

  /// Silent re-login with saved credentials. `null` if nothing was saved or
  /// login failed — then UI should gently redirect user to settings screen,
  /// never crash.
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
