import 'dart:typed_data';

import 'package:app_util/app_util.dart';
import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/content_disposition.dart';
import '../core/api/dio_json.dart';
import '../core/api/endpoints.dart';
import '../core/api/observed_capability.dart';
import '../core/api/server_version.dart';
import '../core/api/server_version_service.dart';
import '../core/models/maintenance.dart';

/// REST data source for printer maintenance (M7): status overview per printer,
/// mark task as done (reset counter), and history.
///
/// Auth adds `AuthInterceptor` to the shared Dio. List parsing is defensive
/// (skip bad entries), and [fetchPrinter] degrades to `null` on non-auth errors —
/// a single unreachable printer won't break post-print reminders.
class MaintenanceRepository {
  MaintenanceRepository(this._dio, [this._serverVersion]);

  final Dio _dio;

  /// Without one (the background isolates never read the log) the version
  /// reads as unknown, which is "no".
  final ServerVersionService? _serverVersion;

  /// Whether the server keeps the log of resets (#3557). Never observed: the
  /// app asks for nothing until this says yes.
  late final logCapability = ObservedCapability(
    ServerFeature.maintenanceLog,
    _serverVersion,
  );

  /// `GET /maintenance/overview` — all active printers. Skip unparseable entries.
  Future<List<PrinterMaintenanceOverview>> fetchOverview() async {
    return guard(
      () => _dio.getList(
        Endpoints.maintenanceOverview,
        PrinterMaintenanceOverview.fromJson,
      ),
    );
  }

  /// `GET /maintenance/printers/{id}` — one printer. Auth errors bubble up
  /// (UI → /setup); other errors degrade to `null`.
  Future<PrinterMaintenanceOverview?> fetchPrinter(int printerId) =>
      guardOrNull(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          Endpoints.maintenancePrinter(printerId),
        );
        final data = res.data;
        return data == null ? null : PrinterMaintenanceOverview.fromJson(data);
      });

  /// `POST /maintenance/items/{id}/perform` — reset counter. Body `{"notes": notes}`.
  /// 403 (no permission) → [AuthException(forbidden)].
  Future<void> perform(int itemId, {String? notes}) => guard(
    () => _dio.post<dynamic>(
      Endpoints.maintenancePerform(itemId),
      data: {'notes': notes},
    ),
  );

  // --- The log of resets (server 1.3.2) ---

  /// `GET /maintenance/printers/{id}/log` — one page of a printer's log, newest
  /// first. A row that does not parse is dropped, and [MaintenanceLogPage.total]
  /// is the server's count, so a page can hold fewer than it says;
  /// [MaintenanceLogPage.received] counts the rows the server sent.
  Future<MaintenanceLogPage> fetchLog(
    int printerId, {
    int limit = logPageSize,
    int offset = 0,
  }) => guard(() async {
    assert(limit >= 1 && limit <= 500, 'the route takes 1..500: $limit');
    final res = await _dio.get<dynamic>(
      Endpoints.maintenancePrinterLog(printerId),
      queryParameters: {'limit': limit, 'offset': offset},
    );
    final data = res.data;
    if (data is! Map) {
      throw ApiException(
        AppErrorCode.badResponse,
        statusCode: res.statusCode,
        method: 'GET',
        path: Endpoints.maintenancePrinterLog(printerId),
      );
    }
    final items = parseJsonList(data['items'], MaintenanceLogEntry.fromJson);
    final raw = data['items'];
    return (
      items: items,
      total: toIntOrNull(data['total']) ?? items.length,
      received: raw is List ? raw.length : 0,
    );
  });

  /// The route's own default and the page the screen asks for.
  static const logPageSize = 50;

  /// `GET …/log/export` — the log as CSV: of [printerId], or of every printer
  /// the caller may see when it is null. [filename] is the server's, from
  /// `Content-Disposition`, or a plain `maintenance-log.csv`.
  Future<({Uint8List bytes, String filename})> exportLog({int? printerId}) =>
      guard(() async {
        final res = await _dio.get<List<int>>(
          printerId == null
              ? Endpoints.maintenanceLogExport
              : Endpoints.maintenancePrinterLogExport(printerId),
          options: Options(responseType: ResponseType.bytes),
        );
        return (
          bytes: Uint8List.fromList(res.data ?? const []),
          filename:
              contentDispositionFilename(
                res.headers.value('content-disposition'),
              ) ??
              'maintenance-log.csv',
        );
      });

  /// `DELETE …/log?older_than_days=` — drops the entries older than that many
  /// days (1..36500; the route keeps at least the last day), of [printerId] or
  /// of every printer the caller may see. Answers how many went.
  Future<int> cleanUpLog({required int olderThanDays, int? printerId}) =>
      guard(() async {
        assert(
          olderThanDays >= 1 && olderThanDays <= 36500,
          'the route takes 1..36500: $olderThanDays',
        );
        final res = await _dio.delete<dynamic>(
          printerId == null
              ? Endpoints.maintenanceLog
              : Endpoints.maintenancePrinterLog(printerId),
          queryParameters: {'older_than_days': olderThanDays},
        );
        final data = res.data;
        return data is Map ? toIntOrNull(data['deleted']) ?? 0 : 0;
      });

  /// `DELETE /maintenance/log/{id}` — one entry, e.g. of a task reset by
  /// mistake. The task's last reset stays: this does not undo it.
  Future<void> deleteLogEntry(int entryId) =>
      guard(() => _dio.delete<dynamic>(Endpoints.maintenanceLogEntry(entryId)));

  // --- Type management (Settings tab) ---

  /// `GET /maintenance/types` — full catalog (system + custom, non-deleted).
  Future<List<MaintenanceType>> fetchTypes() async {
    return guard(
      () => _dio.getList(Endpoints.maintenanceTypes, MaintenanceType.fromJson),
    );
  }

  /// `POST /maintenance/types` — create a custom type. Returns it (with new id).
  Future<MaintenanceType> createType(MaintenanceTypeDraft draft) =>
      guard(() async {
        return _dio.postObject(
          Endpoints.maintenanceTypes,
          MaintenanceType.fromJson,
          data: draft.toJson(),
        );
      });

  /// `PATCH /maintenance/types/{id}` — edit a type (name, interval, icon, wiki).
  Future<void> updateType(int typeId, MaintenanceTypeDraft draft) => guard(
    () => _dio.patch<dynamic>(
      Endpoints.maintenanceType(typeId),
      data: draft.toJson(),
    ),
  );

  /// `DELETE /maintenance/types/{id}` — remove custom type (system → soft-hide).
  Future<void> deleteType(int typeId) =>
      guard(() => _dio.delete<dynamic>(Endpoints.maintenanceType(typeId)));

  /// `POST /maintenance/types/restore-defaults` — un-hide soft-deleted defaults.
  Future<void> restoreDefaults() =>
      guard(() => _dio.post<dynamic>(Endpoints.maintenanceRestoreDefaults));

  /// `POST /maintenance/printers/{printerId}/assign/{typeId}` — attach a custom
  /// type to a printer so it shows up in that printer's status.
  Future<void> assignType(int printerId, int typeId) => guard(
    () => _dio.post<dynamic>(Endpoints.maintenanceAssign(printerId, typeId)),
  );

  // --- Per-printer item management (Status tab) ---

  /// `PATCH /maintenance/items/{id}` — toggle mute ([enabled]) and/or set a
  /// per-printer interval override ([customIntervalHours], null clears it).
  Future<void> updateItem(
    int itemId, {
    bool? enabled,
    double? customIntervalHours,
    bool clearInterval = false,
    String? customIntervalType,
  }) => guard(
    () => _dio.patch<dynamic>(
      Endpoints.maintenanceItem(itemId),
      data: {
        'enabled': ?enabled,
        if (clearInterval)
          'custom_interval_hours': null
        else
          'custom_interval_hours': ?customIntervalHours,
        'custom_interval_type': ?customIntervalType,
      },
    ),
  );

  /// `GET /maintenance/items/{id}/history` — execution history.
  Future<List<MaintenanceHistoryEntry>> fetchHistory(int itemId) async {
    return guard(
      () => _dio.getList(
        Endpoints.maintenanceHistory(itemId),
        MaintenanceHistoryEntry.fromJson,
      ),
    );
  }
}
