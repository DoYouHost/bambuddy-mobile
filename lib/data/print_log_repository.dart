import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/api/server_version.dart';
import '../core/api/server_version_service.dart';
import '../core/models/json_utils.dart';
import '../core/models/print_log_entry.dart';

/// A column `GET /print-log/` can order by, with the key the server names it
/// (`print_log.py::_SORTABLE_COLUMNS`). Anything outside that map is a 400, so
/// these strings are the contract, not labels.
///
/// Only the subset the mobile list can meaningfully sort by is here; the web
/// table offers a few more it has columns for.
enum PrintLogSort {
  /// `started_at` falling back to `created_at` — the date the row shows, so
  /// runs that never started stay where the reader sees them.
  date('date'),
  printName('print_name'),
  printer('printer'),
  user('user'),
  status('status'),
  duration('duration'),
  filamentUsed('filament_used'),
  cost('cost'),
  energy('energy');

  const PrintLogSort(this.wire);

  final String wire;
}

/// REST data source for the print log (`/print-log/`) — one row per run, in a
/// table that outlives the archives it points at.
///
/// Auth adds `AuthInterceptor` to the shared Dio; each method maps
/// [DioException] to [AppApiException]. Parsing is defensive: a malformed row
/// drops itself rather than the page (see [parseJsonList]).
class PrintLogRepository {
  PrintLogRepository(this._dio, [this._serverVersion]);

  final Dio _dio;
  final ServerVersionService? _serverVersion;

  /// The server's own cap (`limit: int = Query(default=50, ge=1, le=500)`).
  /// Asking for more is a 422, not a clamp.
  static const maxPageSize = 500;

  /// Whether this server sends per-run cost and energy, and honours a sort
  /// order. One question because it is one server change (#2636): below it the
  /// three fields are absent — indistinguishable from a run without a smart
  /// plug — and `sort_by` is an unknown query param, which FastAPI drops in
  /// silence rather than refusing.
  ///
  /// Version-only, with no observation to outrank it: both halves are fields on
  /// an endpoint that answers 200 either way.
  Future<bool> supportsCostEnergy() async =>
      await _serverVersion?.supports(ServerFeature.printLogCostEnergy) ?? false;

  /// GET /print-log/ — one page of runs, plus how many the filter matches.
  ///
  /// [dateFrom] / [dateTo] are instants: pass the local day boundaries and they
  /// go out converted. Every other filter is exact except [search], which is an
  /// `ilike` on the print name.
  ///
  /// [sort] is dropped on a server that would ignore it, so a caller cannot
  /// believe an order it never got — check [supportsCostEnergy] before offering
  /// the control.
  Future<PrintLogPage> list({
    String? search,
    int? printerId,
    String? status,
    String? createdByUsername,
    DateTime? dateFrom,
    DateTime? dateTo,
    int limit = 50,
    int offset = 0,
    PrintLogSort? sort,
    bool descending = true,
  }) async {
    final sortable = sort != null && await supportsCostEnergy();
    final query = <String, dynamic>{
      'search': search == null || search.isEmpty ? null : search,
      'printer_id': printerId,
      'status': status,
      'created_by_username': createdByUsername,
      'date_from': _instant(dateFrom),
      'date_to': _instant(dateTo),
      'limit': limit,
      'offset': offset,
      'sort_by': sortable ? sort.wire : null,
      'sort_dir': sortable ? (descending ? 'desc' : 'asc') : null,
    }..removeWhere((_, v) => v == null);

    final body = await guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.printLog,
        queryParameters: query,
      );
      return res.data ?? const <String, dynamic>{};
    });
    return PrintLogPage(
      items: parseJsonList(body['items'], PrintLogEntry.fromJson),
      total: toInt(body['total']),
    );
  }

  /// PATCH /print-log/{id} — re-classify one run, and answer it as the server
  /// stored it.
  ///
  /// Only the fields named here are sent, because the server applies
  /// `exclude_unset`: leaving [status] out is what lets a row keep a value the
  /// PATCH vocabulary cannot write back (`aborted` — see [printLogStatuses]).
  /// [clearFailureReason] sends `''`, the server's "no classification".
  ///
  /// Refused with 400 for a value outside either vocabulary; the server's
  /// wording survives, since our list drifting from its list is the only way to
  /// get there.
  Future<PrintLogEntry> updateEntry(
    int entryId, {
    String? failureReason,
    bool clearFailureReason = false,
    String? status,
  }) async {
    // `?value` omits the entry entirely when the value is null, which is what
    // an unsent field has to be here — clearing sends `''`, so the two cases
    // collapse into one expression: '' is never null, and so never omitted.
    final data = <String, dynamic>{
      'failure_reason': ?(clearFailureReason ? '' : failureReason),
      'status': ?status,
    };
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        Endpoints.printLogEntry(entryId),
        data: data,
      );
      return PrintLogEntry.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioExceptionKeepingDetail(e);
    }
  }

  /// DELETE /print-log/{id} — drop one run. The archive it points at is
  /// untouched (the FK runs the other way), but the run's filament, cost and
  /// duration leave the aggregate statistics with it.
  Future<void> deleteEntry(int entryId) =>
      guard(() => _dio.delete<dynamic>(Endpoints.printLogEntry(entryId)));

  /// DELETE /print-log/ — clear the whole log and answer how many rows went.
  ///
  /// Every user's rows, not the caller's, and every filter is ignored: the
  /// route takes no query at all. Archives and queue items are never touched.
  Future<int> clearAll() => guard(() async {
        final res = await _dio.delete<Map<String, dynamic>>(Endpoints.printLog);
        return toInt(res.data?['deleted']);
      });

  /// A `datetime` query param the way the server can compare it.
  ///
  /// Sent as UTC but **without** the `Z`: the columns are naive UTC
  /// (`DateTime` with no timezone), and a tz-aware bind param compares against
  /// those differently depending on the database behind the server. The web
  /// sends a bare `YYYY-MM-DD`, which lands on UTC midnight and quietly shifts
  /// the range for anyone not on UTC — passing the converted instant is the
  /// same wire type without that skew.
  static String? _instant(DateTime? value) {
    if (value == null) return null;
    final utc = value.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}T'
        '${utc.hour.toString().padLeft(2, '0')}:'
        '${utc.minute.toString().padLeft(2, '0')}:'
        '${utc.second.toString().padLeft(2, '0')}';
  }
}
