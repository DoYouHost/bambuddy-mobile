import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/json_utils.dart';
import '../core/models/maintenance.dart';

/// REST data source for printer maintenance (M7): status overview per printer,
/// mark task as done (reset counter), and history.
///
/// Auth adds `AuthInterceptor` to the shared Dio. List parsing is defensive
/// (skip bad entries), and [fetchPrinter] degrades to `null` on non-auth errors —
/// a single unreachable printer won't break post-print reminders.
class MaintenanceRepository {
  MaintenanceRepository(this._dio);

  final Dio _dio;

  /// `GET /maintenance/overview` — all active printers. Skip unparseable entries.
  Future<List<PrinterMaintenanceOverview>> fetchOverview() async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(Endpoints.maintenanceOverview);
      return res.data ?? const [];
    });
    return parseJsonList(body, PrinterMaintenanceOverview.fromJson);
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

  // --- Type management (Settings tab) ---

  /// `GET /maintenance/types` — full catalog (system + custom, non-deleted).
  Future<List<MaintenanceType>> fetchTypes() async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(Endpoints.maintenanceTypes);
      return res.data ?? const [];
    });
    return parseJsonList(body, MaintenanceType.fromJson);
  }

  /// `POST /maintenance/types` — create a custom type. Returns it (with new id).
  Future<MaintenanceType> createType(MaintenanceTypeDraft draft) =>
      guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.maintenanceTypes,
          data: draft.toJson(),
        );
        return MaintenanceType.fromJson(res.data ?? const {});
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
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.maintenanceHistory(itemId),
      );
      return res.data ?? const [];
    });
    return parseJsonList(body, MaintenanceHistoryEntry.fromJson);
  }
}
