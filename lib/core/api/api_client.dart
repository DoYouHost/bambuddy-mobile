import 'package:dio/dio.dart';

import '../auth/credentials_store.dart';
import '../demo/demo_http_adapter.dart';
import '../diagnostics/http_probe.dart';
import '../settings/server_profile.dart';

/// Bare Dio for calls without auth (login, auth/status probe) and as the base
/// for [ApiClient]. Single place for timeouts.
///
/// [HttpProbe] goes on here rather than in [ApiClient] so the calls made before
/// there is a client — login, the auth/status probe — are logged too. First in
/// the chain, so its duration covers reading the credentials in
/// [AuthInterceptor] and it sees a 401 before the retry hides it.
Dio createBareDio() => Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
      ),
    )..interceptors.add(HttpProbe());

/// Authenticated HTTP client for a single [ServerProfile].
class ApiClient {
  ApiClient({
    required ServerProfile profile,
    required CredentialsStore credentials,
    Future<String?> Function()? refreshAuth,
    Dio? dio,
  }) : dio = dio ?? createBareDio() {
    this.dio.options.baseUrl = profile.baseUrl;
    // Demo profile: serve everything from the in-process fake server. Doing it
    // here covers every ApiClient construction site (providers, background
    // isolate, wear transport) with a single branch.
    if (profile.isDemo) {
      this.dio.httpClientAdapter = DemoHttpClientAdapter();
    }
    this.dio.interceptors.add(AuthInterceptor(
          authMode: profile.authMode,
          credentials: credentials,
          refreshAuth: refreshAuth,
          retryDio: this.dio,
        ));
  }

  final Dio dio;
}

/// Adds auth headers per [AuthMode] and handles 401 for JWT
/// (silent re-login → single retry).
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.authMode,
    required this.credentials,
    required this.retryDio,
    this.refreshAuth,
  });

  static const _retriedFlag = 'authRetried';

  final AuthMode authMode;
  final CredentialsStore credentials;

  /// Attempt to recover a valid JWT (silent re-login). `null` = not possible.
  final Future<String?> Function()? refreshAuth;

  /// Dio used to retry request after token refresh.
  final Dio retryDio;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    switch (authMode) {
      case AuthMode.none:
        // Server requires no auth — never attach stale credentials.
        break;
      case AuthMode.jwt:
        final jwt = await credentials.readJwt();
        if (jwt != null) {
          options.headers['Authorization'] = 'Bearer $jwt';
        }
      case AuthMode.apiKey:
        final key = await credentials.readApiKey();
        if (key != null) {
          options.headers['X-API-Key'] = key;
        }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final is401 = err.response?.statusCode == 401;
    final alreadyRetried = err.requestOptions.extra[_retriedFlag] == true;

    if (is401 &&
        authMode == AuthMode.jwt &&
        refreshAuth != null &&
        !alreadyRetried) {
      final newToken = await refreshAuth!();
      if (newToken != null) {
        final opts = err.requestOptions
          ..headers['Authorization'] = 'Bearer $newToken'
          ..extra[_retriedFlag] = true;
        try {
          handler.resolve(await retryDio.fetch<dynamic>(opts));
        } on DioException catch (retryErr) {
          handler.next(retryErr);
        }
        return;
      }
    }
    handler.next(err);
  }
}
