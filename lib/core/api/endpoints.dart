/// All bambuddy API endpoints in one place.
///
/// Contract: bambuddy v0.2.4.9 … v1.2.5.1 (`/api/v1`) — every path below was
/// diffed across that range and none of them moved
/// (`docs/plans/08-server-v1.2.5-migration.md`). When updating the server,
/// compare with `/openapi.json` before changing anything here.
///
/// [usersSlim] is the one exception: it arrives in 1.2.6 and every server
/// before it refuses the path
/// (`docs/plans/13-users-slim-and-api-key-identity.md`). Callers probe rather
/// than check a version number — see [StatsRepository].
abstract final class Endpoints {
  static const apiPrefix = '/api/v1';

  static const authStatus = '$apiPrefix/auth/status';
  static const authLogin = '$apiPrefix/auth/login';

  /// The signed-in identity — `UserResponse` (role, `is_admin`, permissions,
  /// groups), the same object `POST /auth/login` embeds as `user`
  /// (`backend/app/api/routes/auth.py::login`). Without credentials it is a 401
  /// — a server with auth switched off has no identity to give.
  ///
  /// An `X-API-Key` session is answered differently by the two server
  /// generations, and both are still supported here:
  ///  - **≤ 1.2.5.x** — a synthetic admin: `id: 0`, `role: "admin"`,
  /// `is_admin: true`, every permission in the enum. None of it was true; a key
  /// is refused every administrative route whatever it claims.
  ///  - **1.2.6+** — the key owner's real `id` and `username`, `is_admin`
  /// always `false`, and a `permissions` list pinned to exactly what the route
  /// gate admits (`backend/app/api/routes/auth.py::_api_key_to_user_response`).
  /// `email` and `groups` are withheld on purpose. A key predating per-user
  /// ownership keeps `id: 0` and the `api-key:` username, but no longer claims
  /// admin.
  ///
  /// So `permissions` is the field to branch on, never `is_admin` or `role`
  /// (`docs/plans/13-users-slim-and-api-key-identity.md`).
  static const authMe = '$apiPrefix/auth/me';

  /// Second step of a login that answered `requires_2fa`: exchanges the
  /// pre-auth token plus a code (TOTP / e-mail OTP / backup) for the real JWT.
  static const authTwoFactorVerify = '$apiPrefix/auth/2fa/verify';

  /// Mails a 6-digit code to the user and answers with a **fresh** pre-auth
  /// token — the one sent in is consumed. See
  /// `docs/plans/10-two-factor-login.md`.
  static const authTwoFactorEmailSend = '$apiPrefix/auth/2fa/email/send';

  /// Server version (`{version, repo}`). **Unauthenticated** server-side, so it
  /// answers before login too. Read once per session to gate wire-format
  /// differences between server generations and to stamp the diagnostic log
  /// header — see `ServerVersionService`.
  static const updatesVersion = '$apiPrefix/updates/version';

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

  /// Start a subnet scan (`POST`, body `{subnet, timeout}`) →
  /// `SubnetScanStatus` `{running, scanned, total}`. Runs in the background;
  /// poll [discoveryScanStatus].
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

  /// Heater history (nozzle / bed / chamber) for one printer. Query
  /// `?hours=1..168` and `?kinds=` (comma-separated `nozzle,nozzle_2,bed,
  /// chamber`; all of them when omitted). Reference: bambuddy
  /// `printer_sensor_history.py`.
  static String printerSensorHistory(int printerId) =>
      '$apiPrefix/printer-sensor-history/$printerId';

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
  ///
  /// The whole bundle is built while the request is held open, so the reply
  /// arrives minutes later with no word in the meantime. [printerFilesJob] is
  /// the same work without the held socket, on servers that have it.
  static String printerFilesDownloadZip(int printerId) =>
      '$apiPrefix/printers/$printerId/files/download-zip';

  /// `POST {paths, sizes, filename, as_zip}` — start preparing a download on
  /// the server and answer at once with a job to poll (server #2850).
  ///
  /// 404 on an older server, which is what [printerFilesDownloadZip] stays for.
  static String printerFilesJob(int printerId) =>
      '$apiPrefix/printers/$printerId/files/download-job';

  /// `GET` one job's state, `DELETE` cancels it (and deletes what was already
  /// prepared). Note the plural, which the start route does not have.
  static String printerFilesJobStatus(int printerId, String jobId) =>
      '$apiPrefix/printers/$printerId/files/download-jobs/$jobId';

  /// The prepared bytes, addressed by the single-use token a `ready` job
  /// carries. **Unauthenticated by design** — the token is the authorisation,
  /// bound to this printer and consumed on first use (`create_slicer_download
  /// _token` / `verify_slicer_download_token`, five-minute TTL) — and the
  /// server deletes the staged file once it has been served, so there is no
  /// second attempt: a transfer that breaks needs a new job.
  ///
  /// [filename] only names the download for the client; the server sanitises
  /// it and it does not select the file.
  static String printerFilesPrepared(
    int printerId,
    String token,
    String filename,
  ) =>
      '$apiPrefix/printers/$printerId/files/dl/'
      '${Uri.encodeComponent(token)}/${Uri.encodeComponent(filename)}';

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

  /// Clear the printer's active error dialog (`clean_print_error`) — one call
  /// per printer, not per error. Empty body. 400 when it is not connected.
  static String hmsClear(int printerId) =>
      '$apiPrefix/printers/$printerId/hms/clear';

  /// Run one of the firmware's remediation actions for a fault. JSON body
  /// `{print_error, action, job_id}` — see [PrinterCommandsRepository].
  /// The server waits ~2.5s for the printer to acknowledge and answers 502 if
  /// it stays silent, so this call is slower than every other control route.
  static String hmsExecuteAction(int printerId) =>
      '$apiPrefix/printers/$printerId/hms/execute-action';

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

  /// Chamber target temperature. Query: `target` 0 = off, up to the server's
  /// own `MAX_CHAMBER_TEMP_C` — **60 up to 1.2.5.x, 65 from 1.2.6** (commit
  /// `b04664c6`). The bound is a `Query(le=…)`, so an older server answers 422
  /// rather than clamping; gate on [ServerVersion.chamberMaxTargetC]. Returns
  /// 400 unless the model has an active chamber heater (H2C/H2D/H2D
  /// Pro/H2S/X2D) — gate client-side via `supportsChamberHeater` before
  /// calling.
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

  /// Drying runs the server will start later. `GET` lists the `pending` /
  /// `running` / `failed` rows (optional `printer_id` filter), `POST` schedules
  /// one. 404 on servers before the route shipped — see
  /// [ServerFeature.scheduledDryings].
  static const scheduledDryings = '$apiPrefix/scheduled-dryings';

  /// Cancel a pending or running scheduled drying run, or dismiss a failed one
  /// — the same `DELETE` does both.
  static String scheduledDrying(int id) => '$scheduledDryings/$id';

  // --- Movement / jog (manual control; idle only) --- All POST, empty body,
  // params in query. Relative moves; the server maps the Z sign per model (A1
  // bed-slingers are inverted). Require `can_control_printer`.

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

  // --- AMS filament handling ---

  /// Ask the printer to republish its whole state (`pushall`). Unlike every
  /// other route in this block it needs read permission only, so a key that
  /// cannot control the printer may still call it. Answers 400 when the printer
  /// is not connected.
  static String printerRefreshStatus(int printerId) =>
      '$apiPrefix/printers/$printerId/refresh-status';

  /// Load filament into the extruder. Query: `tray_id`, the **global** tray
  /// number — `ams_id * 4 + slot` for a regular AMS (0..15, and 24..27 once the
  /// A2L AMS-Lite is normalised to unit 6), 254 external / Ext-L, 255 Ext-R.
  /// The server rejects everything else with 400, AMS-HT (unit 128+) included —
  /// build the number with `amsLoadTrayId`, which answers null for those.
  ///
  /// Optional `extruder_id` (0 = right/main, 1 = left/deputy) names the hotend
  /// to feed. Only a printer with a Filament Track Switch needs it — see
  /// `PrinterStatus.filaSwitch`. A server too old to know the parameter ignores
  /// it, which is the same answer as not having the accessory.
  static String amsLoad(int printerId) =>
      '$apiPrefix/printers/$printerId/ams/load';

  /// Unload filament. Optional `tray_id` — the same global encoding [amsLoad]
  /// takes — names the slot, and through it the hotend fed from that slot: a
  /// dual-nozzle printer has one `tray_now` for two loaded hotends, so an
  /// unaddressed unload picks whichever of them that field happens to name.
  /// Omitted, the server keeps that older behaviour, which is all a
  /// single-nozzle printer ever needs; a server too old to know the parameter
  /// ignores it and does the same.
  ///
  /// Answers 409 when no hotend is fed from the named slot — a per-slot menu
  /// offers the action on every slot, and most of them are not loaded.
  static String amsUnload(int printerId) =>
      '$apiPrefix/printers/$printerId/ams/unload';

  /// Re-read one AMS slot's RFID tag. Path ids are **local** (unit id, slot
  /// within the unit) — not the global number [amsLoad] takes. Gated on
  /// `printers:ams_rfid`, a permission of its own: a key allowed to control the
  /// printer can still be refused here.
  static String amsSlotRfidRefresh(int printerId, int amsId, int slotId) =>
      '$apiPrefix/printers/$printerId/ams/$amsId/slot/$slotId/refresh';

  // --- AMS slot configuration ---
  //
  // Ids here are **local** throughout (unit id + slot within the unit), unlike
  // [amsLoad]. The external spool is unit 255 with slot 0 (Ext-L) or 1 (Ext-R):
  // the server adds 254 itself when it looks the slot up in `vt_tray`.

  /// Write a filament configuration into one slot (`POST`). The server computes
  /// nothing — all 12 query parameters (`tray_info_idx`, `tray_type`,
  /// `tray_sub_brands`, `tray_color`, `nozzle_temp_min`, `nozzle_temp_max`,
  /// `cali_idx`, `nozzle_diameter`, `setting_id`, `kprofile_filament_id`,
  /// `kprofile_setting_id`, `k_value`) are the caller's to derive, which is what
  /// `AmsSlotConfiguration` exists for. Needs `printers:control`, and answers
  /// 400 for a printer that is not connected.
  static String amsSlotConfigure(int printerId, int amsId, int trayId) =>
      '$apiPrefix/printers/$printerId/slots/$amsId/$trayId/configure';

  /// Clear a slot's filament configuration (`POST`). Also deletes the saved
  /// [amsSlotPreset] mapping, so the two undo each other.
  static String amsSlotReset(int printerId, int amsId, int trayId) =>
      '$apiPrefix/printers/$printerId/ams/$amsId/tray/$trayId/reset';

  /// Which preset a slot was configured with (`GET` → the mapping or `null`,
  /// `PUT` with query `preset_id`/`preset_name`/`preset_source` to save it).
  /// The printer itself only keeps a filament id, and a user cloud preset's id
  /// resolves to no name anywhere — this mapping is the only way to show back
  /// what was picked.
  static String amsSlotPreset(int printerId, int amsId, int trayId) =>
      '$apiPrefix/printers/$printerId/slot-presets/$amsId/$trayId';

  /// Pressure-advance profiles stored on the printer (`GET`, query
  /// `nozzle_diameter`). The trailing slash is the route's own, and the printer
  /// has to be connected — the server asks it over MQTT and answers 400
  /// otherwise. Gated on `kprofiles:read`, which an API key that can read
  /// status already has.
  static String printerKProfiles(int printerId) =>
      '$apiPrefix/printers/$printerId/kprofiles/';

  /// Every saved slot→preset mapping for a printer (`GET`), keyed by the
  /// *global* tray number (AMS-HT by unit id). One request for a whole card.
  static String amsSlotPresets(int printerId) =>
      '$apiPrefix/printers/$printerId/slot-presets';

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
  /// render used for the skip-objects overlay. Auth via `?token=` (camera
  /// stream token), NOT via header — same as [PrinterStatus.coverUrl].
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

  /// Whether any print in the last 30 days archived without its 3MF, and why
  /// (`{has_fallback, reason}`). Stateless — dismissal is the client's business.
  ///
  /// `reason` is `internal_storage`, `no_external_storage`, or absent; the
  /// slugs are contract (`print_storage.py`), and an older server answers the
  /// same route with `has_fallback` alone. Absent means the original cause,
  /// the slicer's "Store sent files on external storage" being off, which is
  /// what the single-cause wording used to claim unconditionally.
  static const archivesNo3mfWarning = '$apiPrefix/archives/no-3mf-warning';

  /// Thumbnail authenticated via `?token=` (camera token), NOT via header
  /// — see cover in printer_card.
  static String archiveThumbnail(int archiveId) =>
      '$apiPrefix/archives/$archiveId/thumbnail';

  /// The archive's timelapse video, authenticated via `?token=` (camera token)
  /// like [archiveThumbnail] — `archives.py::get_timelapse` takes the camera
  /// stream token, not the auth header. 404 while the print has no video yet.
  ///
  /// Container is whatever the printer produced: MP4 from most models, AVI from
  /// a P1S until the server's background conversion catches up.
  static String archiveTimelapse(int archiveId) =>
      '$apiPrefix/archives/$archiveId/timelapse';

  /// One photo attached to the archive, authenticated via `?token=` (camera
  /// token) like [archiveThumbnail]. [filename] comes from `Archive.photos` —
  /// `archives.py::get_photo` serves nothing that is not on that list.
  static String archivePhoto(int archiveId, String filename) {
    final name = Uri.encodeComponent(filename);
    return '$apiPrefix/archives/$archiveId/photos/$name';
  }

  /// Timelapse metadata read with ffprobe server-side — `{duration, width,
  /// height, fps, codec, file_size, has_audio}`. Unlike the video itself this
  /// one takes the ordinary auth header.
  static String archiveTimelapseInfo(int archiveId) =>
      '$apiPrefix/archives/$archiveId/timelapse/info';

  /// Evenly spaced frames for the editor's filmstrip — `{thumbnails: [base64
  /// JPEG], timestamps: [seconds]}`. Query `count` (1..30) and `width`
  /// (80..320); the server renders them with ffmpeg per request.
  static String archiveTimelapseThumbnails(int archiveId) =>
      '$apiPrefix/archives/$archiveId/timelapse/thumbnails';

  /// Trim/speed/audio re-encode of the timelapse (`POST`, multipart:
  /// `trim_start`, `trim_end`, `speed` 0.25–4.0, `save_mode`,
  /// `output_filename`, `audio`) → `{status, output_path, message}`.
  ///
  /// Runs ffmpeg inline and answers only when it is done, so this one needs a
  /// timeout measured in minutes rather than the client default. `save_mode`
  /// `replace` overwrites the recording; `new` writes a file alongside it that
  /// nothing then points at — which is why the web UI only ever sends
  /// `replace`.
  static String archiveTimelapseProcess(int archiveId) =>
      '$apiPrefix/archives/$archiveId/timelapse/process';

  /// The archive's G-code as `text/plain`, unzipped from its 3MF
  /// (`archives.py::get_gcode`). Query `plate=N` picks `Metadata/plate_N.gcode`.
  ///
  /// **Always send the plate for a multi-plate file.** Without it the answer
  /// depends on the server: newer ones pick the lowest-numbered plate, older
  /// ones the zip's first member — which is whatever order the slicer happened
  /// to write, so the same file could preview as a different plate on two
  /// servers. `Archive.plateId` / `QueueItem.plateId` is the plate the run
  /// belongs to and the one to ask for.
  ///
  /// Older than either embedded viewer the server has had, and untouched by the
  /// one it deleted — which is what makes it safe to draw the preview from.
  static String archiveGcode(int archiveId) =>
      '$apiPrefix/archives/$archiveId/gcode';

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

  /// See [libraryFilePlates]. The archive twin answers two keys the library one
  /// does not: `has_gcode` and a per-plate `bed_type`.
  ///
  /// Each plate row carries its own `thumbnail_url` for
  /// `…/plate-thumbnail/{index}`, authenticated via `?token=` (camera token)
  /// like [archiveThumbnail], and null when the 3MF has no render for that
  /// plate. That path is read from the row rather than rebuilt here: the archive
  /// and library routes spell it differently and the row knows which one it came
  /// from.
  static String archivePlates(int archiveId) =>
      '$apiPrefix/archives/$archiveId/plates';


  // --- Print log (one row per run, in its own table) ---

  /// Print log list (`GET`) → `{items: PrintLogEntry[], total}`. Query:
  /// `search` (print name), `printer_id`, `status`, `created_by_username`,
  /// `date_from`/`date_to` (instants, matched against `created_at`), `limit`
  /// (**capped at 500**), `offset`, plus `sort_by`/`sort_dir` on 1.2.6+.
  ///
  /// Trailing slash required, like [archives].
  ///
  /// There is no `archive_id` filter — the runs of one archive cannot be
  /// fetched here (`print_log.py::get_print_log`).
  ///
  /// `DELETE` on the same path clears the **whole** log, every user's rows,
  /// and answers `{deleted}`. It ignores every filter above.
  static const printLog = '$apiPrefix/print-log/';

  /// One log entry. `PATCH` re-classifies it (`{failure_reason, status}` →
  /// updated entry), `DELETE` removes that row alone and leaves the archive it
  /// points at untouched. Both arrived in server 0.2.4.6; older servers 405.
  static String printLogEntry(int entryId) => '$apiPrefix/print-log/$entryId';

  /// Thumbnail authenticated via `?token=` (camera token), NOT via header —
  /// same as [archiveThumbnail]. 404 once the file behind it is gone, which
  /// also clears `thumbnail_path` on the entry server-side.
  static String printLogThumbnail(int entryId) =>
      '$apiPrefix/print-log/$entryId/thumbnail';

  // --- Slicer (server-side slicing via sidecar; gated by use_slicer_api) ---

  /// Enqueue a slice job for a library file (`POST`, body `SliceRequest`).
  /// Returns `202 {job_id}`; poll [sliceJob].
  static String libraryFileSlice(int fileId) =>
      '$apiPrefix/library/files/$fileId/slice';

  /// Per-filament requirements parsed from a library file's 3MF. See
  /// [archiveFilamentRequirements].
  static String libraryFileFilamentRequirements(int fileId) =>
      '$apiPrefix/library/files/$fileId/filament-requirements';

  /// Plates in a library file's 3MF, plus `embedded_printer` /
  /// `embedded_process` / `design_overrides`. Read for the "slice as designed"
  /// gate rather than for the plates — see `EmbeddedSettings`.
  static String libraryFilePlates(int fileId) =>
      '$apiPrefix/library/files/$fileId/plates';

  /// Poll a slice job (`GET`) → status/progress/result. See [archiveSlice].
  static String sliceJob(int jobId) => '$apiPrefix/slice-jobs/$jobId';

  /// Unified preset list across local/cloud/standard tiers for the slice modal
  /// (`GET`, query `refresh`). Returns `UnifiedPresetsResponse`.
  static const slicerPresets = '$apiPrefix/slicer/presets';

  /// Effective values of one process preset with its `inherits:` chain
  /// flattened (`GET`, query `source` = tier, `id`, `slot` — only `process` is
  /// supported and 400s otherwise). Lets the process-override fields start from
  /// what the preset actually contains: a preset setting a 0.42 mm line width
  /// would otherwise show the compiled-in default of 0.
  ///
  /// Answers `{resolved, values, reason}` and **never errors on a resolution
  /// failure** — `resolved: false` with a `reason` (`sidecar_unavailable`,
  /// `not_configured`, `preset_unresolved`, …) is the normal negative answer,
  /// and the panel stays usable with blank fields. A sidecar older than the
  /// endpoint is the common cause, which is why the reason is worth showing.
  ///
  /// **1.2.6+ only** — an older server 404s, and that (not `resolved: false`)
  /// is what [SlicerRepository] reads as "not supported here".
  static const slicerPresetValues = '$apiPrefix/slicer/preset-values';

  /// Server-wide app settings (`AppSettings`). We only read `use_slicer_api`
  /// here to gate the slice UI; full settings management lives on the web.
  static const appSettings = '$apiPrefix/settings';

  // --- Smart plugs (M7) ---

  /// List of all smart plugs (SmartPlugResponse[]). Each entry carries
  /// `printer_id` — from this, map plug↔printer without N queries.
  /// Trailing slash required (FastAPI), similar to `/printers/`.
  static const smartPlugs = '$apiPrefix/smart-plugs/';

  /// Live smart plug status (SmartPlugStatus): on/off state + power/energy
  /// measurement.
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
  /// (unassign a custom type from the printer). Requires update/delete
  /// permission.
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

  // --- Bulk operations on a selection (server 0.2.5b1 and newer) ---
  //
  // All `POST`, all take `{ids: [int]}` — capped at 500 server-side, so the
  // client chunks — except [inventorySpoolsResetConsumedCounterBulk], whose key
  // is `spool_ids`. An unknown id is reported in the response body, never as a
  // 404, so a 404 here means one thing only: the server predates the routes.
  // Response shapes differ per backend and are normalized in `BulkOutcome`.

  /// Apply one partial `SpoolUpdate` to every listed spool. Body
  /// `{ids: [int], update: {…}}`, response `{updated, not_found}`.
  static const inventorySpoolsBulkUpdate =
      '$apiPrefix/inventory/spools/bulk-update';

  /// Response `{deleted, not_found}`.
  static const inventorySpoolsBulkDelete =
      '$apiPrefix/inventory/spools/bulk-delete';

  /// Response `{archived, already_archived, not_found}`.
  static const inventorySpoolsBulkArchive =
      '$apiPrefix/inventory/spools/bulk-archive';

  /// Response `{restored, already_active, not_found}`.
  static const inventorySpoolsBulkRestore =
      '$apiPrefix/inventory/spools/bulk-restore';

  /// Body `{spool_ids: [int]}` (not `ids`), response `{reset}` — the count of
  /// spools the server found, so it cannot report a partial failure.
  static const inventorySpoolsResetConsumedCounterBulk =
      '$apiPrefix/inventory/spools/reset-consumed-counter-bulk';

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

  /// Reset the "Total Consumed" counter (`POST`, no body). Stamps
  /// `weight_used_baseline = weight_used`, so remaining is preserved and
  /// `weight_locked` is left alone — the spool keeps taking AMS auto-sync.
  static String inventorySpoolResetConsumedCounter(int spoolId) =>
      '$apiPrefix/inventory/spools/$spoolId/reset-consumed-counter';

  /// The pre-0.2.5 name of [inventorySpoolResetConsumedCounter], kept for
  /// servers older than the rename (issue #1644). Try the current path first
  /// and fall back here on 404 — the two never coexist.
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

  /// Create a spool from what an AMS slot currently holds and assign it there
  /// in the same call (`POST`, body `{printer_id, ams_id, tray_id}`, response
  /// `SpoolResponse`). Server-side the slot must hold a readable RFID tag —
  /// without one there is no stable identity and every confirm would make a
  /// duplicate, so it answers 400.
  static const inventorySpoolFromSlot =
      '$apiPrefix/inventory/spools/from-slot';

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
  static String spoolmanSpoolResetConsumedCounter(int spoolId) =>
      '$apiPrefix/spoolman/inventory/spools/$spoolId/reset-consumed-counter';

  /// Pre-rename twin of [spoolmanSpoolResetConsumedCounter] — see
  /// [inventorySpoolResetUsage].
  static String spoolmanSpoolResetUsage(int spoolId) =>
      '$apiPrefix/spoolman/inventory/spools/$spoolId/reset-usage';

  /// Spoolman twins of the native bulk routes. Same request bodies; the
  /// responses report per-spool failures as `{errors: [{id, status, detail}]}`
  /// instead of native's `not_found` / `already_*` lists, because the backend
  /// loops the per-spool proxy calls rather than one SQL statement.
  static const spoolmanSpoolsBulkUpdate =
      '$apiPrefix/spoolman/inventory/spools/bulk-update';
  static const spoolmanSpoolsBulkDelete =
      '$apiPrefix/spoolman/inventory/spools/bulk-delete';
  static const spoolmanSpoolsBulkArchive =
      '$apiPrefix/spoolman/inventory/spools/bulk-archive';
  static const spoolmanSpoolsBulkRestore =
      '$apiPrefix/spoolman/inventory/spools/bulk-restore';
  static const spoolmanSpoolsResetConsumedCounterBulk =
      '$apiPrefix/spoolman/inventory/spools/reset-consumed-counter-bulk';
  static const spoolmanAssignments =
      '$apiPrefix/spoolman/inventory/slot-assignments/all';

  /// Spoolman counterpart of [inventorySpoolFromSlot]. Like [spoolmanLabels]
  /// it does NOT live under `/spoolman/inventory/`, and unlike every other
  /// inventory write it is gated on `filaments:update`, which no API key may
  /// hold — a key-authenticated session gets 403 here whatever its scopes.
  static const spoolmanSpoolFromSlot =
      '$apiPrefix/spoolman/spools/from-slot';

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

  /// The file's G-code as `text/plain`: a `.gcode` served as it is, a
  /// `.gcode.3mf` unzipped first (`library.py::get_gcode`).
  ///
  /// Takes no plate: the server returns the **first** `.gcode` in the archive
  /// whatever is asked, so a multi-plate sliced file always previews plate 1.
  static String libraryFileGcode(int fileId) =>
      '$apiPrefix/library/files/$fileId/gcode';

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

  // --- Library tags ---

  /// Tag catalog (`TagResponse[]`, alphabetical, with `file_count`).
  /// Also `POST` — create tag (`TagCreate`: name); `409` on a
  /// case-insensitive duplicate.
  static const libraryTags = '$apiPrefix/library/tags';

  /// Single tag: `PATCH` (rename `TagUpdate`: name, `409` on duplicate),
  /// `DELETE` (drops the tag; files themselves are untouched).
  static String libraryTag(int tagId) => '$apiPrefix/library/tags/$tagId';

  /// Add / remove / replace tags across files (`POST`, body
  /// `{file_ids, tag_ids, action}` → `TagBulkAssignResponse`).
  static const libraryTagsBulkAssign =
      '$apiPrefix/library/tags/bulk-assign';

  // --- Library variant groups (server #671) ---
  //
  // The same job sliced for different printer models, grouped so a queue item
  // can offer them as alternatives and take whichever printer frees up first.
  // **1.2.6+ only** — every path here 404s on an older server.

  /// Create a group (`POST`, body `{members:[{library_file_id, target_model?}],
  /// name?}` → `VariantGroupResponse`). Minimum two members: a group of one
  /// expresses no choice and is refused. Member order is the priority order.
  ///
  /// `target_model` is normally omitted and read from the file's own
  /// `sliced_for_model`; send it only for a legacy 3MF that declares none.
  static const libraryVariantGroups = '$apiPrefix/library/variant-groups';

  /// One group: `GET` (with members), `PATCH` (body `{name?,
  /// member_file_ids?}` — a partial `member_file_ids` is rejected rather than
  /// guessing, so send the full current membership), `DELETE` (ungroups; the
  /// files themselves are untouched).
  static String libraryVariantGroup(int groupId) =>
      '$apiPrefix/library/variant-groups/$groupId';

  /// The group a file belongs to (`GET`) → `VariantGroupResponse`. 404 when the
  /// file is in none, which is the ordinary case and not an error.
  static String libraryVariantGroupByFile(int fileId) =>
      '$apiPrefix/library/variant-groups/by-file/$fileId';

  /// Add a member (`POST`, body `{library_file_id, target_model?}`).
  static String libraryVariantGroupMembers(int groupId) =>
      '$apiPrefix/library/variant-groups/$groupId/members';

  /// Remove one member (`DELETE`, 204). Removing the second-to-last member
  /// **dissolves the whole group** server-side
  /// (`library_variants.py::_dissolve_if_too_small`) — a one-member group is
  /// not a choice. So the caller must refresh the other file's state too, not
  /// just this one's.
  static String libraryVariantGroupMember(int groupId, int fileId) =>
      '$apiPrefix/library/variant-groups/$groupId/members/$fileId';

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

  /// Slicer presets stored in the user's Bambu Cloud account (`GET`) —
  /// `{filament: [...], printer: [...], process: [...]}`, each entry a
  /// `SlicerSetting` with `setting_id`/`name`/`is_custom`. **401 when no cloud
  /// login exists**, which is a normal answer here: the filament picker falls
  /// back to [cloudBuiltinFilaments] plus the local presets.
  static const cloudSettings = '$apiPrefix/cloud/settings';

  /// One cloud preset in full (`GET`). Read for a custom preset's own
  /// `filament_id`, which is what the printer needs and what the id in the list
  /// is not. Never substitute the response's `base_id`: that is the generic the
  /// preset inherits from, and using it makes the slicer resolve the slot back
  /// to "Generic …" (bambuddy #1053).
  static String cloudSettingDetail(String settingId) =>
      '$apiPrefix/cloud/settings/$settingId';

  /// Bambu's built-in filament table (`GET`) — `[{filament_id, name}]`. Static
  /// and needs no cloud login (only `filaments:read`), which makes it the floor
  /// the filament picker always has.
  static const cloudBuiltinFilaments = '$apiPrefix/cloud/builtin-filaments';

  /// Presets imported from a slicer bundle (`GET`) — same grouping as
  /// [cloudSettings], entries carry `filament_type`, `nozzle_temp_min/max` and
  /// a JSON-encoded `compatible_printers` string. Gated on `settings:read`, so
  /// a narrow key can be refused this tier while still having the other two.
  static const localPresets = '$apiPrefix/local-presets/';

  /// Bambu's model registry (`GET`) — `{"Bambu Lab X1 Carbon": "X1C", …}`.
  /// Static reference data, no auth. Maps the long names that appear inside
  /// preset names to the short codes `Printer.model` uses.
  static const slicerPrinterModels = '$apiPrefix/slicer/printer-models';

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

  /// Finished-run count per library file (`GET`, `ProjectFileProgress[]`).
  /// Server ≥ 1.2.5.2 — older ones answer 404, which the repository turns into
  /// an empty list rather than an error.
  static String projectFileProgress(int projectId) =>
      '$apiPrefix/projects/$projectId/file-progress';

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

  /// BOM items (`GET` → `BOMItemResponse[]`; `POST` create body
  /// `BOMItemCreate`).
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

  /// User list (`UserResponse[]`) — the administration user list, and the
  /// fallback behind [usersSlim] for the Stats "filter by user" picker. Gated
  /// server-side on `USERS_READ` only
  /// (`backend/app/api/routes/users.py::_user_to_response`), so a custom group
  /// without the admin role reaches it, but an API key never does: `users:read`
  /// is unmapped in the key scope allowlist, which makes it administrative.
  /// Ordered by `created_at`. Trailing slash required (FastAPI), like
  /// `/printers/`.
  static const users = '$apiPrefix/users/';

  /// Id → name only (`[{id, username}]` —
  /// `backend/app/schemas/auth.py::UserSlim`), so the `created_by_id` values
  /// that come back from archives, the queue and statistics can be shown as
  /// names. Ordered by `username`. **1.2.6+ only.**
  ///
  /// Reachable where [users] is not: gated on `users:read_slim` *or*
  /// `users:read` (any-of), and the slim permission is mapped to the API-key
  /// `can_read_status` scope
  /// (`backend/app/core/auth.py::_APIKEY_SCOPE_BY_PERMISSION`) — so a key
  /// reads this and not the full listing, which is the whole point of server
  /// issue #1894.
  ///
  /// **An older server cannot answer this successfully**, so support is probed
  /// rather than derived from a version number (that numbering is a trap —
  /// `docs/plans/08-server-v1.2.5-migration.md`). `/{user_id}` is declared
  /// `int` there, so the path yields **422** for a caller that would otherwise
  /// pass, and **403** for one refused before the path is even parsed. Never a
  /// 404 — treat any non-200 as "not supported here" and fall back to [users].
  ///
  /// No trailing slash: `slim` is a literal segment, not a collection.
  static const usersSlim = '$apiPrefix/users/slim';

  /// What this account owns (`{archives, queue_items, library_files}` —
  /// `backend/app/api/routes/users.py::update_user`). Read-only, `USERS_READ`;
  /// answers what a later edit or deletion would be touching.
  static String userItemsCount(int userId) =>
      '$apiPrefix/users/$userId/items-count';

  /// One account: `PATCH` (edit, `users.py::list_users_slim`) and `DELETE`
  /// (`users.py::get_user_items_count`, query `delete_items=true|false` — see
  /// [UsersRepository.delete]). Both are admin-only *and* permission-gated; API
  /// keys are refused outright.
  static String userById(int userId) => '$apiPrefix/users/$userId';

  /// Whether the server generates and mails the password instead of the admin
  /// setting one (`{advanced_auth_enabled, smtp_configured, ...}` —
  /// `backend/app/api/routes/auth.py::disable_advanced_auth`). Unauthenticated
  /// server-side, and what decides the shape of the account form.
  static const advancedAuthStatus = '$apiPrefix/auth/advanced-auth/status';

  // --- API keys ---

  /// Key list (`GET`, `APIKeyResponse[]` — never the keys themselves) and
  /// creation (`POST`, whose answer carries the full key **once**;
  /// `backend/app/api/routes/api_keys.py::create_api_key`). Gated on
  /// `api_keys:read` / `api_keys:create` — no admin role on top, unlike users
  /// and groups.
  static const apiKeys = '$apiPrefix/api-keys/';

  /// One key: `PATCH` (rename, scopes, enable/disable, expiry) and `DELETE`
  /// (revoke — the key stops working immediately).
  static String apiKeyById(int keyId) => '$apiPrefix/api-keys/$keyId';

  // --- Groups ---

  /// Group list (`GroupResponse[]` —
  /// `backend/app/api/routes/groups.py::list_permissions`), gated on
  /// `groups:read`. Trailing slash required, like `/users/`.
  static const groups = '$apiPrefix/groups/';

  /// Every permission the server knows, by category (`PermissionsListResponse`,
  /// `groups.py::_permission_label`). Gated on `groups:read` — the same key
  /// that opens the group screens.
  static const groupPermissions = '$apiPrefix/groups/permissions';

  /// One group with its member list (`GroupDetailResponse`,
  /// `groups.py::create_group`). `PATCH` and `DELETE` on the same path are
  /// admin-only and refuse system groups.
  static String groupById(int groupId) => '$apiPrefix/groups/$groupId';

  /// Membership from the group's side: `POST` adds, `DELETE` removes
  /// (`groups.py::delete_group`, `:297`). Admin-only on top of `groups:update`,
  /// and both answer 204 with no body.
  static String groupMember(int groupId, int userId) =>
      '$apiPrefix/groups/$groupId/users/$userId';
}
