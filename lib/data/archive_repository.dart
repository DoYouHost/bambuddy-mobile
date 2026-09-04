import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/api/observed_capability.dart';
import '../core/api/server_version.dart';
import '../core/api/server_version_service.dart';
import '../core/models/archive.dart';
import '../core/models/archive_media.dart';
import '../core/models/archive_purge.dart';
import '../core/models/json_utils.dart';
import '../core/models/no_3mf_warning.dart';
import '../core/models/plate_list.dart';

/// REST data source for print archive (M5).
///
/// Auth adds [AuthInterceptor] to the shared Dio.
/// Each method maps [DioException] to [AppApiException].
class ArchiveRepository {
  ArchiveRepository(this._dio, [this._serverVersion]);

  final Dio _dio;

  /// Answers [supportsPrinterMedia] until a `printer-media` request has.
  final ServerVersionService? _serverVersion;

  /// Whether this server can look for a print's recordings on the printer.
  ///
  /// Unknown → not offered, because here that is not free: the entry point is
  /// a button on the archive sheet, and there is no older route behind it. A
  /// button that opens onto a 404 is worse than one that is absent.
  late final _printerMedia = ObservedCapability(
    ServerFeature.archivePrinterMedia,
    _serverVersion,
  );

  Future<bool> supportsPrinterMedia() => _printerMedia.supported;

  /// GET /archives/ — paginated archive list.
  ///
  /// Defensive parsing: unparseable entries are skipped.
  Future<List<Archive>> list({
    int limit = 50,
    int offset = 0,
    int? printerId,
  }) async {
    final query = <String, dynamic>{
      'limit': limit,
      'offset': offset,
      'printer_id': printerId,
    }..removeWhere((_, v) => v == null);
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.archives,
        queryParameters: query,
      );
      return res.data ?? const [];
    });
    return parseJsonList(body, Archive.fromJson);
  }

  /// GET /archives/search?q=&limit=&offset= — full-text search.
  ///
  /// Defensive parsing: unparseable entries are skipped. [cancelToken] lets
  /// callers cancel a stale in-flight search (e.g. search-as-you-type) instead
  /// of letting it resolve and race with a newer request.
  Future<List<Archive>> search(
    String q, {
    int limit = 50,
    int offset = 0,
    CancelToken? cancelToken,
  }) async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.archivesSearch,
        queryParameters: {'q': q, 'limit': limit, 'offset': offset},
        cancelToken: cancelToken,
      );
      return res.data ?? const [];
    });
    return parseJsonList(body, Archive.fromJson);
  }

  /// GET /archives/{id} — one archive, re-read rather than reused from the
  /// list: the finish photo is attached in the background after the print
  /// ends, so a list loaded before that still shows the print without it.
  Future<Archive> byId(int archiveId) => guard(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          Endpoints.archive(archiveId),
        );
        return Archive.fromJson(res.data ?? const {});
      });

  /// POST /archives/{id}/favorite — toggle the favorite flag server-side and
  /// return the updated archive (defensively parsed).
  Future<Archive> toggleFavorite(int archiveId) => guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.archiveFavorite(archiveId),
        );
        return Archive.fromJson(res.data ?? const {});
      });

  /// PATCH /archives/{id} — write the filament weight this print is recorded
  /// with, or clear it with a null.
  ///
  /// The one archive figure the app lets a user type. A print that archived
  /// without its 3MF has no weight at all and nothing can supply one after the
  /// fact — a rescan needs the file this archive does not have — so the server
  /// made the column editable and mirrors the new value onto the run's log
  /// entry, which is what the filament totals actually sum.
  ///
  /// Sent as an explicit null rather than omitted when clearing: the server
  /// applies `exclude_unset`, so a key that is *present* and null is what wipes
  /// the column, while an absent key means "leave it alone".
  ///
  /// **`applied` is the whole point.** A server older than the one that added
  /// the field still has the route and still answers 200 — its request model
  /// simply drops a key it cannot name — so the status code says nothing about
  /// whether anything was stored. The response carries the archive as it now
  /// is, so the value that comes back either is the one that went out or the
  /// server threw it away.
  Future<({Archive archive, bool applied})> setFilamentGrams(
    int archiveId,
    double? grams,
  ) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        Endpoints.archive(archiveId),
        data: <String, dynamic>{'filament_used_grams': grams},
      );
      final archive = Archive.fromJson(res.data ?? const {});
      return (
        archive: archive,
        applied: sameFilamentGrams(archive.filamentUsedGrams, grams),
      );
    } on DioException catch (e) {
      // The server bounds the column (0..100 kg) and answers 422 with which
      // bound was crossed. The field checks the same range before sending, so
      // getting here means the two lists drifted — and then its sentence is
      // worth more than ours.
      throw mapDioExceptionKeepingDetail(e);
    }
  }

  /// DELETE /archives/{id} — delete a print from the archive. Soft-delete by
  /// default; [purgeStats] sends `?purge_stats=true` to also remove the print
  /// from aggregate statistics.
  Future<void> delete(int archiveId, {bool purgeStats = false}) => guard(() => _dio.delete<dynamic>(
        Endpoints.archive(archiveId),
        queryParameters: {'purge_stats': purgeStats},
      ));

  /// GET /archives/purge/preview — count + size of prints older than
  /// [olderThanDays] eligible for purge. Read-only.
  Future<ArchivePurgePreview> purgePreview({
    required int olderThanDays,
    bool purgeStats = false,
  }) =>
      guard(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          Endpoints.archivesPurgePreview,
          queryParameters: {
            'older_than_days': olderThanDays,
            'purge_stats': purgeStats,
          },
        );
        return ArchivePurgePreview.fromJson(res.data ?? const {});
      });

  /// GET /archives/{id}/plates — the plates of a multi-plate 3MF.
  ///
  /// Best-effort by design: every failure answers [PlateList.none], which reads
  /// as "no plate to choose" and leaves the caller looking exactly as it did
  /// before plates existed. That covers a server without the route, an archive
  /// whose file is gone (404), a `.gcode` that was never a 3MF, and an account
  /// without `archives:read` (403) — four causes, one correct response.
  Future<PlateList> plates(int archiveId) async {
    final data = await guardOrNullAllowingForbidden(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.archivePlates(archiveId),
      );
      return res.data;
    });
    return data == null ? PlateList.none : PlateList.fromJson(data);
  }

  /// GET /archives/no-3mf-warning — whether any print in the last 30 days
  /// archived without its 3MF, and why.
  ///
  /// Best-effort like [plates]: a server that lacks the route, or a user whose
  /// permissions do not reach it (403), gets no nudge rather than an error. The
  /// `reason` key is newer than the route, and its absence is a meaningful
  /// answer rather than a gap — see [No3mfReason.slicerSetting].
  Future<No3mfWarning> no3mfWarning() async {
    final data = await guardOrNullAllowingForbidden(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.archivesNo3mfWarning,
      );
      return res.data;
    });
    return data == null ? No3mfWarning.none : No3mfWarning.fromJson(data);
  }

  /// POST /archives/purge — bulk-delete prints older than [olderThanDays].
  /// [purgeStats] also drops them from statistics (irreversible). Returns the
  /// number of deleted prints.
  Future<int> purge({
    required int olderThanDays,
    bool purgeStats = false,
  }) =>
      guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.archivesPurge,
          data: {'older_than_days': olderThanDays, 'purge_stats': purgeStats},
        );
        return toInt(res.data?['deleted']);
      });

  /// GET /archives/{id}/printer-media — the recordings this print can still be
  /// given, from the server's own copy and from the printer's storage.
  ///
  /// **Null means this server has no such route** and the caller offers
  /// nothing; every other failure bubbles up, because a search that broke is
  /// not a search that found nothing.
  ///
  /// The deadline is the server's own work: it lists up to five directories
  /// over the printer's FTP at 8 seconds each, so anything near the client
  /// default would abort a search that was about to answer.
  Future<ArchivePrinterMedia?> printerMedia(int archiveId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.archivePrinterMedia(archiveId),
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
      _printerMedia.observe(present: true);
      return ArchivePrinterMedia.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      _printerMedia.observeFailure(status);
      if (status == 404) return null;
      throw mapDioException(e);
    }
  }
}

/// Whether the weight that came back is the one that was sent.
///
/// Compared with a tolerance rather than by `==`: the figure makes a round trip
/// through JSON and a float column, and a thousandth of a gram of drift is the
/// same weight — while no edit worth reporting as saved moves it by less than
/// that. Only used to tell "stored" from "an older server dropped the key",
/// which are a whole typed number apart.
bool sameFilamentGrams(double? stored, double? sent) =>
    stored == null || sent == null
        ? stored == sent
        : (stored - sent).abs() < 0.001;
