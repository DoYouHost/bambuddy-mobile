import 'package:app_util/app_util.dart';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/api/observed_capability.dart';
import '../core/api/server_version.dart';
import '../core/api/server_version_service.dart';
import '../core/models/json_utils.dart';
import '../core/models/print_batch.dart';

/// How many runs of one plate an order asks for (`PrintBatchPlateTarget`).
/// [plateId] null is a single-plate file, not "unknown plate".
typedef BatchPlateTarget = ({int? plateId, String? plateName, int quantity});

List<Map<String, dynamic>> _platesWire(List<BatchPlateTarget> plates) => [
  for (final (i, p) in plates.indexed)
    {
      'plate_id': p.plateId,
      'plate_name': ?p.plateName,
      'quantity_target': p.quantity,
      // The list order is the order the screens show, so it is the sort key.
      'sort_order': i,
    },
];

/// Print batches and orders — `/queue/batches` (see [Endpoints.queueBatches]).
///
/// Permissions are the queue's, so an API key with `can_queue` does all of it.
class BatchRepository {
  BatchRepository(this._dio, [this._serverVersion]);

  final Dio _dio;
  final ServerVersionService? _serverVersion;

  /// Whether the route exists here: the list's own answer, else the version.
  late final listCapability = ObservedCapability(
    ServerFeature.batchListing,
    _serverVersion,
  );

  /// Grouping by hand and ungrouping (v0.2.4.8). Nothing in a batch row tells
  /// 0.2.4.7 from 0.2.4.8, so only an order — which is newer still — settles
  /// it before the version does.
  late final groupingCapability = ObservedCapability(
    ServerFeature.batchGrouping,
    _serverVersion,
  );

  /// Orders (#342): targets, editing and dispatch. The list outranks the
  /// version: a batch row either carries `has_targets` or predates it.
  ///
  /// **Callers check it before sending `plates`, `due_date`, `notes` or
  /// `project_id` on [create]** — from v0.2.4.8 an older server drops them
  /// without a word and makes a plain grouping.
  late final ordersCapability = ObservedCapability(
    ServerFeature.batchOrders,
    _serverVersion,
  );

  void _observe(Object? row) {
    if (row is! Map) return;
    final orders = row.containsKey('has_targets');
    ordersCapability.observe(present: orders);
    if (orders) groupingCapability.observe(present: true);
  }

  /// GET /queue/batches — newest first. [status] null lists every status.
  ///
  /// The server leaves out batches with neither items nor targets.
  Future<List<PrintBatch>> list({PrintBatchStatus? status}) async {
    final List<dynamic> body;
    try {
      body = await listCapability.watching(
        observing: treat404AsAbsent,
        () async {
          final res = await _dio.get<List<dynamic>>(
            Endpoints.queueBatches,
            queryParameters: status == null ? null : {'status': status.name},
          );
          return res.data ?? const [];
        },
      );
    } on ApiException catch (e) {
      // Before v0.2.3: `GET /queue/{item_id}` refusing "batches" as an id.
      if (e.statusCode == 422) listCapability.observe(present: false);
      rethrow;
    }
    _observe(body.firstOrNull);
    return parseJsonList(body, PrintBatch.fromJson);
  }

  /// GET /queue/batches/{id}. A 404 is the batch gone or not this caller's.
  Future<PrintBatch> get(int batchId) async {
    final body = await guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.queueBatch(batchId),
      );
      return res.data ?? const <String, dynamic>{};
    });
    _observe(body);
    return PrintBatch.fromJson(body);
  }

  /// POST /queue/batches (v0.2.4.8+, see [groupingCapability]). With
  /// [itemIds] it groups those pending items (the ones already in a batch, not
  /// pending or not the caller's are skipped); without, it makes an empty
  /// batch to pass as `batch_id` on queue creates.
  ///
  /// Keeps the detail: the 400s ("Duplicate plate in order", "Order must
  /// request at least one print") are the only explanation of a refusal.
  Future<PrintBatch> create({
    required String name,
    List<int>? itemIds,
    int? archiveId,
    int? libraryFileId,
    List<BatchPlateTarget>? plates,
    int? projectId,
    DateTime? dueDate,
    String? notes,
  }) async {
    final body = await guardKeepingDetail(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.queueBatches,
        data: <String, dynamic>{
          'name': name,
          'item_ids': ?itemIds,
          'archive_id': ?archiveId,
          'library_file_id': ?libraryFileId,
          'plates': ?(plates == null ? null : _platesWire(plates)),
          'project_id': ?projectId,
          'due_date': ?(dueDate == null ? null : instantToJson(dueDate)),
          'notes': ?notes,
        },
      );
      return res.data ?? const <String, dynamic>{};
    });
    _observe(body);
    return PrintBatch.fromJson(body);
  }

  /// PATCH /queue/batches/{id} (1.2.5.3+). A null argument is left alone — the
  /// server has no way to clear [dueDate] or [projectId] once set, and
  /// [notes] clears only to `""`.
  ///
  /// [plates] replaces the whole target set: a plate left out loses its row.
  /// [reopen] makes a cancelled order active again. The route also takes
  /// `cancelled`, which this app does not send: it would close the order and
  /// leave its pending items queued — [cancel] is the one that stops them.
  Future<PrintBatch> update(
    int batchId, {
    String? name,
    String? notes,
    DateTime? dueDate,
    int? projectId,
    List<BatchPlateTarget>? plates,
    bool reopen = false,
  }) async {
    final body = await guardKeepingDetail(() async {
      final res = await _dio.patch<Map<String, dynamic>>(
        Endpoints.queueBatch(batchId),
        data: <String, dynamic>{
          'name': ?name,
          'notes': ?notes,
          'due_date': ?(dueDate == null ? null : instantToJson(dueDate)),
          'project_id': ?projectId,
          'plates': ?(plates == null ? null : _platesWire(plates)),
          if (reopen) 'status': 'active',
        },
      );
      return res.data ?? const <String, dynamic>{};
    });
    _observe(body);
    return PrintBatch.fromJson(body);
  }

  /// POST /queue/batches/{id}/dispatch — queue what the order still owes, or
  /// only [plate]'s share when given. Answers with the batch after it.
  ///
  /// `plate_id` null is a real plate (single-plate file), so a one-plate
  /// dispatch always says `only_plate` rather than leaving it to the null.
  /// Keeps the detail: the stranded-plate 400 names the plates.
  Future<PrintBatch> dispatch(int batchId, {PrintBatchPlate? plate}) async {
    final body = await guardKeepingDetail(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.queueBatchDispatch(batchId),
        data: plate == null
            ? const <String, dynamic>{}
            : {'plate_id': plate.plateId, 'only_plate': true},
      );
      return res.data ?? const <String, dynamic>{};
    });
    _observe(body);
    return PrintBatch.fromJson(body);
  }

  /// POST /queue/batches/{id}/ungroup (v0.2.4.8+) — how many items left the
  /// batch. The row survives while it still holds items this caller may not
  /// touch.
  Future<int> ungroup(int batchId) async {
    final body = await guardKeepingDetail(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.queueBatchUngroup(batchId),
      );
      return res.data;
    });
    return (body?['ungrouped_count'] as num?)?.toInt() ?? 0;
  }

  /// DELETE /queue/batches/{id} — cancels the pending items and marks the
  /// batch cancelled. Needs `queue:delete_all`.
  Future<void> cancel(int batchId) => guardKeepingDetail(
    () => _dio.delete<dynamic>(Endpoints.queueBatch(batchId)),
  );
}
