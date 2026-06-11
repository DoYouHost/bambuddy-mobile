import 'package:dio/dio.dart';

/// Bazowy wyjątek warstwy API.
sealed class AppApiException implements Exception {
  const AppApiException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Serwer odpowiedział, ale błędem (4xx/5xx poza 401/403) albo
/// odpowiedź miała nieoczekiwany kształt.
class ApiException extends AppApiException {
  const ApiException(super.message, {this.statusCode});

  final int? statusCode;
}

/// Problem z uwierzytelnieniem: złe dane logowania, wygasły/unieważniony
/// token lub klucz, brak uprawnień.
class AuthException extends AppApiException {
  const AuthException(super.message);
}

/// Serwer nieosiągalny: timeout, odmowa połączenia, brak sieci.
class NetworkException extends AppApiException {
  const NetworkException(super.message);
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
      return NetworkException('Serwer nieosiągalny (${e.message})');
    case DioExceptionType.badResponse:
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        return const AuthException('Brak autoryzacji');
      }
      return ApiException('Serwer odpowiedział błędem $code',
          statusCode: code);
    case DioExceptionType.badCertificate:
      return const NetworkException(
          'Nieprawidłowy certyfikat TLS (self-signed nieobsługiwany w v1)');
    case DioExceptionType.cancel:
    case DioExceptionType.unknown:
      return NetworkException('Błąd połączenia (${e.message})');
  }
}
