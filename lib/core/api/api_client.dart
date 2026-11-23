import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:app_util/app_util.dart';
import 'package:dio/dio.dart';

import '../auth/auth_headers.dart';
import '../auth/credentials_store.dart';
import '../demo/demo_backend.dart';
import '../diagnostics/report_config.dart';
import '../settings/server_profile.dart';
import 'api_exceptions.dart';
import 'edge_access_probe.dart';

/// Bare Dio for calls without auth (login, auth/status probe) and as the base
/// for [ApiClient]. Single place for timeouts.
///
/// [HttpProbe] goes on here rather than in [ApiClient] so the calls made before
/// there is a client — login, the auth/status probe — are logged too. First in
/// the chain, so its duration covers reading the credentials in
/// [AuthInterceptor] and it sees a 401 before the retry hides it.
Dio createBareDio() {
  // Does not touch [ServerReachability]: a notification button tapped with the
  // app open builds clients here too, and that is no new server. The profile
  // notifier forgets it when the server changes.
  return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
      ),
    )
    ..interceptors.add(HttpProbe(config: bambuddyHttpProbe))
    // After the probe, so the log keeps the whole exchange, and on the bare Dio
    // so the login and the auth probe answer for reachability too.
    ..interceptors.add(ReachabilityProbe(ServerReachability.instance))
    // After the probes, so an answer that is a Cloudflare sign-in page is still
    // logged and still counts as the server being reachable.
    ..interceptors.add(EdgeAccessProbe());
}

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
      this.dio.httpClientAdapter = DemoHttpClientAdapter(
        DemoBackend.instance.handle,
      );
    }
    this.dio.interceptors.add(
      AuthInterceptor(
        authMode: profile.authMode,
        credentials: credentials,
        refreshAuth: refreshAuth,
        retryDio: this.dio,
      ),
    );
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
    // A retry already carries the token [refreshAuth] returned; reading the
    // store again would put back whatever it holds, which is the same token
    // only when the refresh stored it before answering.
    if (options.extra[_retriedFlag] != true) {
      options.headers.addAll(await authHeaders(authMode, credentials));
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
      // A throw here is the re-login meeting Cloudflare, not a wrong password
      // (`AuthService.silentReLogin` lets that one out); Dio passes it on as the
      // request's error, which is what the saved login below must not hide.
      final newToken = await refreshAuth!();
      if (newToken != null) {
        final opts = err.requestOptions
          ..headers['Authorization'] = 'Bearer $newToken'
          ..extra[_retriedFlag] = true;
        // Dio sends a FormData once and the first attempt already did; without
        // a copy the retry of an upload dies on "already been finalized" after
        // the re-login has succeeded.
        final body = opts.data;
        if (body is FormData) opts.data = body.clone();
        try {
          handler.resolve(await retryDio.fetch<dynamic>(opts));
        } on DioException catch (retryErr) {
          handler.next(retryErr);
        }
        return;
      }
      // `silentReLogin` forgets the saved login only on a refused password or
      // a 2FA demand, so a login still saved means the attempt failed for
      // another reason (429, 5xx, no network). Passing the 401 on would end a
      // session that has not ended: the dashboard sends a 401 to /setup.
      if (await credentials.readRememberedLogin() != null) {
        final refused = mapDioException(err);
        handler.next(
          err.copyWith(
            error: NetworkException(
              AppErrorCode.serverUnreachable,
              method: refused.method,
              path: refused.path,
            ),
          ),
        );
        return;
      }
    }
    handler.next(err);
  }
}
