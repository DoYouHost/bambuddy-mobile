import 'package:dio/dio.dart';

import '../api/api_exceptions.dart';
import '../api/endpoints.dart';
import '../diagnostics/auth_probe.dart';
import '../models/current_user.dart';
import '../settings/server_profile.dart';
import '../settings/sign_in_reason.dart';
import 'credentials_store.dart';
import 'two_factor.dart';

/// [baseUrl] is the URL actually *reached*, which differs from what the user
/// typed when the probe was redirected (`http://host` → `https://host`). The
/// caller persists this one, keeping REST and WS on the same scheme.
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

  /// From the `user` object the login answer embeds (`LoginResponse.user`,
  /// `backend/app/schemas/auth.py::LoginResponse`). Null when the server sent
  /// none — the identity then has to come from `GET /auth/me`.
  final CurrentUser? user;
}

/// Password accepted, second factor pending. Nothing stored yet — see
/// [AuthService.verifyTwoFactor].
class LoginNeedsTwoFactor extends LoginResult {
  const LoginNeedsTwoFactor(this.challenge);

  final TwoFactorChallenge challenge;
}

/// JWT login and auth mode detection. Uses bare Dio: login by definition goes
/// without headers, which is also what breaks the AuthService ↔ ApiClient
/// cycle.
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

  /// `GET /auth/status`, falling back for servers old enough to 404 it: an
  /// unauthenticated `GET /printers` answering 200 means auth is disabled.
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

  /// Stores the JWT on success, plus username and password when [remember] is
  /// set — that pair is what [silentReLogin] runs on. A `requires_2fa` answer
  /// stores nothing and comes back as [LoginNeedsTwoFactor].
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
        // 2FA demanded with nothing to answer it with.
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

  /// An answer without a user is still a completed login, so this never throws.
  static CurrentUser? _userOrNull(Object? value) =>
      value is Map<String, dynamic> ? CurrentUser.fromJson(value) : null;

  /// Answers with the challenge to use from here on: the server consumes the
  /// token it was given and issues a fresh one, so keeping the old one
  /// guarantees a 401 at verification. A failed send rolls back, leaving the
  /// passed-in challenge good for a retry.
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
    // A 200 without a fresh token means the old one was never consumed — the
    // server only re-issues after consuming — so carrying it forward is the
    // recovery, not a guess.
    return fresh is String && fresh.isNotEmpty
        ? challenge.withToken(fresh)
        : challenge;
  }

  /// Exchanges the challenge plus a code for the JWT, stored as [login] would.
  ///
  /// Deliberately has no "remember me": a saved password cannot renew a 2FA
  /// session on its own, and a stored secret that buys nothing is pure
  /// liability. `docs/plans/10-two-factor-login.md` §2.
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
    // `TwoFAVerifyResponse` carries the same `user` as the one-step login
    // (`backend/app/schemas/auth.py::TwoFAVerifyRequest`), so this costs no
    // `GET /auth/me`.
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

  /// Whether a 401 blames the pre-auth token rather than the code — opposite
  /// next steps, start over from the password or just retype. The server says
  /// "Invalid or expired pre-auth token" for the first and names the factor
  /// ("Invalid TOTP code", "Invalid backup code") for the second.
  static bool _challengeGone(Object? body) {
    final detail = body is Map ? body['detail'] : null;
    return detail is String && detail.toLowerCase().contains('pre-auth');
  }

  /// Proves the key on a `GET /printers` before storing it, so a typo surfaces
  /// in the form rather than as a dead app.
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
      // Only a 401 means the key itself is not accepted. A 403 is a key the
      // server recognises and then refuses this route to — too few scopes,
      // an owner without `printers:read` (1.2.6+), an owner whose account is
      // gone — and "API key rejected" would send the user hunting for a typo
      // that isn't there. The mapped error carries the server's reason.
      if (e.response?.statusCode == 401) {
        throw const AuthException(AppErrorCode.apiKeyRejected);
      }
      throw mapDioException(e);
    }
    await _credentials.writeApiKey(apiKey);
  }

  Future<String?>? _pendingSilentReLogin;

  /// `null` when nothing was saved or the login failed; the UI then routes to
  /// settings rather than crashing.
  ///
  /// Memoized because `AuthInterceptor`, `WsClient` and
  /// `ProactiveTokenRefresher` all reach for this in the same window when a JWT
  /// expires. Uncoordinated that is N parallel logins, and a server which
  /// invalidates the previous JWT on each one turns the retried request's
  /// second 401 into a spurious logout. Cleared once the attempt settles, so
  /// the next expiry still gets a fresh login.
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
          // The password is still right, but this runs in an interceptor or a
          // background timer and there is nobody to type a code. Handled like a
          // rejected password for the same reason: every later 401 would repeat
          // a login that cannot finish, against the budget quoted below.
          AuthProbe.twoFactorBlockedSilentLogin();
          await _credentials.clearRememberedLogin();
          await onSignInRequired?.call(SignInReason.twoFactorRequired);
          return null;
      }
    } on AppApiException catch (e) {
      // A 401 is the server's final word, and keeping the credentials would
      // replay the rejected password on every 401 the app meets. The server
      // counts those: 10 per username, 20 per IP in 15 minutes — and behind a
      // reverse proxy that IP bucket is the proxy's, shared with the web UI, so
      // one phone with a stale password can lock the whole install out.
      // Anything else (429, 5xx, no network) says nothing about the password.
      if (e.code == AppErrorCode.invalidCredentials) {
        await _credentials.clearRememberedLogin();
        await onSignInRequired?.call(SignInReason.credentialsRejected);
      }
      return null;
    }
  }
}
