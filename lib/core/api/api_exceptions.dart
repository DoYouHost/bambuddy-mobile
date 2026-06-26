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
  twoFactorUnsupported,
  apiKeyRejected,
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
      return ApiException(AppErrorCode.badResponse, statusCode: code);
    case DioExceptionType.badCertificate:
      return const NetworkException(AppErrorCode.badCertificate);
    case DioExceptionType.cancel:
    case DioExceptionType.unknown:
      return NetworkException(AppErrorCode.connectionError, detail: e.message);
  }
}
