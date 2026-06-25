/// Wszystkie używane ścieżki API bambuddy w jednym miejscu.
///
/// Kontrakt: bambuddy v0.2.4.4 (`/api/v1`). Przy aktualizacji serwera
/// porównać z jego `/openapi.json` zanim coś się tu zmieni.
abstract final class Endpoints {
  static const apiPrefix = '/api/v1';

  /// Strona przeglądarki G-code (PrettyGCode) serwowana POZA `/api/v1`.
  /// Trailing slash wymagany — `/gcode-viewer` (bez slasha) celowo spada do
  /// SPA. Sterowanie przez query: `?archive=<id>` lub `?library_file=<id>`
  /// (+ opcjonalnie `&plate=<N>`); auth czyta z `localStorage.auth_token`.
  static const gcodeViewer = '/gcode-viewer/';

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

  /// Statystyki zbiorcze archiwum. Query (wszystkie opcjonalne):
  /// `date_from`/`date_to` (YYYY-MM-DD, włącznie), `created_by_id`
  /// (filtr po autorze; `-1` = bez użytkownika).
  static const archivesStats = '$apiPrefix/archives/stats';

  /// Lekka lista wydruków (ArchiveSlim[]) do liczenia bogatych statystyk po
  /// stronie klienta. Query: `date_from`/`date_to`/`created_by_id`/`limit`/`offset`.
  static const archivesSlim = '$apiPrefix/archives/slim';

  /// Analiza niepowodzeń. Query: `days` lub `date_from`/`date_to`,
  /// `printer_id`/`project_id`/`created_by_id`.
  static const archivesFailures = '$apiPrefix/archives/analysis/failures';
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

  // --- Filamenty: magazyn szpul (inventory) ---
  //
  // Dwa backendy za wspólnym interfejsem (patrz [SpoolInventorySource]):
  // natywny `/inventory/*` (domyślny) i Spoolman `/spoolman/inventory/*`.
  // Trailing slash NIE jest tu wymagany — trasy są pod pełną ścieżką bez slasha.

  /// Lista szpul. Query: `include_archived=true|false`. Również `POST` —
  /// utworzenie szpuli (body `SpoolCreate`, zwraca `SpoolResponse`).
  static const inventorySpools = '$apiPrefix/inventory/spools';

  /// Pojedyncza szpula: `GET` (szczegóły), `PATCH` (edycja, body `SpoolUpdate`),
  /// `DELETE` (trwałe usunięcie). Zapisy wymagają uprawnienia na kluczu (→ 403).
  static String inventorySpool(int spoolId) =>
      '$apiPrefix/inventory/spools/$spoolId';

  /// Archiwizacja szpuli (`POST`, bez body). Odwrotność: [inventorySpoolRestore].
  static String inventorySpoolArchive(int spoolId) =>
      '$apiPrefix/inventory/spools/$spoolId/archive';

  /// Przywrócenie zarchiwizowanej szpuli (`POST`, bez body).
  static String inventorySpoolRestore(int spoolId) =>
      '$apiPrefix/inventory/spools/$spoolId/restore';

  /// Reset zużycia szpuli do zera (`POST`, bez body).
  static String inventorySpoolResetUsage(int spoolId) =>
      '$apiPrefix/inventory/spools/$spoolId/reset-usage';

  /// Historia zużycia szpuli (`SpoolUsageHistoryResponse[]`).
  static String inventorySpoolUsage(int spoolId) =>
      '$apiPrefix/inventory/spools/$spoolId/usage';

  /// Przypisania szpul do slotów AMS (`SpoolAssignmentResponse[]`). Również
  /// `POST` — przypisanie szpuli (body `SpoolAssignmentCreate`).
  static const inventoryAssignments = '$apiPrefix/inventory/assignments';

  /// Odpięcie szpuli ze slotu (`DELETE`) — klucz to trójka (drukarka, jednostka
  /// AMS, taca). Szpula zewnętrzna: `amsId=255`, `trayId` 0=lewy/1=prawy.
  static String inventoryAssignment(int printerId, int amsId, int trayId) =>
      '$apiPrefix/inventory/assignments/$printerId/$amsId/$trayId';

  // --- Dane referencyjne formularza szpuli (Faza 2) ---

  /// Katalog wag rdzeni szpul (`CatalogEntryResponse[]`: id/name/weight/
  /// is_default) — do pola „Empty Spool Weight".
  static const inventoryCatalog = '$apiPrefix/inventory/catalog';

  /// Baza kolorów filamentów (`ColorEntryResponse[]`: manufacturer/color_name/
  /// hex_color/material/extra_colors/effect_type/is_default) — picker kolorów.
  /// Źródło dropdownów materiału/marki to istniejący [filamentCatalog].
  static const inventoryColors = '$apiPrefix/inventory/colors';

  /// Profile kalibracji K szpuli (`SpoolKProfileResponse[]`). `PUT` zastępuje
  /// całą listę (body `SpoolKProfileBase[]`). Zakładka PA Profile.
  static String inventorySpoolKProfiles(int spoolId) =>
      '$apiPrefix/inventory/spools/$spoolId/k-profiles';

  // Backend Spoolman (drop-in — inny kształt danych).
  static const spoolmanSpools = '$apiPrefix/spoolman/inventory/spools';
  static String spoolmanSpool(int spoolId) =>
      '$apiPrefix/spoolman/inventory/spools/$spoolId';
  static String spoolmanSpoolArchive(int spoolId) =>
      '$apiPrefix/spoolman/inventory/spools/$spoolId/archive';
  static String spoolmanSpoolRestore(int spoolId) =>
      '$apiPrefix/spoolman/inventory/spools/$spoolId/restore';
  static String spoolmanSpoolResetUsage(int spoolId) =>
      '$apiPrefix/spoolman/inventory/spools/$spoolId/reset-usage';
  static const spoolmanAssignments =
      '$apiPrefix/spoolman/inventory/slot-assignments/all';

  // Katalog filamentów (definicje/profile — `FilamentResponse[]`).
  static const filamentCatalog = '$apiPrefix/filament-catalog/';

  // --- Firmware ---

  /// Firmware całej farmy jednym zapytaniem (`FirmwareUpdatesResponse`:
  /// `{updates:[FirmwareUpdateInfo], updates_available:int}`).
  static const firmwareUpdates = '$apiPrefix/firmware/updates';

  /// Firmware jednej drukarki (`FirmwareUpdateInfo`).
  static String firmwareUpdate(int printerId) =>
      '$apiPrefix/firmware/updates/$printerId';

  /// Najnowsze firmware per model (`LatestFirmwareInfo[]`).
  static const firmwareLatest = '$apiPrefix/firmware/latest';

  // Poniższe na PRZYSZŁOŚĆ — wykonywanie aktualizacji (nieużywane jeszcze w UI).

  /// Sonda przed wgraniem firmware (`FirmwareUploadPrepareResponse`).
  static String firmwarePrepare(int printerId) =>
      '$apiPrefix/firmware/updates/$printerId/prepare';

  /// Start wgrywania firmware (`FirmwareUploadStartResponse`). Query: `version`.
  /// Wymaga uprawnienia sterowania na kluczu API (brak → 403).
  static String firmwareUpload(int printerId) =>
      '$apiPrefix/firmware/updates/$printerId/upload';

  /// Postęp wgrywania firmware (`FirmwareUploadStatusResponse`).
  static String firmwareUploadStatus(int printerId) =>
      '$apiPrefix/firmware/updates/$printerId/upload/status';

  // --- Menedżer plików / biblioteka (library) ---
  //
  // Pliki druku (3mf/gcode/stl…) zorganizowane w drzewo folderów. Auth
  // nagłówkiem (X-API-Key / Bearer) — poza miniaturą, która (jak archiwum)
  // idzie przez `?token=` token kamery.

  /// Lista plików. Query (wszystkie opcjonalne): `folder_id` (null = poziom
  /// root przy `include_root=true`), `project_id`, `include_root` (domyślnie
  /// true). Zwraca `FileListResponse[]`. Również `POST` — upload pliku
  /// (multipart, query `folder_id` + `generate_stl_thumbnails`).
  static const libraryFiles = '$apiPrefix/library/files';

  /// Pojedynczy plik: `GET` (szczegóły), `PUT` (edycja `FileUpdate`:
  /// filename/folder_id/notes), `DELETE` (do kosza).
  static String libraryFile(int fileId) => '$apiPrefix/library/files/$fileId';

  /// Pobranie pliku (`GET`, strumień bajtów). Auth nagłówkiem.
  static String libraryFileDownload(int fileId) =>
      '$apiPrefix/library/files/$fileId/download';

  /// Miniatura pliku — uwierzytelniana przez `?token=` (token kamery), NIE
  /// nagłówkiem, analogicznie do [archiveThumbnail].
  static String libraryFileThumbnail(int fileId) =>
      '$apiPrefix/library/files/$fileId/thumbnail';

  /// Wysłanie pliku do druku na drukarce. Query `printer_id`; body opcjonalne
  /// (`FilePrintRequest`). Tylko pliki skrojone (.gcode/.gcode.3mf).
  static String libraryFilePrint(int fileId) =>
      '$apiPrefix/library/files/$fileId/print';

  /// Przeniesienie plików do folderu (`POST`, body `FileMoveRequest`:
  /// `{file_ids, folder_id}`; `folder_id=null` = root).
  static const libraryFilesMove = '$apiPrefix/library/files/move';

  /// Dodanie plików do kolejki (`POST`, body `AddToQueueRequest`:
  /// `{file_ids}`).
  static const libraryFilesAddToQueue = '$apiPrefix/library/files/add-to-queue';

  /// Zbiorcze usunięcie do kosza (`POST`, body `BulkDeleteRequest`:
  /// `{file_ids, folder_ids}`).
  static const libraryBulkDelete = '$apiPrefix/library/bulk-delete';

  /// Drzewo folderów (`FolderTreeItem[]`, zagnieżdżone przez `children`).
  /// Również `POST` — utworzenie folderu (`FolderCreate`: name/parent_id…).
  static const libraryFolders = '$apiPrefix/library/folders';

  /// Pojedynczy folder: `PUT` (edycja `FolderUpdate`: name/parent_id),
  /// `DELETE` (usunięcie folderu wraz z zawartością).
  static String libraryFolder(int folderId) =>
      '$apiPrefix/library/folders/$folderId';

  /// Statystyki biblioteki (liczba plików/folderów, rozmiar, wolne miejsce).
  static const libraryStats = '$apiPrefix/library/stats';

  // --- Kosz biblioteki (library-trash) ---

  /// Lista plików w koszu (`TrashListResponse`: items/total/retention_days).
  /// Również `DELETE` — opróżnienie kosza (`EmptyTrashResponse`).
  static const libraryTrash = '$apiPrefix/library/trash';

  /// Przywrócenie pliku z kosza (`POST`, bez body).
  static String libraryTrashRestore(int fileId) =>
      '$apiPrefix/library/trash/$fileId/restore';

  /// Trwałe usunięcie pliku z kosza (`DELETE`).
  static String libraryTrashItem(int fileId) =>
      '$apiPrefix/library/trash/$fileId';

  // --- MakerWorld + Bambu Cloud ---

  /// Stan integracji MakerWorld (`GET`): `{has_cloud_token, can_download}`.
  /// `can_download=false` → brak/nieważny token chmury Bambu, pobieranie
  /// niedostępne (użytkownik musi się zalogować — patrz [cloudLogin]).
  static const makerworldStatus = '$apiPrefix/makerworld/status';

  /// Rozwiązanie dowolnego URL-a modelu MakerWorld (`POST`, body `{url}`)
  /// → `MakerWorldResolvedModel` (design + lista instancji/płyt). Nie wymaga
  /// tokenu chmury — działa także wylogowanym.
  static const makerworldResolve = '$apiPrefix/makerworld/resolve';

  /// Import (pobranie) instancji do biblioteki (`POST`, body
  /// `{model_id, profile_id?, folder_id?}`) → `MakerWorldImportResponse`.
  /// Wymaga ważnego tokenu chmury Bambu (inaczej błąd).
  static const makerworldImport = '$apiPrefix/makerworld/import';

  /// Ostatnie importy z MakerWorld (`GET`, query `limit`).
  static const makerworldRecentImports =
      '$apiPrefix/makerworld/recent-imports';

  /// Proxy miniatury MakerWorld (`GET`, query `url=<URL okładki>`). Publiczny
  /// — bez auth; używany bezpośrednio przez `Image.network`.
  static const makerworldThumbnail = '$apiPrefix/makerworld/thumbnail';

  /// Stan logowania do chmury Bambu (`GET`): `{is_authenticated, email?, region?}`.
  static const cloudStatus = '$apiPrefix/cloud/status';

  /// Logowanie do chmury Bambu (`POST`, body `{email, password, region}`)
  /// → `CloudLoginResponse`. `needs_verification=true` → dosyłamy kod przez
  /// [cloudVerify].
  static const cloudLogin = '$apiPrefix/cloud/login';

  /// Weryfikacja kodu 2FA/OTP (`POST`, body `{email, code, tfa_key?, region}`).
  static const cloudVerify = '$apiPrefix/cloud/verify';

  /// Wylogowanie z chmury Bambu (`POST`, bez body).
  static const cloudLogout = '$apiPrefix/cloud/logout';
}
