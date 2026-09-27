import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:app_util/app_util.dart';
import 'package:dio/dio.dart';

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

  /// The pre-auth token is gone — elapsed, spent, or the `2fa_challenge` binding
  /// failed, which is what a proxy dropping `Set-Cookie` looks like. Only the
  /// password step produces a new one.
  twoFactorChallengeExpired,

  /// TOTP turned off between the two steps, or a backup code on an account
  /// without TOTP.
  twoFactorMethodUnavailable,

  /// No SMTP configured, or the send failed. Another method still works.
  twoFactorEmailUnavailable,

  apiKeyRejected,

  /// The slot holds no readable RFID tag, so Spoolman — which binds to the tag
  /// rather than to the (printer, AMS, tray) triple — has nothing to bind to.
  /// Raised before the request, since the server spends a bare 400 on it.
  slotTagUnreadable,

  /// The printer is not reachable, so the app cannot read what its slot holds.
  /// Told apart from [slotTagUnreadable] because the remedy is the opposite:
  /// nothing is wrong with the filament, the machine simply has to come back.
  printerOffline,

  /// 429 — refusing for now, not forever. bambuddy answers it *before* checking
  /// the password, so a rate-limited user gets it even when they finally type
  /// the right one, and "wait 15 minutes" sends them somewhere else entirely.
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
  /// guesses which request in flight the failure belongs to. [path] has been
  /// through [loggablePath] — no host, no query, no segment the user named — and
  /// both are null for an exception the app raised itself.
  final String? method;
  final String? path;

  /// What the server wrote: the `detail` of a FastAPI error, or
  /// `DioException.message` for a failure that never reached one. Shown to the
  /// user only where a code alone cannot say why, and framed rather than bare —
  /// it is the server's own English.
  final String? detail;

  /// Whether this is the 403 that means the API key's owner account is gone,
  /// rather than a permission the key or the account is missing.
  ///
  /// The remedy is the opposite of a missing permission: no scope or group
  /// change fixes it, the account has to come back. It also arrives on *every*
  /// route at once, `/auth/me` included, so the app looks broken rather than
  /// restricted (`core/auth.py::resolve_apikey_owner`).
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
  const AuthException(super.code, {super.detail, super.method, super.path});
}

/// Timeout, connection refused, or no network.
class NetworkException extends AppApiException {
  const NetworkException(super.code, {super.detail, super.method, super.path});
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

/// [guard] for a route that enforces a rule the app does not re-implement, so
/// the 400 or 422 keeps the sentence explaining it — see
/// [mapDioExceptionKeepingDetail].
Future<T> guardKeepingDetail<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on DioException catch (e) {
    throw mapDioExceptionKeepingDetail(e);
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
    _logDegraded(mapped.code.name, mapped);
    return null;
  } on Object catch (error) {
    _logDegraded(error.runtimeType.toString(), null);
    return null;
  }
}

/// [guardOrNull] for a read that only decorates a screen — an optional badge, a
/// nudge, a picker that is hidden when there is nothing to pick.
///
/// Same as [guardOrNull] except that a **403 also degrades to `null`** — it is a
/// permanent per-permission answer about one route, not a session ending, and a
/// 401 still bubbles up so the app can redirect.
Future<T?> guardOrNullAllowingForbidden<T>(Future<T?> Function() body) async {
  try {
    return await body();
  } on DioException catch (e) {
    final mapped = mapDioException(e);
    if (mapped is AuthException && mapped.code != AppErrorCode.forbidden) {
      throw mapped;
    }
    _logDegraded(mapped.code.name, mapped);
    return null;
  } on Object catch (error) {
    _logDegraded(error.runtimeType.toString(), null);
    return null;
  }
}

/// The one failure this app makes invisible on purpose, so "the dashboard shows
/// no printer" reaches a report as a screenshot of a working app. The `http`
/// record shows the failed request but not the decision to carry on without it,
/// and a `TypeError` from an unreadable response never reaches the probe at all.
/// Field list: `docs/diagnostics-log.md`.
void _logDegraded(String cause, AppApiException? failure) =>
    DiagnosticRecorder.active?.add(
      LogSource.http,
      'degraded',
      lvl: LogLevel.warn,
      fields: {
        'cause': cause,
        'status': failure?.statusCode,
        // Which call the screen carried on without; with several in flight the
        // surrounding `http` records cannot say.
        'method': failure?.method,
        'path': failure?.path == null ? null : loggablePath(failure!.path!),
      },
    );

/// [mapDioException] keeping what the server wrote in a 400 or 422, where the
/// reason for a rule the app does not re-implement ("Cannot delete the last
/// admin user") exists only in `detail`. A 403 needs no help: the base mapper
/// keeps its detail for every caller.
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
/// A rule violation arrives as `{"detail": "..."}` and a schema violation as
/// `{"detail": [{"msg": "..."}, ...]}` — the password validator produces the
/// second. Public because a route can answer one status for two unrelated
/// reasons, and then the text is all that tells them apart.
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
  return switch (classifyDioException(e)) {
    DioFailure.unreachable => NetworkException(
      AppErrorCode.serverUnreachable,
      detail: e.message,
      method: method,
      path: path,
    ),
    DioFailure.unauthorized => AuthException(
      AppErrorCode.unauthorized,
      method: method,
      path: path,
    ),
    // The only party that knows *which* permission is missing is the server,
    // and it always says: "Missing required permissions: x" for a login, "API
    // key does not have 'y' permission" for a key. Dropping that left every
    // refusal looking identical, which from 1.2.6 also covers the
    // owner-narrowing refusals that are new to existing keys.
    DioFailure.forbidden => AuthException(
      AppErrorCode.forbidden,
      detail: serverDetailOf(e.response?.data),
      method: method,
      path: path,
    ),
    DioFailure.tooManyRequests => ApiException(
      AppErrorCode.tooManyAttempts,
      statusCode: 429,
      method: method,
      path: path,
    ),
    DioFailure.badResponse => ApiException(
      AppErrorCode.badResponse,
      statusCode: e.response?.statusCode,
      method: method,
      path: path,
    ),
    DioFailure.badCertificate => NetworkException(
      AppErrorCode.badCertificate,
      method: method,
      path: path,
    ),
    // A cancel maps as it always has. The one caller that cancels, the printer
    // download job, reports it as a cancellation itself.
    DioFailure.cancelled || DioFailure.unknown => NetworkException(
      AppErrorCode.connectionError,
      detail: e.message,
      method: method,
      path: path,
    ),
  };
}
