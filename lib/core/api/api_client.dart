import 'package:dio/dio.dart';

import '../auth/credentials_store.dart';
import '../settings/server_profile.dart';

/// Goły Dio do wywołań bez auth (login, sonda auth/status) i jako baza
/// dla [ApiClient]. Jedno miejsce na timeouty.
Dio createBareDio() => Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
      ),
    );

/// Uwierzytelniony klient HTTP dla jednego [ServerProfile].
class ApiClient {
  ApiClient({
    required ServerProfile profile,
    required CredentialsStore credentials,
    Future<String?> Function()? refreshAuth,
    Dio? dio,
  }) : dio = dio ?? createBareDio() {
    this.dio.options.baseUrl = profile.baseUrl;
    this.dio.interceptors.add(AuthInterceptor(
          authMode: profile.authMode,
          credentials: credentials,
          refreshAuth: refreshAuth,
          retryDio: this.dio,
        ));
  }

  final Dio dio;
}

/// Dodaje nagłówki auth wg [AuthMode] i obsługuje 401 dla JWT
/// (cichy re-login → jednorazowy retry).
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

  /// Próba odzyskania ważnego JWT (cichy re-login). `null` = nie da się.
  final Future<String?> Function()? refreshAuth;

  /// Dio użyte do ponowienia żądania po odświeżeniu tokenu.
  final Dio retryDio;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    switch (authMode) {
      case AuthMode.none:
        break; // Serwer bez auth — ŻADNYCH nagłówków.
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
