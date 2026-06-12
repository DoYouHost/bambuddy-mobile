/// Wszystkie używane ścieżki API bambuddy w jednym miejscu.
///
/// Kontrakt: bambuddy v0.2.4.6 (`/api/v1`). Przy aktualizacji serwera
/// porównać z jego `/openapi.json` zanim coś się tu zmieni.
abstract final class Endpoints {
  static const apiPrefix = '/api/v1';

  static const authStatus = '$apiPrefix/auth/status';
  static const authLogin = '$apiPrefix/auth/login';

  // Trailing slash wymagany: serwer (FastAPI) ma trasę pod `/printers/`,
  // a `/printers` (bez slasha) zwraca 404 dla uwierzytelnionego żądania.
  static const printers = '$apiPrefix/printers/';
  static String printerStatus(int printerId) =>
      '$apiPrefix/printers/$printerId/status';

  /// Mint tokenu strumienia kamery (ważny ~60 min). Wymagany jako `?token=`
  /// dla okładki wydruku (`cover_url`) i — od M2 — dla podglądu kamery.
  static const cameraStreamToken = '$apiPrefix/printers/camera/stream-token';

  /// Strumień MJPEG kamery (`multipart/x-mixed-replace; boundary=frame`).
  /// Autoryzacja przez `?token=` (mint w [cameraStreamToken]).
  static String cameraStream(int printerId) =>
      '$apiPrefix/printers/$printerId/camera/stream';

  /// Pojedyncza klatka JPEG (fallback/odświeżenie). Również `?token=`.
  static String cameraSnapshot(int printerId) =>
      '$apiPrefix/printers/$printerId/camera/snapshot';
}
