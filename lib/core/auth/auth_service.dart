import 'package:dio/dio.dart';

import '../api/api_exceptions.dart';
import '../api/endpoints.dart';
import '../diagnostics/auth_probe.dart';
import '../models/current_user.dart';
import '../settings/server_profile.dart';
import '../settings/sign_in_reason.dart';
import 'credentials_store.dart';
import 'two_factor.dart';

/// Result of server auth mode probe. [baseUrl] is the URL actually reached —
/// it may differ from what the user typed when the server redirected the probe
/// (e.g. `http://host` → `https://host`), so the caller persists this one to
/// keep REST and WS (ws/wss) on the same scheme.
typedef AuthProbeResult = ({
  bool authEnabled,
  bool requiresSetup,
  String baseUrl,
});

/// Outcome of the password step. Sealed on purpose: a server with 2FA on
/// answers 200 without a token, and every caller that signs in has to say what
/// it does about that — the compiler asks rather than the user finding out.
sealed class LoginResult {
  const LoginResult();
}

/// Signed in: the JWT is already in the credentials store.
class LoginCompleted extends LoginResult {
  const LoginCompleted(this.token, {this.user});

  final String token;

  /// Who signed in, from the `user` object the login answer embeds
  /// (`LoginResponse.user`, `backend/app/schemas/auth.py:39`). Null when the
  /// server sent none — then the identity has to come from `GET /auth/me`.
  final CurrentUser? user;
}

/// Password accepted, second factor pending. Nothing was stored yet — see
/// [AuthService.verifyTwoFactor].
class LoginNeedsTwoFactor extends LoginResult {
  const LoginNeedsTwoFactor(this.challenge);

  final TwoFactorChallenge challenge;
}


/// JWT login and auth mode detection. Uses bare Dio (no auth interceptor) —
/// login by definition goes without headers, which breaks the AuthService ↔
/// ApiClient cycle.
class AuthService {
  AuthService({
    required Dio bareDio,
    required this._credentials,
    this.onSignInRequired,
  }) : _dio = bareDio;

  final Dio _dio;
  final CredentialsStore _credentials;

  /// Called once when the remembered login can no longer restore a session on
  /// its own, so the app can tell the user why. See [_doSilentReLogin].
  final Future<void> Function(SignInReason)? onSignInRequired;

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

  /// `POST /auth/login`. On success stores the JWT in secure storage; when
  /// [remember] is true also stores username+password (silent re-login after
  /// 401).
  ///
  /// A `requires_2fa` answer carries no token and stores nothing — the caller
  /// gets a [LoginNeedsTwoFactor] to finish through [verifyTwoFactor].
  Future<LoginResult> login({
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
      // Checked before `access_token`: a server that sent both has not
      // completed a login, whatever the token looks like.
      final challenge = TwoFactorChallenge.tryParse(
        body,
        setCookie: res.headers.map['set-cookie'] ?? const [],
      );
      if (challenge == null) {
        // 2FA demanded without anything to answer it with — nothing the user
        // can do from here, and storing a token we weren't given is not an
        // option either.
        throw const ApiException(AppErrorCode.malformedResponse);
      }
      AuthProbe.twoFactorRequired(challenge);
      return LoginNeedsTwoFactor(challenge);
    }
    final token = body['access_token'];
    if (token is! String || token.isEmpty) {
      throw const ApiException(AppErrorCode.malformedResponse);
    }

    await _credentials.writeJwt(token);
    if (remember) {
      await _credentials.writeRememberedLogin(username, password);
    }
    return LoginCompleted(token, user: _userOrNull(body['user']));
  }

  /// The embedded `UserResponse`, or null when the server sent none — an
  /// answer without it is still a completed login, so this never throws.
  static CurrentUser? _userOrNull(Object? value) =>
      value is Map<String, dynamic> ? CurrentUser.fromJson(value) : null;

  /// `POST /auth/2fa/email/send` — mails a 6-digit code.
  ///
  /// Returns the challenge to use from here on: the server consumes the token
  /// it was given and issues a fresh one, so keeping the old one guarantees a
  /// 401 at verification. A failed send leaves the passed-in challenge valid
  /// (the server rolls back), so the caller can retry with what it already has.
  Future<TwoFactorChallenge> sendEmailOtp({
    required String baseUrl,
    required TwoFactorChallenge challenge,
  }) async {
    final Response<Map<String, dynamic>> res;
    try {
      res = await _dio.post<Map<String, dynamic>>(
        '$baseUrl${Endpoints.authTwoFactorEmailSend}',
        data: {'pre_auth_token': challenge.preAuthToken},
        options: Options(headers: challenge.cookieHeader),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      AuthProbe.emailCodeSent(ok: false, status: status);
      throw _twoFactorError(e, method: null);
    }
    AuthProbe.emailCodeSent(ok: true, status: res.statusCode);
    final fresh = res.data?['pre_auth_token'];
    // A server that answered 200 without a fresh token has kept the old one
    // valid (it only re-issues after consuming), so carrying it forward is the
    // recovery, not a guess.
    return fresh is String && fresh.isNotEmpty
        ? challenge.withToken(fresh)
        : challenge;
  }

  /// `POST /auth/2fa/verify` — exchanges the challenge plus a code for the JWT,
  /// which is then stored exactly as [login] would.
  ///
  /// Deliberately has no "remember me": a saved password cannot renew a 2FA
  /// session on its own (the second factor is in the user's head or their
  /// authenticator), and a stored secret that buys nothing is pure liability.
  /// See `docs/plans/10-two-factor-login.md` §2.
  Future<LoginCompleted> verifyTwoFactor({
    required String baseUrl,
    required TwoFactorChallenge challenge,
    required TwoFactorMethod method,
    required String code,
  }) async {
    final Response<Map<String, dynamic>> res;
    try {
      res = await _dio.post<Map<String, dynamic>>(
        '$baseUrl${Endpoints.authTwoFactorVerify}',
        data: {
          'pre_auth_token': challenge.preAuthToken,
          // The server normalises to upper case and rejects surrounding space
          // with a 422; both are one keyboard slip away on a backup code.
          'code': code.trim().toUpperCase(),
          'method': method.name,
        },
        options: Options(headers: challenge.cookieHeader),
      );
    } on DioException catch (e) {
      throw _twoFactorError(e, method: method);
    }

    final token = res.data?['access_token'];
    if (token is! String || token.isEmpty) {
      AuthProbe.twoFactorVerified(method,
          failure: TwoFactorFailure.server, status: res.statusCode);
      throw const ApiException(AppErrorCode.malformedResponse);
    }
    AuthProbe.twoFactorVerified(method);
    await _credentials.writeJwt(token);
    // `TwoFAVerifyResponse` carries the same `user` object as the one-step
    // login (`backend/app/schemas/auth.py:271`), so finishing 2FA identifies
    // the session too and costs no extra `GET /auth/me`.
    return LoginCompleted(token, user: _userOrNull(res.data?['user']));
  }

  /// Maps a failed `/2fa/*` call and records it. [method] is null for the
  /// e-mail send, which verifies nothing and so writes no verify record.
  AppApiException _twoFactorError(
    DioException e, {
    required TwoFactorMethod? method,
  }) {
    final status = e.response?.statusCode;
    final failure = switch (status) {
      401 => _challengeGone(e.response?.data)
          ? TwoFactorFailure.challenge
          : TwoFactorFailure.code,
      429 => TwoFactorFailure.rateLimit,
      400 => TwoFactorFailure.method,
      _ => TwoFactorFailure.server,
    };
    if (method != null) {
      AuthProbe.twoFactorVerified(method, failure: failure, status: status);
    }
    return switch (failure) {
      TwoFactorFailure.code =>
        const AuthException(AppErrorCode.twoFactorCodeRejected),
      TwoFactorFailure.challenge =>
        const AuthException(AppErrorCode.twoFactorChallengeExpired),
      TwoFactorFailure.rateLimit =>
        const ApiException(AppErrorCode.tooManyAttempts, statusCode: 429),
      TwoFactorFailure.method => AuthException(
          // The e-mail path's own 400 is "no address on the account"; either
          // way this method cannot be used and another one has to be picked.
          method == null
              ? AppErrorCode.twoFactorEmailUnavailable
              : AppErrorCode.twoFactorMethodUnavailable,
        ),
      TwoFactorFailure.server => method == null && status != null && status >= 500
          // `email/send` answers 500 when the server has no SMTP configured —
          // a setup problem the user can only route around by using another
          // method, not a transient server fault.
          ? const ApiException(AppErrorCode.twoFactorEmailUnavailable)
          : mapDioException(e),
    };
  }

  /// Whether a 401 body blames the pre-auth token rather than the code. The
  /// server says "Invalid or expired pre-auth token" for the first and names
  /// the factor ("Invalid TOTP code", "Invalid OTP code", "Invalid backup
  /// code") for the second — and they lead to opposite next steps: start over
  /// from the password, or just type the code again.
  static bool _challengeGone(Object? body) {
    final detail = body is Map ? body['detail'] : null;
    return detail is String && detail.toLowerCase().contains('pre-auth');
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

  Future<String?>? _pendingSilentReLogin;

  /// Silent re-login with saved credentials. `null` if nothing was saved or
  /// login failed — then UI should gently redirect user to settings screen,
  /// never crash.
  ///
  /// Memoized: `AuthInterceptor`, `WsClient` and `ProactiveTokenRefresher` can
  /// all call this within the same window when a JWT expires. Without
  /// coordination that's N parallel `POST /auth/login`, and a server that
  /// invalidates the previous JWT on new login turns the retried request's
  /// second 401 into a spurious logout. Concurrent callers share the same
  /// in-flight future; it's cleared once that attempt settles so the next
  /// expiry still triggers a fresh login.
  Future<String?> silentReLogin(String baseUrl) {
    final pending = _pendingSilentReLogin;
    if (pending != null) return pending;
    final future = _doSilentReLogin(baseUrl);
    _pendingSilentReLogin = future;
    future.whenComplete(() {
      if (identical(_pendingSilentReLogin, future)) {
        _pendingSilentReLogin = null;
      }
    });
    return future;
  }

  Future<String?> _doSilentReLogin(String baseUrl) async {
    final saved = await _credentials.readRememberedLogin();
    if (saved == null) return null;
    try {
      final result = await login(
        baseUrl: baseUrl,
        username: saved.username,
        password: saved.password,
      );
      switch (result) {
        case LoginCompleted(:final token):
          return token;
        case LoginNeedsTwoFactor():
          // The password is still right, but from here a code is needed and
          // there is nobody to type it — this runs in an interceptor or a
          // background timer. Same handling as a rejected password, and for the
          // same reason: every later 401 would otherwise repeat this login and
          // spend the server's failed-attempt budget (10 per username, 20 per
          // IP in 15 minutes) on an attempt that cannot finish. The warning
          // says 2FA rather than blaming the password.
          AuthProbe.twoFactorBlockedSilentLogin();
          await _credentials.clearRememberedLogin();
          await onSignInRequired?.call(SignInReason.twoFactorRequired);
          return null;
      }
    } on AppApiException catch (e) {
      // A 401 is the server's final word on these credentials: it checked them
      // and said no. Keeping them means replaying the same rejected password on
      // every 401 the app runs into, and the server counts those — 10 per
      // username and 20 per IP in a 15-minute window. Behind a reverse proxy
      // that IP bucket is the proxy's, shared with the web UI, so a phone whose
      // saved password went stale can lock the whole install out of signing in.
      // Forget them instead: the next call finds nothing saved and stops there.
      // Anything else (429, 5xx, no network) says nothing about the password, so
      // those keep it and retry later.
      if (e.code == AppErrorCode.invalidCredentials) {
        await _credentials.clearRememberedLogin();
        await onSignInRequired?.call(SignInReason.credentialsRejected);
      }
      return null;
    }
  }
}
