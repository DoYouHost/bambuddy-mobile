/// Wszystkie używane ścieżki API bambuddy w jednym miejscu.
///
/// Kontrakt: bambuddy v0.2.4.4 (`/api/v1`). Przy aktualizacji serwera
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

  // --- Sterowanie (M4) ---
  // Wszystkie to POST; wymagają uprawnienia `can_control_printer` na kluczu
  // API (brak → 403). Body puste — parametry idą w query (patrz niżej).

  static String printPause(int printerId) =>
      '$apiPrefix/printers/$printerId/print/pause';
  static String printResume(int printerId) =>
      '$apiPrefix/printers/$printerId/print/resume';
  static String printStop(int printerId) =>
      '$apiPrefix/printers/$printerId/print/stop';

  /// Światło komory. Query: `on=true|false`.
  static String chamberLight(int printerId) =>
      '$apiPrefix/printers/$printerId/chamber-light';

  /// Prędkość druku. Query: `mode=1..4` (1 Silent, 2 Standard, 3 Sport,
  /// 4 Ludicrous) — zgodne z [PrinterStatus.speedLevel].
  static String printSpeed(int printerId) =>
      '$apiPrefix/printers/$printerId/print-speed';

  // --- Kolejka + archiwum (M5) ---

  // Trailing slash wymagany: serwer (FastAPI) ma trasę pod `/queue/`,
  // a `/queue` (bez slasha) zwraca 404 dla uwierzytelnionego żądania.
  static const queue = '$apiPrefix/queue/';
  static const queueReorder = '$apiPrefix/queue/reorder';
  static String queueItem(int itemId) => '$apiPrefix/queue/$itemId';
  static String queueItemStart(int itemId) => '$apiPrefix/queue/$itemId/start';
  static String queueItemCancel(int itemId) =>
      '$apiPrefix/queue/$itemId/cancel';

  // Trailing slash wymagany: analogicznie do `/queue/`.
  static const archives = '$apiPrefix/archives/';
  static const archivesSearch = '$apiPrefix/archives/search';
  static String archiveReprint(int archiveId) =>
      '$apiPrefix/archives/$archiveId/reprint';

  /// Miniatura uwierzytelniana przez `?token=` (token kamery), NIE nagłówkiem
  /// — patrz okładka w printer_card.
  static String archiveThumbnail(int archiveId) =>
      '$apiPrefix/archives/$archiveId/thumbnail';

  // --- Smart gniazdka (M7) ---

  /// Lista wszystkich gniazdek (SmartPlugResponse[]). Każdy wpis niesie
  /// `printer_id` — stąd mapowanie gniazdko↔drukarka bez N zapytań.
  /// Trailing slash wymagany (FastAPI), analogicznie do `/printers/`.
  static const smartPlugs = '$apiPrefix/smart-plugs/';

  /// Żywy status gniazdka (SmartPlugStatus): stan on/off + pomiar mocy/energii.
  static String smartPlugStatus(int plugId) =>
      '$apiPrefix/smart-plugs/$plugId/status';

  /// Sterowanie gniazdkiem. Body JSON `{"action":"on"|"off"|"toggle"}`.
  /// Wymaga uprawnienia sterowania na kluczu API (brak → 403).
  static String smartPlugControl(int plugId) =>
      '$apiPrefix/smart-plugs/$plugId/control';

  // --- Konserwacja (M7) ---

  /// Przegląd konserwacji wszystkich aktywnych drukarek
  /// (`PrinterMaintenanceOverview[]`).
  static const maintenanceOverview = '$apiPrefix/maintenance/overview';

  /// Przegląd konserwacji jednej drukarki (`PrinterMaintenanceOverview`).
  static String maintenancePrinter(int printerId) =>
      '$apiPrefix/maintenance/printers/$printerId';

  /// Oznaczenie czynności jako wykonanej (reset licznika). Body
  /// `{"notes": string?}`. Wymaga uprawnienia sterowania (brak → 403).
  static String maintenancePerform(int itemId) =>
      '$apiPrefix/maintenance/items/$itemId/perform';

  /// Historia wykonania czynności (`MaintenanceHistoryResponse[]`).
  static String maintenanceHistory(int itemId) =>
      '$apiPrefix/maintenance/items/$itemId/history';
}
