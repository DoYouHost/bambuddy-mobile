import 'package:dio/dio.dart';

/// Kody błędów warstwy API/auth. Warstwa rdzenia jest niezależna od UI:
/// tłumaczenie na tekst następuje przy wyświetlaniu (patrz
/// `lib/l10n/error_messages.dart`).
enum AppErrorCode {
  serverUnreachable,
  unauthorized,
  badResponse,
  badCertificate,
  connectionError,
  malformedResponse,
  invalidCredentials,
  twoFactorUnsupported,
  apiKeyRejected,
}

/// Bazowy wyjątek warstwy API. Niesie kod błędu (do lokalizacji) oraz
/// opcjonalne, techniczne szczegóły do logów.
sealed class AppApiException implements Exception {
  const AppApiException(this.code, {this.statusCode, this.detail});

  final AppErrorCode code;

  /// Kod HTTP dla [AppErrorCode.badResponse] (null w innych przypadkach).
  final int? statusCode;

  /// Surowy, niewidoczny dla użytkownika szczegół (np. `DioException.message`).
  final String? detail;

  @override
  String toString() =>
      '$runtimeType($code${statusCode == null ? '' : ', status=$statusCode'}'
      '${detail == null ? '' : ', detail=$detail'})';
}

/// Serwer odpowiedział, ale błędem (4xx/5xx poza 401/403) albo
/// odpowiedź miała nieoczekiwany kształt.
class ApiException extends AppApiException {
  const ApiException(super.code, {super.statusCode, super.detail});
}

/// Problem z uwierzytelnieniem: złe dane logowania, wygasły/unieważniony
/// token lub klucz, brak uprawnień.
class AuthException extends AppApiException {
  const AuthException(super.code, {super.detail});
}

/// Serwer nieosiągalny: timeout, odmowa połączenia, brak sieci.
class NetworkException extends AppApiException {
  const NetworkException(super.code, {super.detail});
}

/// Mapuje [DioException] na typowany wyjątek aplikacji.
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
      if (code == 401 || code == 403) {
        return const AuthException(AppErrorCode.unauthorized);
      }
      return ApiException(AppErrorCode.badResponse, statusCode: code);
    case DioExceptionType.badCertificate:
      return const NetworkException(AppErrorCode.badCertificate);
    case DioExceptionType.cancel:
    case DioExceptionType.unknown:
      return NetworkException(AppErrorCode.connectionError, detail: e.message);
  }
}
