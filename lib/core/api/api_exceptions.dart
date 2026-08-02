import 'package:dio/dio.dart';

/// Error codes for the API/auth layer. The core layer is UI-independent:
/// translation to text happens at display time (see `lib/l10n/error_messages.dart`).
enum AppErrorCode {
  serverUnreachable,
  unauthorized,

  /// 403 — authentication OK, but no permission for this action (e.g., API key
  /// without `can_control_printer`). Unlike [unauthorized], does NOT indicate
  /// session expiry — we don't log out, just block the action.
  forbidden,
  badResponse,
  badCertificate,
  connectionError,
  malformedResponse,
  invalidCredentials,

  /// The account needs a second factor and the caller has no way to ask for it
  /// — silent re-login from an interceptor or the background isolate. The
  /// interactive path never sees this: it gets a [TwoFactorChallenge] instead.
  twoFactorUnsupported,

  /// The server checked the code and said no. The login challenge survives a
  /// wrong code, so the user just types the next one.
  twoFactorCodeRejected,

  /// The pre-auth token is gone: 5 minutes elapsed, it was already spent, or
  /// the `2fa_challenge` cookie binding failed (a proxy that drops `Set-Cookie`
  /// looks exactly like this). Only the password step can produce a new one.
  twoFactorChallengeExpired,

  /// The chosen second factor is not usable on this account — TOTP turned off
  /// between the two steps, or a backup code on an account without TOTP.
  twoFactorMethodUnavailable,

  /// The server cannot mail the code: no SMTP configured, or the send failed.
  /// Another method (if the account has one) still works.
  twoFactorEmailUnavailable,

  apiKeyRejected,

  /// 429 — the server is refusing for now, not forever. bambuddy rate-limits
  /// failed logins in two buckets (10 per username, 20 per IP, 15-minute
  /// window) and answers 429 *before* checking the password, so a locked-out
  /// user gets it even when they finally type the right one. Reported as its
  /// own code because "wait 15 minutes" and "your password is wrong" send the
  /// user in opposite directions.
  tooManyAttempts,
}

/// Base exception for the API layer. Carries error code (for localization) and
/// optional technical details for logs.
sealed class AppApiException implements Exception {
  const AppApiException(this.code, {this.statusCode, this.detail});

  final AppErrorCode code;

  /// HTTP status code for [AppErrorCode.badResponse] (null for others).
  final int? statusCode;

  /// Raw, user-invisible detail (e.g., `DioException.message`).
  final String? detail;

  @override
  String toString() =>
      '$runtimeType($code${statusCode == null ? '' : ', status=$statusCode'}'
      '${detail == null ? '' : ', detail=$detail'})';
}

/// Server responded with an error (4xx/5xx except 401/403) or
/// response had unexpected shape.
class ApiException extends AppApiException {
  const ApiException(super.code, {super.statusCode, super.detail});
}

/// Authentication problem: bad credentials, expired/invalidated token or key, or
/// insufficient permissions.
class AuthException extends AppApiException {
  const AuthException(super.code, {super.detail});
}

/// Server unreachable: timeout, connection refused, or no network.
class NetworkException extends AppApiException {
  const NetworkException(super.code, {super.detail});
}

/// Runs [body], mapping any [DioException] to [AppApiException] via
/// [mapDioException]. Centralizes the `try { ... } on DioException catch (e)
/// { throw mapDioException(e); }` boilerplate repeated across repositories.
Future<T> guard<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on DioException catch (e) {
    throw mapDioException(e);
  }
}

/// Like [guard], but non-auth failures degrade to `null` instead of
/// rethrowing — for single-entity fetches (printer/plug status, etc.) where
/// one unreachable resource shouldn't break a composite view (dashboard,
/// maintenance overview). Auth errors still bubble up so the UI can redirect.
Future<T?> guardOrNull<T>(Future<T?> Function() body) async {
  try {
    return await body();
  } on DioException catch (e) {
    final mapped = mapDioException(e);
    if (mapped is AuthException) throw mapped;
    return null;
  } on Object {
    return null;
  }
}

/// Maps [DioException] to a typed application exception.
AppApiException mapDioException(DioException e) {
  if (e.error is AppApiException) {
    return e.error! as AppApiException;
  }
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      return NetworkException(AppErrorCode.serverUnreachable,
          detail: e.message);
    case DioExceptionType.badResponse:
      final code = e.response?.statusCode;
      if (code == 401) {
        return const AuthException(AppErrorCode.unauthorized);
      }
      if (code == 403) {
        return const AuthException(AppErrorCode.forbidden);
      }
      if (code == 429) {
        return const ApiException(AppErrorCode.tooManyAttempts,
            statusCode: 429);
      }
      return ApiException(AppErrorCode.badResponse, statusCode: code);
    case DioExceptionType.badCertificate:
      return const NetworkException(AppErrorCode.badCertificate);
    case DioExceptionType.cancel:
    case DioExceptionType.unknown:
      return NetworkException(AppErrorCode.connectionError, detail: e.message);
  }
}
