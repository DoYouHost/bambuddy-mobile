import 'package:dio/dio.dart';

import '../diagnostics/log_path.dart';

/// Error codes for the API/auth layer. The core layer is UI-independent:
/// translation to text happens at display time (see
/// `lib/l10n/error_messages.dart`).
enum AppErrorCode {
  serverUnreachable,
  unauthorized,

  /// 403 — authenticated but not permitted. Unlike [unauthorized] this is not
  /// session expiry, so it blocks the action rather than signing the user out.
  forbidden,
  badResponse,
  badCertificate,
  connectionError,
  malformedResponse,
  invalidCredentials,

  /// A second factor is needed and the caller cannot ask for one — silent
  /// re-login from an interceptor or the background isolate. The interactive
  /// path gets a `TwoFactorChallenge` instead and never sees this.
  twoFactorUnsupported,

  /// The challenge survives a wrong code, so the user just types the next one.
  twoFactorCodeRejected,

  /// The pre-auth token is gone: elapsed, spent, or the `2fa_challenge` binding
  /// failed — a proxy dropping `Set-Cookie` looks exactly like this. Only the
  /// password step can produce a new one.
  twoFactorChallengeExpired,

  /// TOTP turned off between the two steps, or a backup code on an account
  /// without TOTP.
  twoFactorMethodUnavailable,

  /// No SMTP configured, or the send failed. Another method still works.
  twoFactorEmailUnavailable,

  apiKeyRejected,

  /// 429 — refusing for now, not forever. bambuddy answers it *before* checking
  /// the password, so a rate-limited user gets it even when they finally type
  /// the right one; its own code because "wait 15 minutes" and "your password
  /// is wrong" send the user in opposite directions.
  tooManyAttempts,
}

/// Carries the code the UI localizes, plus detail for the log.
sealed class AppApiException implements Exception {
  const AppApiException(
    this.code, {
    this.statusCode,
    this.detail,
    this.method,
    this.path,
  });

  final AppErrorCode code;

  /// Set for [AppErrorCode.badResponse], null for the rest.
  final int? statusCode;

  /// The call that failed, for the `action_failed` record: without it a reader
  /// has to guess which of the requests in flight the failure belongs to.
  ///
  /// [path] has been through [loggablePath], the same reduction `HttpProbe`
  /// records with: no host, no query string, and no segment the user named.
  /// Null for an exception the app raised itself rather than mapped from a
  /// response.
  final String? method;
  final String? path;

  /// What the server wrote, when it wrote anything: the `detail` of a FastAPI
  /// error, or `DioException.message` for a failure that never reached one.
  ///
  /// Shown to the user only where a code alone cannot say why — a 403 names
  /// the missing permission and nothing else can. It is the server's own
  /// English either way, so display it framed rather than bare.
  final String? detail;

  /// Whether this is the 403 that means the API key's owner account is gone,
  /// rather than a permission the key or the account is missing.
  ///
  /// Worth telling apart because the remedy is the opposite: no scope or group
  /// change fixes it, the account has to come back. It also arrives on *every*
  /// route at once, including `/auth/me`, so the app looks broken rather than
  /// restricted (`backend/app/core/auth.py::resolve_apikey_owner`,
  /// server 1.2.6+).
  ///
  /// Matched on the server's wording, so a reworded message degrades to the
  /// framed detail — still the truth, just less specific.
  bool get isApiKeyOwnerDisabled {
    final text = detail?.toLowerCase();
    if (text == null || !text.contains('api key owner')) return false;
    return text.contains('deactivated') || text.contains('no longer exists');
  }

  @override
  String toString() =>
      '$runtimeType($code${statusCode == null ? '' : ', status=$statusCode'}'
      '${detail == null ? '' : ', detail=$detail'})';
}

/// 4xx/5xx other than 401/403, or a response of unexpected shape.
class ApiException extends AppApiException {
  const ApiException(
    super.code, {
    super.statusCode,
    super.detail,
    super.method,
    super.path,
  });
}

/// Bad credentials, an expired token or key, or missing permissions.
class AuthException extends AppApiException {
  const AuthException(
    super.code, {
    super.detail,
    super.method,
    super.path,
  });
}

/// Timeout, connection refused, or no network.
class NetworkException extends AppApiException {
  const NetworkException(
    super.code, {
    super.detail,
    super.method,
    super.path,
  });
}

/// The `on DioException catch (e) { throw mapDioException(e); }` every
/// repository would otherwise repeat.
Future<T> guard<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on DioException catch (e) {
    throw mapDioException(e);
  }
}

/// [guard] for single-entity fetches inside a composite view: one unreachable
/// printer must not empty the whole dashboard, so non-auth failures degrade to
/// `null`. Auth errors still bubble up, or the UI could not redirect.
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

/// [guardOrNull] for a read that only decorates a screen — an optional badge, a
/// nudge, a picker that is hidden when there is nothing to pick.
///
/// Same as [guardOrNull] except that a **403 also degrades to `null`**. A 401
/// still bubbles up: the session really is over and the app has to redirect. A
/// 403 is a permanent per-permission answer about one route, and throwing it out
/// of a decorative read would put a session dialog in front of a user over a
/// control they simply cannot have (`slicer_repository.presetValues` learned
/// this the hard way and handles the two apart for the same reason).
Future<T?> guardOrNullAllowingForbidden<T>(Future<T?> Function() body) async {
  try {
    return await body();
  } on DioException catch (e) {
    final mapped = mapDioException(e);
    if (mapped is AuthException && mapped.code != AppErrorCode.forbidden) {
      throw mapped;
    }
    return null;
  } on Object {
    return null;
  }
}

/// [mapDioException] keeping what the server wrote in a 400 or 422. For routes
/// enforcing rules the app deliberately does not re-implement — "Cannot delete
/// the last admin user", "Cannot rename system groups" — the reason exists only
/// in `detail`, which the plain mapper drops for those two statuses.
///
/// A 403 needs no help here: the base mapper keeps its detail for every caller,
/// because a refusal is worth explaining wherever it happens.
AppApiException mapDioExceptionKeepingDetail(DioException e) {
  final mapped = mapDioException(e);
  final status = e.response?.statusCode;
  if (mapped is! ApiException || (status != 400 && status != 422)) {
    return mapped;
  }
  final detail = serverDetailOf(e.response?.data);
  if (detail == null) return mapped;
  return ApiException(
    mapped.code,
    statusCode: status,
    detail: detail,
    method: mapped.method,
    path: mapped.path,
  );
}

/// What the server wrote, out of a FastAPI error body.
///
/// It answers a rule violation with `{"detail": "..."}` and a schema violation
/// with `{"detail": [{"msg": "..."}, ...]}` — the password complexity
/// validator produces the second shape.
///
/// Public because a route can answer one status for two unrelated reasons, and
/// then the text is the only thing that tells them apart — see
/// `_guardKeeping404Detail` in `data/inventory_source.dart`.
String? serverDetailOf(Object? data) {
  if (data is! Map) return null;
  final detail = data['detail'];
  if (detail is String) return detail.isEmpty ? null : detail;
  if (detail is List) {
    final messages = [
      for (final item in detail)
        if (item is Map && item['msg'] is String)
          // Pydantic prefixes its own "Value error, " — noise for a reader.
          (item['msg'] as String).replaceFirst('Value error, ', ''),
    ];
    if (messages.isNotEmpty) return messages.join('\n');
  }
  return null;
}

/// Maps [DioException] to a typed application exception.
AppApiException mapDioException(DioException e) {
  if (e.error is AppApiException) {
    return e.error! as AppApiException;
  }
  final method = e.requestOptions.method;
  // The same reduction `HttpProbe` records with: no host, no query, and no
  // segment the user named.
  final path = loggablePath(e.requestOptions.uri.path);
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      return NetworkException(AppErrorCode.serverUnreachable,
          detail: e.message, method: method, path: path);
    case DioExceptionType.badResponse:
      final code = e.response?.statusCode;
      if (code == 401) {
        return AuthException(AppErrorCode.unauthorized,
            method: method, path: path);
      }
      if (code == 403) {
        // The only party that knows *which* permission is missing is the
        // server, and it always says: "Missing required permissions: x" for a
        // login, "API key does not have 'y' permission" for a key. Dropping
        // that left every refusal looking identical, which from 1.2.6 also
        // covers the owner-narrowing refusals that are new to existing keys.
        return AuthException(
          AppErrorCode.forbidden,
          detail: serverDetailOf(e.response?.data),
          method: method,
          path: path,
        );
      }
      if (code == 429) {
        return ApiException(AppErrorCode.tooManyAttempts,
            statusCode: 429, method: method, path: path);
      }
      return ApiException(AppErrorCode.badResponse,
          statusCode: code, method: method, path: path);
    case DioExceptionType.badCertificate:
      return NetworkException(AppErrorCode.badCertificate,
          method: method, path: path);
    case DioExceptionType.cancel:
    case DioExceptionType.unknown:
      return NetworkException(AppErrorCode.connectionError,
          detail: e.message, method: method, path: path);
  }
}
