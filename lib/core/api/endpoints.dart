/// All bambuddy API endpoints in one place.
///
/// Contract: bambuddy v0.2.4.8 (`/api/v1`). When updating the server,
/// compare with `/openapi.json` before changing anything here.
abstract final class Endpoints {
  static const apiPrefix = '/api/v1';

  /// G-code browser page (PrettyGCode) served outside `/api/v1`.
  /// Trailing slash required — `/gcode-viewer` (without slash) intentionally
  /// falls back to SPA. Control via query: `?archive=<id>` or `?library_file=<id>`
  /// (+ optionally `&plate=<N>`); auth read from `localStorage.auth_token`.
  static const gcodeViewer = '/gcode-viewer/';

  static const authStatus = '$apiPrefix/auth/status';
  static const authLogin = '$apiPrefix/auth/login';

  /// Mint a short-lived WebSocket token (valid ~60 min). Required as `?token=`
  /// on the `/ws` handshake (GHSA-r2qv follow-up) — the upgrade can't carry
  /// `Authorization`/`X-API-Key` headers, so the server validates this token
  /// before accepting the connection.
  static const wsToken = '$apiPrefix/auth/ws-token';

  // Trailing slash required: server (FastAPI) has route at `/printers/`,
  // and `/printers` (without slash) returns 404 for authenticated requests.
  static const printers = '$apiPrefix/printers/';

  /// Filaments currently loaded on active printers of a model (query `model`,
  /// optional `location`) — options for model-based filament overrides.
  static const printersAvailableFilaments =
      '$apiPrefix/printers/available-filaments';
  static String printerStatus(int printerId) =>
      '$apiPrefix/printers/$printerId/status';

  /// Pre-save connection diagnostic for the Add-Printer flow (`POST`, body
  /// `{ip_address, serial_number?, access_code?}`). Returns
  /// `PrinterDiagnosticResult` (`{overall, checks:[{id,status,params}]}`).
  /// Requires the `PRINTERS_CREATE` permission.
  static const printersDiagnostic = '$apiPrefix/printers/diagnostic';

  // --- Discovery (SSDP + subnet scan) ---
  // Requires the `DISCOVERY_SCAN` permission (missing → 403).

  /// Environment info (`GET`): `{is_docker, ssdp_running, scan_running,
  /// subnets:[cidr]}` — drives the subnet picker in the Add-Printer flow.
  static const discoveryInfo = '$apiPrefix/discovery/info';

  /// Start a subnet scan (`POST`, body `{subnet, timeout}`) → `SubnetScanStatus`
  /// `{running, scanned, total}`. Runs in the background; poll [discoveryScanStatus].
  static const discoveryScan = '$apiPrefix/discovery/scan';

  /// Current subnet-scan progress (`GET`) → `{running, scanned, total}`.
  static const discoveryScanStatus = '$apiPrefix/discovery/scan/status';

  /// Printers found so far (`GET`, from both SSDP + subnet scan) →
  /// `[{serial, name, ip_address, model, discovered_at}]`.
  static const discoveryPrinters = '$apiPrefix/discovery/printers';

  /// Start SSDP multicast discovery (`POST`, query `duration` seconds). Used on
  /// native installs; poll [discoveryPrinters] and stop with [discoveryStop].
  static const discoveryStart = '$apiPrefix/discovery/start';

  /// Stop SSDP discovery (`POST`).
  static const discoveryStop = '$apiPrefix/discovery/stop';

  /// AMS sensor history (temperature + humidity) for one AMS unit.
  /// Query `?hours=1..168`. Reference: bambuddy `ams_history.py`.
  static String amsHistory(int printerId, int amsId) =>
      '$apiPrefix/ams-history/$printerId/$amsId';

  /// Mint camera stream token (valid ~60 min). Required as `?token=`
  /// for print cover (`cover_url`) and — from M2 — for camera preview.
  static const cameraStreamToken = '$apiPrefix/printers/camera/stream-token';

  /// MJPEG camera stream (`multipart/x-mixed-replace; boundary=frame`).
  /// Authorization via `?token=` (minted at [cameraStreamToken]).
  static String cameraStream(int printerId) =>
      '$apiPrefix/printers/$printerId/camera/stream';

  // --- Printer storage / file manager ---
  // Browse the printer's own storage (SD/eMMC) over the server's FTP bridge.
  // All require the `PRINTERS_FILES` permission. `path` is a query parameter.

  /// List entries at `?path=` (default `/`). Response: `{path, files:[...]}`.
  static String printerFiles(int printerId) =>
      '$apiPrefix/printers/$printerId/files';

  /// Download a single file (`?path=`) as a binary stream with
  /// `Content-Disposition`. Same route as [printerFiles] but `/download`.
  static String printerFileDownload(int printerId) =>
      '$apiPrefix/printers/$printerId/files/download';

  /// Download several files (`{"paths":[...]}` body) bundled as one ZIP.
  static String printerFilesDownloadZip(int printerId) =>
      '$apiPrefix/printers/$printerId/files/download-zip';

  /// `DELETE ?path=` removes one file. Same route as [printerFiles].
  static String printerFileDelete(int printerId) =>
      '$apiPrefix/printers/$printerId/files';

  /// Storage usage: `{used_bytes, free_bytes}` (both may be null).
  static String printerStorage(int printerId) =>
      '$apiPrefix/printers/$printerId/storage';

  // --- Control (M4) ---
  // All are POST; require `can_control_printer` permission on API key
  // (missing → 403). Body empty — parameters in query (see below).

  static String printPause(int printerId) =>
      '$apiPrefix/printers/$printerId/print/pause';
  static String printResume(int printerId) =>
      '$apiPrefix/printers/$printerId/print/resume';
  static String printStop(int printerId) =>
      '$apiPrefix/printers/$printerId/print/stop';

  /// Acknowledge the build plate is cleared after a finished/failed print, so
  /// the scheduler may start the next queued print (`POST`, empty body). Gated
  /// on the `require_plate_clear` server setting.
  static String printerClearPlate(int printerId) =>
      '$apiPrefix/printers/$printerId/clear-plate';

  /// Chamber light. Query: `on=true|false`.
  static String chamberLight(int printerId) =>
      '$apiPrefix/printers/$printerId/chamber-light';

  /// Print speed. Query: `mode=1..4` (1 Silent, 2 Standard, 3 Sport,
  /// 4 Ludicrous) — matches [PrinterStatus.speedLevel].
  static String printSpeed(int printerId) =>
      '$apiPrefix/printers/$printerId/print-speed';

  /// Nozzle target temperature. Query: `target` 0–320 (0 = off),
  /// `nozzle` 0|1 (0 = right/default, 1 = left on dual-head H2D/X2D).
  static String nozzleTemperature(int printerId) =>
      '$apiPrefix/printers/$printerId/temperature/nozzle';

  /// Bed target temperature. Query: `target` 0–140 (0 = off).
  static String bedTemperature(int printerId) =>
      '$apiPrefix/printers/$printerId/temperature/bed';

  /// Chamber target temperature. Query: `target` 0–60 (0 = off). Server returns
  /// 400 unless the model has an active chamber heater (H2C/H2D/H2D Pro/H2S/X2D)
  /// — gate client-side via `supportsChamberHeater` before calling.
  static String chamberTemperature(int printerId) =>
      '$apiPrefix/printers/$printerId/temperature/chamber';

  /// Airduct flap mode. Query: `mode=cooling|heating`. Supported on
  /// P2S/X2D/H2* — gate via `supportsAirduct` first.
  static String airductMode(int printerId) =>
      '$apiPrefix/printers/$printerId/airduct-mode';

  /// Fan speed. Query: `fan=part|aux|chamber`, `speed` 0–100 (%).
  static String fanSpeed(int printerId) =>
      '$apiPrefix/printers/$printerId/fan-speed';

  /// Select the active extruder on dual-nozzle printers. Query: `extruder=0|1`
  /// (0=right, 1=left).
  static String selectExtruder(int printerId) =>
      '$apiPrefix/printers/$printerId/select-extruder';

  /// Start AMS drying. Query: `ams_id`, `temp` 45–85, `duration` 1–24 (hours),
  /// optional `filament` (backfilled server-side) and `rotate_tray`. Gated on
  /// [PrinterStatus.supportsDrying]; server may 409 with a blocking reason.
  static String dryingStart(int printerId) =>
      '$apiPrefix/printers/$printerId/drying/start';

  /// Stop AMS drying. Query: `ams_id`.
  static String dryingStop(int printerId) =>
      '$apiPrefix/printers/$printerId/drying/stop';

  // --- Movement / jog (manual control; idle only) ---
  // All POST, empty body, params in query. Relative moves; the server maps the
  // Z sign per model (A1 bed-slingers are inverted). Require `can_control_printer`.

  /// Relative nozzle-bed gap jog. Query: `distance` (signed mm, |d|≤200;
  /// negative = decrease gap / "up"), `force` (bypass soft endstops when Z is
  /// not homed). Server flips the Z sign on A1 bed-slingers so "up" stays "up".
  static String bedJog(int printerId) =>
      '$apiPrefix/printers/$printerId/bed-jog';

  /// Relative toolhead X/Y jog. Query: `x`, `y` (signed mm, |·|≤200 each).
  static String xyJog(int printerId) =>
      '$apiPrefix/printers/$printerId/xy-jog';

  /// Relative extrusion. Query: `distance` (signed mm, |d|≤100; +extrude,
  /// −retract). Firmware refuses extrusion below the min-extrude temperature.
  static String extruderJog(int printerId) =>
      '$apiPrefix/printers/$printerId/extruder-jog';

  /// Full auto-home (bare `G28`). Query `axes` is accepted but ignored — the
  /// server always runs the safe park → home-XY → home-Z sequence.
  static String homeAxes(int printerId) =>
      '$apiPrefix/printers/$printerId/home-axes';

  /// Printable objects for the current print (`GET`). Query `reload=true`
  /// re-reads them from the 3MF (useful after a restart). Returns
  /// `{objects:[{id,name,x,y,skipped}], total, skipped_count, is_printing,
  /// bbox_all}`.
  static String printObjects(int printerId) =>
      '$apiPrefix/printers/$printerId/print/objects';

  /// Skip objects during the current print (`POST`, JSON body is a bare array
  /// of `identify_id` ints, e.g. `[683]`). Requires `can_control_printer`.
  static String printSkipObjects(int printerId) =>
      '$apiPrefix/printers/$printerId/print/skip-objects';

  /// Current print cover image. Query `view=top` gives the top-down build-plate
  /// render used for the skip-objects overlay. Auth via `?token=` (camera stream
  /// token), NOT via header — same as [PrinterStatus.coverUrl].
  static String printerCover(int printerId) =>
      '$apiPrefix/printers/$printerId/cover';

  // --- Queue + archive (M5) ---

  // Trailing slash required: server (FastAPI) has route at `/queue/`,
  // and `/queue` (without slash) returns 404 for authenticated requests.
  static const queue = '$apiPrefix/queue/';
  static const queueReorder = '$apiPrefix/queue/reorder';
  static String queueItem(int itemId) => '$apiPrefix/queue/$itemId';
  static String queueItemStart(int itemId) => '$apiPrefix/queue/$itemId/start';
  static String queueItemCancel(int itemId) =>
      '$apiPrefix/queue/$itemId/cancel';

  // Trailing slash required: similar to `/queue/`.
  static const archives = '$apiPrefix/archives/';
  static const archivesSearch = '$apiPrefix/archives/search';

  /// Archive aggregate statistics. Query (all optional):
  /// `date_from`/`date_to` (YYYY-MM-DD, inclusive), `created_by_id`
  /// (filter by author; `-1` = no user).
  static const archivesStats = '$apiPrefix/archives/stats';

  /// Lightweight print list (ArchiveSlim[]) for rich client-side stats.
  /// Query: `date_from`/`date_to`/`created_by_id`/`limit`/`offset`.
  static const archivesSlim = '$apiPrefix/archives/slim';

  /// Failure analysis. Query: `days` or `date_from`/`date_to`,
  /// `printer_id`/`project_id`/`created_by_id`.
  static const archivesFailures = '$apiPrefix/archives/analysis/failures';

  /// Delete an archive (`DELETE`). Soft by default (keeps aggregate stats);
  /// query `purge_stats=true` hard-deletes, removing the print from statistics.
  static String archive(int archiveId) => '$apiPrefix/archives/$archiveId';

  /// Toggle an archive's favorite flag (`POST`, no body) → updated archive.
  static String archiveFavorite(int archiveId) =>
      '$apiPrefix/archives/$archiveId/favorite';

  /// Bulk-delete prints older than a threshold (`POST`, body
  /// `{older_than_days, purge_stats}`) → `{deleted, purge_stats}`. Soft by
  /// default; `purge_stats=true` also drops them from /stats (irreversible).
  static const archivesPurge = '$apiPrefix/archives/purge';

  /// Read-only preview of [archivesPurge] (`GET`). Query: `older_than_days`
  /// (required), `purge_stats` → `ArchivePurgePreviewResponse`.
  static const archivesPurgePreview = '$apiPrefix/archives/purge/preview';

  /// Thumbnail authenticated via `?token=` (camera token), NOT via header
  /// — see cover in printer_card.
  static String archiveThumbnail(int archiveId) =>
      '$apiPrefix/archives/$archiveId/thumbnail';

  /// Viewing/slicing capabilities of an archive's 3MF — `{has_model, has_gcode,
  /// has_source, build_volume, filament_colors}`. Slice is only meaningful when
  /// `has_source` or `has_model` is true (gcode-only archives can't be parsed).
  static String archiveCapabilities(int archiveId) =>
      '$apiPrefix/archives/$archiveId/capabilities';

  /// Enqueue a slice job for an archive's source/model (`POST`, body
  /// `SliceRequest`). Returns `202 {job_id}`; poll [sliceJob].
  static String archiveSlice(int archiveId) =>
      '$apiPrefix/archives/$archiveId/slice';

  /// Per-filament requirements parsed from an archive's 3MF — `{filaments:
  /// [{slot_id, type, color, ...}]}`. Drives the multi-filament slice mapping.
  static String archiveFilamentRequirements(int archiveId) =>
      '$apiPrefix/archives/$archiveId/filament-requirements';

  // --- Slicer (server-side slicing via sidecar; gated by use_slicer_api) ---

  /// Enqueue a slice job for a library file (`POST`, body `SliceRequest`).
  /// Returns `202 {job_id}`; poll [sliceJob].
  static String libraryFileSlice(int fileId) =>
      '$apiPrefix/library/files/$fileId/slice';

  /// Per-filament requirements parsed from a library file's 3MF. See
  /// [archiveFilamentRequirements].
  static String libraryFileFilamentRequirements(int fileId) =>
      '$apiPrefix/library/files/$fileId/filament-requirements';

  /// Poll a slice job (`GET`) → status/progress/result. See [archiveSlice].
  static String sliceJob(int jobId) => '$apiPrefix/slice-jobs/$jobId';

  /// Unified preset list across local/cloud/standard tiers for the slice modal
  /// (`GET`, query `refresh`). Returns `UnifiedPresetsResponse`.
  static const slicerPresets = '$apiPrefix/slicer/presets';

  /// Server-wide app settings (`AppSettings`). We only read `use_slicer_api`
  /// here to gate the slice UI; full settings management lives on the web.
  static const appSettings = '$apiPrefix/settings';

  // --- Smart plugs (M7) ---

  /// List of all smart plugs (SmartPlugResponse[]). Each entry carries
  /// `printer_id` — from this, map plug↔printer without N queries.
  /// Trailing slash required (FastAPI), similar to `/printers/`.
  static const smartPlugs = '$apiPrefix/smart-plugs/';

  /// Live smart plug status (SmartPlugStatus): on/off state + power/energy measurement.
  static String smartPlugStatus(int plugId) =>
      '$apiPrefix/smart-plugs/$plugId/status';

  /// Control smart plug. JSON body `{"action":"on"|"off"|"toggle"}`.
  /// Requires control permission on API key (missing → 403).
  static String smartPlugControl(int plugId) =>
      '$apiPrefix/smart-plugs/$plugId/control';

  // --- Maintenance (M7) ---

  /// Maintenance overview for all active printers
  /// (`PrinterMaintenanceOverview[]`).
  static const maintenanceOverview = '$apiPrefix/maintenance/overview';

  /// Maintenance overview for one printer (`PrinterMaintenanceOverview`).
  static String maintenancePrinter(int printerId) =>
      '$apiPrefix/maintenance/printers/$printerId';

  /// Maintenance types catalog (`MaintenanceTypeResponse[]`). `GET` lists
  /// (system + custom); `POST` creates a custom type (body
  /// `MaintenanceTypeCreate`). Requires create permission on `POST`.
  static const maintenanceTypes = '$apiPrefix/maintenance/types';

  /// Single maintenance type: `PATCH` (edit, body `MaintenanceTypeUpdate`),
  /// `DELETE` (custom → hard delete; system → soft-hidden, restorable).
  static String maintenanceType(int typeId) =>
      '$apiPrefix/maintenance/types/$typeId';

  /// Restore soft-deleted default (system) maintenance types (`POST`, no body).
  static const maintenanceRestoreDefaults =
      '$apiPrefix/maintenance/types/restore-defaults';

  /// Single printer maintenance item: `PATCH` (body `PrinterMaintenanceUpdate`:
  /// `custom_interval_hours`, `custom_interval_type`, `enabled`), `DELETE`
  /// (unassign a custom type from the printer). Requires update/delete permission.
  static String maintenanceItem(int itemId) =>
      '$apiPrefix/maintenance/items/$itemId';

  /// Assign a maintenance type to a printer (`POST`, no body) — needed for
  /// custom types to appear on that printer.
  static String maintenanceAssign(int printerId, int typeId) =>
      '$apiPrefix/maintenance/printers/$printerId/assign/$typeId';

  /// Mark task as performed (reset counter). Body
  /// `{"notes": string?}`. Requires control permission (missing → 403).
  static String maintenancePerform(int itemId) =>
      '$apiPrefix/maintenance/items/$itemId/perform';

  /// Task execution history (`MaintenanceHistoryResponse[]`).
  static String maintenanceHistory(int itemId) =>
      '$apiPrefix/maintenance/items/$itemId/history';

  // --- Filaments: spool inventory ---
  //
  // Two backends under common interface (see [SpoolInventorySource]):
  // native `/inventory/*` (default) and Spoolman `/spoolman/inventory/*`.
  // Trailing slash NOT required — routes are at full path without slash.

  /// List spools. Query: `include_archived=true|false`. Also `POST` —
  /// create spool (body `SpoolCreate`, returns `SpoolResponse`).
  static const inventorySpools = '$apiPrefix/inventory/spools';

  /// Bulk-create identical spools ("restock"). `POST` body
  /// `SpoolBulkCreate` (`{spool: SpoolCreate, quantity: 1..100}`), returns
  /// `SpoolResponse[]`.
  static const inventorySpoolsBulk = '$apiPrefix/inventory/spools/bulk';

  /// Single spool: `GET` (details), `PATCH` (edit, body `SpoolUpdate`),
  /// `DELETE` (permanent deletion). Writes require permission on key (→ 403).
  static String inventorySpool(int spoolId) =>
      '$apiPrefix/inventory/spools/$spoolId';

  /// Archive spool (`POST`, no body). Reverse: [inventorySpoolRestore].
  static String inventorySpoolArchive(int spoolId) =>
      '$apiPrefix/inventory/spools/$spoolId/archive';

  /// Restore archived spool (`POST`, no body).
  static String inventorySpoolRestore(int spoolId) =>
      '$apiPrefix/inventory/spools/$spoolId/restore';

  /// Reset spool usage to zero (`POST`, no body).
  static String inventorySpoolResetUsage(int spoolId) =>
      '$apiPrefix/inventory/spools/$spoolId/reset-usage';

  /// Spool usage history (`SpoolUsageHistoryResponse[]`).
  static String inventorySpoolUsage(int spoolId) =>
      '$apiPrefix/inventory/spools/$spoolId/usage';

  /// Spool-to-AMS-slot assignments (`SpoolAssignmentResponse[]`). Also
  /// `POST` — assign spool (body `SpoolAssignmentCreate`).
  static const inventoryAssignments = '$apiPrefix/inventory/assignments';

  /// Unassign spool from slot (`DELETE`) — key is triple (printer, AMS unit,
  /// tray). External spool: `amsId=255`, `trayId` 0=left/1=right.
  static String inventoryAssignment(int printerId, int amsId, int trayId) =>
      '$apiPrefix/inventory/assignments/$printerId/$amsId/$trayId';

  // --- Spool form reference data (Phase 2) ---

  /// Spool core weight catalog (`CatalogEntryResponse[]`: id/name/weight/
  /// is_default) — for "Empty Spool Weight" field.
  static const inventoryCatalog = '$apiPrefix/inventory/catalog';

  /// Filament color database (`ColorEntryResponse[]`: manufacturer/color_name/
  /// hex_color/material/extra_colors/effect_type/is_default) — color picker.
  /// Material/brand dropdown source is existing [filamentCatalog].
  static const inventoryColors = '$apiPrefix/inventory/colors';

  /// Storage-location catalog (`LocationResponse[]`: id/name/spool_count/...).
  /// Drives the spool location picker. A spool create/update that sends a
  /// free-text `storage_location` auto-creates the matching catalog entry
  /// server-side, so the app doesn't need to POST here to "add" a location.
  static const inventoryLocations = '$apiPrefix/inventory/locations';

  /// Spool K calibration profiles (`SpoolKProfileResponse[]`). `PUT` replaces
  /// entire list (body `SpoolKProfileBase[]`). PA Profile tab.
  static String inventorySpoolKProfiles(int spoolId) =>
      '$apiPrefix/inventory/spools/$spoolId/k-profiles';

  /// Render spool labels as a PDF stream (`POST`, body
  /// `{spool_ids:[int], template:str, monochrome:bool}`). Response is the raw
  /// PDF, not JSON — fetch with `ResponseType.bytes`. Server caps the batch at
  /// 500 ids and 404s if any id is unknown.
  static const inventoryLabels = '$apiPrefix/inventory/labels';

  // Backend Spoolman (drop-in replacement — different data shape).
  static const spoolmanSpools = '$apiPrefix/spoolman/inventory/spools';
  static const spoolmanSpoolsBulk =
      '$apiPrefix/spoolman/inventory/spools/bulk';
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

  /// Spoolman counterpart of [inventoryLabels]. Note the path is NOT under
  /// `/spoolman/inventory/` — the label routes live at `/spoolman/labels`.
  static const spoolmanLabels = '$apiPrefix/spoolman/labels';

  // Filament catalog (definitions/profiles — `FilamentResponse[]`).
  static const filamentCatalog = '$apiPrefix/filament-catalog/';

  // --- Firmware ---

  /// Firmware for entire farm in one call (`FirmwareUpdatesResponse`:
  /// `{updates:[FirmwareUpdateInfo], updates_available:int}`).
  static const firmwareUpdates = '$apiPrefix/firmware/updates';

  /// Firmware for one printer (`FirmwareUpdateInfo`).
  static String firmwareUpdate(int printerId) =>
      '$apiPrefix/firmware/updates/$printerId';

  // Below for FUTURE — firmware update execution (not yet used in UI).

  /// Probe before firmware upload (`FirmwareUploadPrepareResponse`).
  static String firmwarePrepare(int printerId) =>
      '$apiPrefix/firmware/updates/$printerId/prepare';

  /// Start firmware upload (`FirmwareUploadStartResponse`). Query: `version`.
  /// Requires control permission on API key (missing → 403).
  static String firmwareUpload(int printerId) =>
      '$apiPrefix/firmware/updates/$printerId/upload';

  /// Firmware upload progress (`FirmwareUploadStatusResponse`).
  static String firmwareUploadStatus(int printerId) =>
      '$apiPrefix/firmware/updates/$printerId/upload/status';

  // --- File manager / library ---
  //
  // Print files (3mf/gcode/stl…) organized in folder tree. Auth via header
  // (X-API-Key / Bearer) — except thumbnail, which (like archive cover)
  // goes via `?token=` camera token.

  /// File list. Query (all optional): `folder_id` (null = root level when
  /// `include_root=true`), `project_id`, `include_root` (default true).
  /// Returns `FileListResponse[]`. Also `POST` — file upload
  /// (multipart, query `folder_id` + `generate_stl_thumbnails`).
  static const libraryFiles = '$apiPrefix/library/files';

  /// Single file: `GET` (details), `PUT` (edit `FileUpdate`:
  /// filename/folder_id/notes), `DELETE` (to trash).
  static String libraryFile(int fileId) => '$apiPrefix/library/files/$fileId';

  /// File thumbnail — authenticated via `?token=` (camera token), NOT
  /// header, similar to [archiveThumbnail].
  static String libraryFileThumbnail(int fileId) =>
      '$apiPrefix/library/files/$fileId/thumbnail';

  /// Move files to folder (`POST`, body `FileMoveRequest`:
  /// `{file_ids, folder_id}`; `folder_id=null` = root).
  static const libraryFilesMove = '$apiPrefix/library/files/move';

  /// Add files to queue (`POST`, body `AddToQueueRequest`:
  /// `{file_ids}`).
  static const libraryFilesAddToQueue = '$apiPrefix/library/files/add-to-queue';

  /// Bulk delete to trash (`POST`, body `BulkDeleteRequest`:
  /// `{file_ids, folder_ids}`).
  static const libraryBulkDelete = '$apiPrefix/library/bulk-delete';

  /// Folder tree (`FolderTreeItem[]`, nested via `children`).
  /// Also `POST` — create folder (`FolderCreate`: name/parent_id…).
  static const libraryFolders = '$apiPrefix/library/folders';

  /// Single folder: `PUT` (edit `FolderUpdate`: name/parent_id),
  /// `DELETE` (delete folder and contents).
  static String libraryFolder(int folderId) =>
      '$apiPrefix/library/folders/$folderId';

  /// Library statistics (file/folder count, size, free space).
  static const libraryStats = '$apiPrefix/library/stats';

  // --- Library trash ---

  /// Trash file list (`TrashListResponse`: items/total/retention_days).
  /// Also `DELETE` — empty trash (`EmptyTrashResponse`).
  static const libraryTrash = '$apiPrefix/library/trash';

  /// Restore file from trash (`POST`, no body).
  static String libraryTrashRestore(int fileId) =>
      '$apiPrefix/library/trash/$fileId/restore';

  /// Permanently delete file from trash (`DELETE`).
  static String libraryTrashItem(int fileId) =>
      '$apiPrefix/library/trash/$fileId';

  // --- MakerWorld + Bambu Cloud ---

  /// MakerWorld integration status (`GET`): `{has_cloud_token, can_download}`.
  /// `can_download=false` → missing/invalid Bambu cloud token, download
  /// unavailable (user must log in — see [cloudLogin]).
  static const makerworldStatus = '$apiPrefix/makerworld/status';

  /// Resolve any MakerWorld model URL (`POST`, body `{url}`)
  /// → `MakerWorldResolvedModel` (design + list of instances/plates).
  /// Does not require cloud token — works logged out too.
  static const makerworldResolve = '$apiPrefix/makerworld/resolve';

  /// Import (download) instance to library (`POST`, body
  /// `{model_id, profile_id?, folder_id?}`) → `MakerWorldImportResponse`.
  /// Requires valid Bambu cloud token (otherwise error).
  static const makerworldImport = '$apiPrefix/makerworld/import';

  /// Recent MakerWorld imports (`GET`, query `limit`).
  static const makerworldRecentImports =
      '$apiPrefix/makerworld/recent-imports';

  /// MakerWorld thumbnail proxy (`GET`, query `url=<cover URL>`). Public
  /// — no auth; used directly by `Image.network`.
  static const makerworldThumbnail = '$apiPrefix/makerworld/thumbnail';

  /// Bambu Cloud login status (`GET`): `{is_authenticated, email?, region?}`.
  static const cloudStatus = '$apiPrefix/cloud/status';

  /// Bambu Cloud login (`POST`, body `{email, password, region}`)
  /// → `CloudLoginResponse`. `needs_verification=true` → send code via
  /// [cloudVerify].
  static const cloudLogin = '$apiPrefix/cloud/login';

  /// Verify 2FA/OTP code (`POST`, body `{email, code, tfa_key?, region}`).
  static const cloudVerify = '$apiPrefix/cloud/verify';

  /// Bambu Cloud logout (`POST`, no body).
  static const cloudLogout = '$apiPrefix/cloud/logout';

  // --- Projects ---
  //
  // Group prints (archives + queue) toward a goal: stats, BOM, timeline,
  // attachments, cover image, templates and a parent/child hierarchy.

  /// List projects (`ProjectListResponse[]`). Query: `status` (optional).
  /// Also `POST` — create project (body `ProjectCreate`). Trailing slash
  /// required (FastAPI), similar to `/printers/`.
  static const projects = '$apiPrefix/projects/';

  /// Project templates (`ProjectListResponse[]`, `is_template=true`).
  static const projectsTemplates = '$apiPrefix/projects/templates';

  /// Create project from template (`POST`). Query `name` (new project name).
  static String projectFromTemplate(int templateId) =>
      '$apiPrefix/projects/from-template/$templateId';

  /// Import project from exported file (`POST`, multipart `{file}`).
  static const projectsImportFile = '$apiPrefix/projects/import/file';

  /// Single project: `GET` (full `ProjectResponse` incl. stats/children),
  /// `PATCH` (body `ProjectUpdate`), `DELETE`.
  static String project(int projectId) => '$apiPrefix/projects/$projectId';

  /// Turn a project into a reusable template (`POST`, no body).
  static String projectCreateTemplate(int projectId) =>
      '$apiPrefix/projects/$projectId/create-template';

  /// Export project as a downloadable archive (`GET`, byte stream).
  /// Query `format` (default `zip`).
  static String projectExport(int projectId) =>
      '$apiPrefix/projects/$projectId/export';

  /// Project archives (`GET`, query `limit`/`offset`).
  static String projectArchives(int projectId) =>
      '$apiPrefix/projects/$projectId/archives';

  /// Add archives to project (`POST`, body `{archive_ids:[]}`).
  static String projectAddArchives(int projectId) =>
      '$apiPrefix/projects/$projectId/add-archives';

  /// Remove archives from project (`POST`, body `{archive_ids:[]}`).
  static String projectRemoveArchives(int projectId) =>
      '$apiPrefix/projects/$projectId/remove-archives';

  /// Project queue items (`GET` → queue item list).
  static String projectQueue(int projectId) =>
      '$apiPrefix/projects/$projectId/queue';

  /// Add queue items to project (`POST`, body `{queue_item_ids:[]}`).
  static String projectAddQueue(int projectId) =>
      '$apiPrefix/projects/$projectId/add-queue';

  /// BOM items (`GET` → `BOMItemResponse[]`; `POST` create body `BOMItemCreate`).
  static String projectBom(int projectId) =>
      '$apiPrefix/projects/$projectId/bom';

  /// Single BOM item: `PATCH` (edit), `DELETE`.
  static String projectBomItem(int projectId, int itemId) =>
      '$apiPrefix/projects/$projectId/bom/$itemId';

  /// Project attachments (`POST` multipart `{file}` — upload).
  static String projectAttachments(int projectId) =>
      '$apiPrefix/projects/$projectId/attachments';

  /// Single attachment by filename: `GET` (download byte stream), `DELETE`.
  static String projectAttachment(int projectId, String filename) =>
      '$apiPrefix/projects/$projectId/attachments/$filename';

  /// Cover image: `POST` multipart `{file}` (upload), `GET` (image — auth via
  /// `?token=` camera token, NOT header), `DELETE`.
  static String projectCoverImage(int projectId) =>
      '$apiPrefix/projects/$projectId/cover-image';

  /// Project timeline (`GET` → `TimelineEvent[]`). Query `limit` (optional).
  static String projectTimeline(int projectId) =>
      '$apiPrefix/projects/$projectId/timeline';

  /// Library folders linked to a project (`GET` → `FolderTreeItem[]`).
  static String libraryFoldersByProject(int projectId) =>
      '$apiPrefix/library/folders/by-project/$projectId';

  // --- Users ---

  /// User list (`UserResponse[]`) — used only by the Stats "filter by user"
  /// picker. Gated server-side on `USERS_READ`/`stats:filter_by_user`; 403
  /// means this identity can't filter by user (caller hides the picker, not
  /// an error). Trailing slash required (FastAPI), similar to `/printers/`.
  static const users = '$apiPrefix/users/';
}
