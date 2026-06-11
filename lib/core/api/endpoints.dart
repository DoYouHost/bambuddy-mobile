/// Wszystkie używane ścieżki API bambuddy w jednym miejscu.
///
/// Kontrakt: bambuddy v0.2.4.6 (`/api/v1`). Przy aktualizacji serwera
/// porównać z jego `/openapi.json` zanim coś się tu zmieni.
abstract final class Endpoints {
  static const apiPrefix = '/api/v1';

  static const authStatus = '$apiPrefix/auth/status';
  static const authLogin = '$apiPrefix/auth/login';

  static const printers = '$apiPrefix/printers';
  static String printerStatus(int printerId) =>
      '$apiPrefix/printers/$printerId/status';
}
