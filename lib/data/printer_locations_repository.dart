import 'package:app_util/app_util.dart';
import 'package:dio/dio.dart';

import '../core/api/endpoints.dart';
import '../core/api/observed_capability.dart';
import '../core/api/server_version.dart';
import '../core/api/server_version_service.dart';
import '../core/models/printer_location.dart';

/// The managed list of printer locations (server #2962).
///
/// Every write addresses a location by its name, in the body, and is one
/// transaction on the server — a rename moves the printers, the queue items
/// aimed at the location and the groups' grants together, which is the reason
/// to call these instead of patching each printer's `location`.
class PrinterLocationsRepository {
  PrinterLocationsRepository(this._dio, [this._serverVersion]);

  final Dio _dio;

  /// Answers [capability] until the listing has.
  final ServerVersionService? _serverVersion;

  /// Whether the server has the route family at all.
  late final capability = ObservedCapability(
    ServerFeature.printerLocations,
    _serverVersion,
  );

  /// Every location, those only printers carry included, in natural name
  /// order. A 404 or a 403 answers with an empty list: the latch has recorded
  /// why, and the screen is additive.
  Future<List<PrinterLocation>> list() => capability.watching(
    () async {
      final res = await _dio.get<List<dynamic>>(Endpoints.printerLocations);
      return parseJsonList(res.data, PrinterLocation.fromJson);
    },
    absent: () => const [],
    observing: treat404AsAbsent,
  );

  /// None of the writes settles [capability]: their 403 is a missing
  /// `printers:update` — which no API key holds — and taking it for "no
  /// locations here" would hide a list the session may read.
  ///
  /// A 409 is a name already taken, case-insensitively.
  Future<PrinterLocation> create(PrinterLocationDraft draft) =>
      capability.watching(observing: const {}, () async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.printerLocations,
          data: draft.toCreateJson(),
        );
        return PrinterLocation.fromJson(res.data ?? const {});
      });

  /// Renames and/or restyles. A 404 is a location that is gone, a 409 a
  /// rename onto a name already taken, and a 403 a location that also holds
  /// printers the caller cannot see (or a group's grant only an admin moves).
  Future<PrinterLocation> update(PrinterLocationDraft draft) =>
      capability.watching(observing: const {}, () async {
        final res = await _dio.patch<Map<String, dynamic>>(
          Endpoints.printerLocations,
          data: draft.toUpdateJson(),
        );
        return PrinterLocation.fromJson(res.data ?? const {});
      });

  /// Their printers end up with no location. Queue items aimed at a deleted
  /// location are left alone, so one may be left waiting for printers that no
  /// longer have it. Returns how many locations existed to be deleted.
  Future<int> delete(List<String> names) =>
      capability.watching(observing: const {}, () async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.printerLocationsDelete,
          data: {'names': names},
        );
        return toInt(res.data?['deleted']);
      });

  /// Moves [printerIds] into [location], or out of any with `null`. Returns
  /// how many printers changed. A printer someone else moved meanwhile moves
  /// again only if it is in this request.
  Future<int> assign(List<int> printerIds, String? location) =>
      capability.watching(observing: const {}, () async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.printerLocationsAssign,
          data: {'printer_ids': printerIds, 'location': location},
        );
        return toInt(res.data?['moved']);
      });
}
