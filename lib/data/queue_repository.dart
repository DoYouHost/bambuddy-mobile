import 'package:app_util/app_util.dart';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/api/observed_capability.dart';
import '../core/api/server_version.dart';
import '../core/api/server_version_service.dart';
import '../core/models/calibration_option.dart';
import '../core/models/queue_item.dart';

/// Sentinel distinguishing "argument not passed" from an explicit `null` in
/// [QueueRepository.updateItem], where `null` is a meaningful value that clears
/// a nullable column server-side. Public so callers can request an explicit
/// omission (e.g. keep `ams_mapping` untouched in model-based assignment).
const Object kQueueUpdateUnset = Object();

/// `{groupId: position}` as JSON can carry it — with the group ids stringified,
/// which every JSON object must do and `jsonEncode` refuses to do itself.
///
/// An empty pick is sent as `null`: the server reads either as "assign them for
/// me", and null is what clears a stored pick on a PATCH.
Map<String, int>? rackChoiceWire(Object? choice) {
  if (choice is! Map<int, int> || choice.isEmpty) return null;
  return {for (final e in choice.entries) '${e.key}': e.value};
}

/// Everything the print form decides before a queue item exists — the create
/// counterpart of [QueueRepository.updateItem]'s named parameters. Mirrors
/// `PrintQueueItemCreate`, where every field has a default: null means "not
/// configured" and the key is left out (on create no stored value could be cleared).
/// The whole configuration goes with the POST, so the scheduler cannot dispatch a
/// freshly added item while the user is still configuring it.
class QueueCreateOptions {
  const QueueCreateOptions({
    this.targetModel,
    this.targetLocation,
    this.filamentOverrides,
    this.amsMapping,
    this.plateId,
    this.scheduledTime,
    this.requirePreviousSuccess,
    this.autoOffAfter,
    this.manualStart,
    this.bedLevelling,
    this.flowCali,
    this.vibrationCali,
    this.layerInspect,
    this.timelapse,
    this.nozzleOffsetCali,
    this.gcodeInjection,
    this.confirmOutcome,
    this.preheatOverride,
    this.preheatChamberTargetOverride,
    this.nozzleRackChoice,
    this.batchId,
    this.costCenterId,
  });

  final String? targetModel;
  final String? targetLocation;
  final List<Map<String, dynamic>>? filamentOverrides;
  final List<int>? amsMapping;
  final int? plateId;

  /// ISO-8601 UTC start time; null = ASAP/queue (eligible immediately).
  final String? scheduledTime;

  final bool? requirePreviousSuccess;
  final bool? autoOffAfter;

  /// Stage the item: the scheduler leaves it alone until the user starts it.
  final bool? manualStart;

  final CalibrationOption? bedLevelling;
  final CalibrationOption? flowCali;
  final bool? vibrationCali;
  final bool? layerInspect;
  final bool? timelapse;
  final CalibrationOption? nozzleOffsetCali;

  /// Inject the per-model auto-print G-code snippets (`Settings → Workflow` on
  /// the web) into this job's 3MF before it is uploaded. Needed by plate-swap
  /// rigs (SwapMod, Farmloop, …); a no-op when the target model has no snippet.
  final bool? gcodeInjection;

  /// Ask for the outcome when the job completes (#1898). Null leaves it to the
  /// server's default, `False` on the create route.
  final bool? confirmOutcome;

  final String? preheatOverride;
  final int? preheatChamberTargetOverride;

  /// Which rack position each filament group prints from, `{groupId: position}`
  /// (H2C, server #1784). Null leaves every group to the scheduler, which is
  /// also the only thing a server that predates the field can do — the print
  /// form only offers the pick once a printer has reported a rack.
  final Map<int, int>? nozzleRackChoice;

  /// An existing batch to add the copies into (v0.2.4.8+) — how an order made
  /// beforehand gets its runs. Without it, `quantity > 1` makes a grouping.
  final int? batchId;

  /// Where the job's cost is booked. Sent only while the server has billing on,
  /// when a create without one is refused (`validate_print_budget`); the server
  /// derives the estimate itself and ignores one sent.
  final int? costCenterId;

  /// These options with the three fields that are only known once an order for
  /// the copies exists (or has been refused): the plate its target names, the
  /// order itself, and the outcome flag resolved against the server's default.
  QueueCreateOptions withOrder({
    required int? plateId,
    required int? batchId,
    required bool? confirmOutcome,
  }) => QueueCreateOptions(
    targetModel: targetModel,
    targetLocation: targetLocation,
    filamentOverrides: filamentOverrides,
    amsMapping: amsMapping,
    plateId: plateId,
    scheduledTime: scheduledTime,
    requirePreviousSuccess: requirePreviousSuccess,
    autoOffAfter: autoOffAfter,
    manualStart: manualStart,
    bedLevelling: bedLevelling,
    flowCali: flowCali,
    vibrationCali: vibrationCali,
    layerInspect: layerInspect,
    timelapse: timelapse,
    nozzleOffsetCali: nozzleOffsetCali,
    gcodeInjection: gcodeInjection,
    confirmOutcome: confirmOutcome,
    preheatOverride: preheatOverride,
    preheatChamberTargetOverride: preheatChamberTargetOverride,
    nozzleRackChoice: nozzleRackChoice,
    batchId: batchId,
    costCenterId: costCenterId,
  );

  /// Body fragment merged into the POST. Null fields are absent, not null-valued.
  ///
  /// [triState] says whether the server can store `auto` on the three
  /// calibrations. Creating uses [CalibrationOption.toCreateWire], not
  /// `toWire`: there is no stored value to protect here, so an `auto` the server
  /// cannot keep is sent as the state the form was showing rather than omitted.
  Map<String, dynamic> toJson({required bool triState}) => <String, dynamic>{
    'target_model': ?targetModel,
    'target_location': ?targetLocation,
    'filament_overrides': ?filamentOverrides,
    'ams_mapping': ?amsMapping,
    'plate_id': ?plateId,
    'scheduled_time': ?scheduledTime,
    'require_previous_success': ?requirePreviousSuccess,
    'auto_off_after': ?autoOffAfter,
    'manual_start': ?manualStart,
    'bed_levelling': ?bedLevelling?.toCreateWire(triState: triState),
    'flow_cali': ?flowCali?.toCreateWire(triState: triState),
    'vibration_cali': ?vibrationCali,
    'layer_inspect': ?layerInspect,
    'timelapse': ?timelapse,
    'nozzle_offset_cali': ?nozzleOffsetCali?.toCreateWire(triState: triState),
    'gcode_injection': ?gcodeInjection,
    'confirm_outcome': ?confirmOutcome,
    'preheat_override': ?preheatOverride,
    'preheat_chamber_target_override': ?preheatChamberTargetOverride,
    'nozzle_rack_choice': ?rackChoiceWire(nozzleRackChoice),
    'batch_id': ?batchId,
    'cost_center_id': ?costCenterId,
  };
}

/// One change for many queue items — the body of `PATCH /queue/bulk`
/// (`PrintQueueBulkUpdate`) without the ids. Every field null means "leave it":
/// the server applies only the keys that are present, so a field the user did
/// not touch is never sent. The web's modal offers exactly these thirteen and no
/// more, and so does the app.
///
/// [printerId] has three states instead of two, which is why it is an `Object?`
/// as in [QueueRepository.updateItem]: [kQueueUpdateUnset] leaves the printer,
/// `null` takes the item off its printer, an `int` puts it on that one. The
/// route has no `target_model`, so an "any X" item given a printer here keeps its
/// model, where the single-item edit clears it.
class QueueBulkChanges {
  const QueueBulkChanges({
    this.printerId = kQueueUpdateUnset,
    this.manualStart,
    this.autoOffAfter,
    this.requirePreviousSuccess,
    this.gcodeInjection,
    this.bedLevelling,
    this.flowCali,
    this.vibrationCali,
    this.layerInspect,
    this.timelapse,
    this.useAms,
    this.confirmOutcome,
    this.nozzleOffsetCali,
  });

  final Object? printerId;
  final bool? manualStart;
  final bool? autoOffAfter;
  final bool? requirePreviousSuccess;
  final bool? gcodeInjection;
  final CalibrationOption? bedLevelling;
  final CalibrationOption? flowCali;
  final bool? vibrationCali;
  final bool? layerInspect;
  final bool? timelapse;
  final bool? useAms;
  final bool? confirmOutcome;
  final CalibrationOption? nozzleOffsetCali;

  /// Nothing to send: the server answers such a body with 400 ("No fields to
  /// update"), so the form keeps its Apply button off while this holds.
  bool get isEmpty => toJson(triState: true).isEmpty;

  /// The calibration options go through [CalibrationOption.toWire], as on a
  /// single edit: an `auto` a pre-1.2.5 server cannot store drops out rather
  /// than being rewritten as a boolean over a value the user never saw.
  Map<String, dynamic> toJson({required bool triState}) => <String, dynamic>{
    if (printerId != kQueueUpdateUnset) 'printer_id': printerId,
    'manual_start': ?manualStart,
    'auto_off_after': ?autoOffAfter,
    'require_previous_success': ?requirePreviousSuccess,
    'gcode_injection': ?gcodeInjection,
    'bed_levelling': ?bedLevelling?.toWire(triState: triState),
    'flow_cali': ?flowCali?.toWire(triState: triState),
    'vibration_cali': ?vibrationCali,
    'layer_inspect': ?layerInspect,
    'timelapse': ?timelapse,
    'use_ams': ?useAms,
    'confirm_outcome': ?confirmOutcome,
    'nozzle_offset_cali': ?nozzleOffsetCali?.toWire(triState: triState),
  };
}

/// What `PATCH /queue/bulk` did: [updated] items changed, [skipped] left alone
/// because they were not `pending`, were being dispatched, were not the
/// caller's, or needed a start right the caller lacks.
typedef QueueBulkResult = ({int updated, int skipped});

/// What `POST /queue/printer/{id}/resume` did: [acknowledged] failed prints no
/// longer hold the printer's gate, and [restored] skipped jobs are `pending`
/// again. Both zero means there was nothing to clear.
typedef QueueResumeResult = ({int acknowledged, int restored});

/// A page of the queue history: [total] rows match in all. Not [serverOrdered]
/// when an older server sent the whole history, unsorted.
typedef QueueHistoryPage = ({
  List<QueueItem> items,
  int total,
  bool serverOrdered,
});

typedef QueueHistoryCleared = ({int cleared, int kept});

/// REST data source for print queue (M5).
///
/// Auth adds [AuthInterceptor] to the shared Dio.
/// Each method maps [DioException] to [AppApiException].
class QueueRepository {
  QueueRepository(this._dio, [this._serverVersion]);

  final Dio _dio;

  /// Fallback for the wire form of the three calibration options, used until a
  /// queue response has shown it. Optional because the read-only callers (the
  /// watch relay) never write one, and a missing service reads the same as an
  /// unknown version: the boolean form, which every server generation accepts.
  final ServerVersionService? _serverVersion;

  /// Whether this server stores the calibration options as `off`/`on`/`auto`. What the
  /// server puts in `bed_levelling` outranks its version number, which cannot be
  /// trusted here (docs/server-gates.md, `triStateCalibration`). Unknown → the boolean
  /// form, which every server accepts.
  late final triStateCapability = ObservedCapability(
    ServerFeature.triStateCalibration,
    _serverVersion,
  );

  /// Whether this server can ask for a job's outcome (#1898). Observed like
  /// [triStateCapability]: `confirm_outcome` is a defaulted field of every
  /// queue row from the feature on, absent before it — and an older server
  /// drops it from a create or an update without a word, so unknown → hidden.
  late final outcomeCapability = ObservedCapability(
    ServerFeature.printOutcome,
    _serverVersion,
  );

  static const _calibrationKeys = [
    'bed_levelling',
    'flow_cali',
    'nozzle_offset_cali',
  ];

  /// Records which spelling a queue payload used. Reads the raw JSON rather than
  /// the parsed [QueueItem], because the whole point of the parsed form is that
  /// both spellings collapse into one enum.
  void _observeCalibrationWire(List<dynamic> records) {
    for (final record in records) {
      if (record is! Map) continue;
      for (final key in _calibrationKeys) {
        final value = record[key];
        if (value is String) {
          triStateCapability.observe(present: true);
          return;
        }
        if (value is bool) {
          triStateCapability.observe(present: false);
          return;
        }
      }
    }
  }

  /// GET /queue/ — defensive list parsing (skip unparseable entries,
  /// like [PrintersRepository.fetchPrinters]).
  ///
  /// Optional query: `printer_id`, `status` (omitted if null).
  Future<List<QueueItem>> fetch({int? printerId, String? status}) async {
    final query = <String, dynamic>{'printer_id': printerId, 'status': status}
      ..removeWhere((_, v) => v == null);
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.queue,
        queryParameters: query.isNotEmpty ? query : null,
      );
      return res.data ?? const [];
    });
    _observeCalibrationWire(body);
    outcomeCapability.observeKey(body.firstOrNull, 'confirm_outcome');
    return parseJsonList(body, QueueItem.fromJson);
  }

  /// The queue as the app shows it: everything waiting plus whatever is printing, in
  /// two filtered requests run concurrently (the server takes one status per call).
  /// Unfiltered, `GET /queue/` answers with every item ever queued: 218 kB after two
  /// months, polled every 10 s. A paused print needs no third: the server keeps it
  /// `printing`.
  Future<List<QueueItem>> fetchActive() async {
    final lists = await Future.wait([
      fetch(status: 'pending'),
      fetch(status: 'printing'),
    ]);
    // An item that starts printing between the two answers comes back in both.
    // The `printing` list is applied second, so the fresher truth wins.
    final byId = <int, QueueItem>{};
    for (final item in lists.expand((list) => list)) {
      byId[item.id] = item;
    }
    return byId.values.toList();
  }

  /// POST /queue/reorder — change element order.
  ///
  /// Body: `{"items": [{"id": .., "position": ..}, ...]}`.
  Future<void> reorder(List<({int id, int position})> items) {
    final body = {
      'items': [
        for (final it in items) {'id': it.id, 'position': it.position},
      ],
    };
    return guard(() => _dio.post<dynamic>(Endpoints.queueReorder, data: body));
  }

  /// DELETE /queue/{id} — delete item from queue. Keeps the detail: the 400 for a
  /// printing row names the status, which is the whole explanation (see [stop]). False
  /// when the server kept the row as cancelled instead, the last run a batch order can
  /// re-queue its plate from (`deleted: false`, `print_queue.py::delete_queue_item`,
  /// #2960).
  Future<bool> delete(int itemId) => guardKeepingDetail(() async {
    final res = await _dio.delete<dynamic>(Endpoints.queueItem(itemId));
    final body = res.data;
    return !(body is Map && body['deleted'] == false);
  });

  /// Whether the server has [Endpoints.queueHistory]; null until asked.
  bool? _hasHistoryRoute;

  /// An older server reads `GET /queue/history` as `/queue/{item_id}` and
  /// refuses "history" as an int. A 403 is left out: the route is there, and
  /// the fallback would be refused the same.
  static const _historyRouteMissing = {404, 405, 422};

  /// The first [limit] rows of the history in the server's order, from
  /// [Endpoints.queueHistory]; on an older server the whole history from
  /// [fetchHistory], for the caller to sort ([QueueHistoryPage.serverOrdered]).
  /// [sortBy] and [reverse] are the route's own: date/name/printer, and newest
  /// first, A to Z unless reversed.
  Future<QueueHistoryPage> fetchHistoryPage({
    required String sortBy,
    required bool reverse,
    required int limit,
  }) async {
    if (_hasHistoryRoute != false) {
      try {
        final res = await _dio.get<Map<String, dynamic>>(
          Endpoints.queueHistory,
          queryParameters: {
            'sort_by': sortBy,
            'reverse': reverse,
            'limit': limit,
          },
        );
        _hasHistoryRoute = true;
        final body = res.data ?? const <String, dynamic>{};
        final rows = body['items'] is List ? body['items'] as List : const [];
        _observeCalibrationWire(rows);
        return (
          items: parseJsonList(rows, QueueItem.fromJson),
          total: toInt(body['total']),
          serverOrdered: true,
        );
      } on DioException catch (e) {
        // Once the route has answered, a failure is a failure, not an old server.
        if (_hasHistoryRoute == true ||
            !_historyRouteMissing.contains(e.response?.statusCode)) {
          throw mapDioException(e);
        }
        _hasHistoryRoute = false;
      }
    }
    final items = await fetchHistory();
    return (items: items, total: items.length, serverOrdered: false);
  }

  /// Clears the history: one [Endpoints.queueHistoryClear] where the server
  /// has it, else one `DELETE` per row of [shown], which is then the whole
  /// history. Counts the runs a batch order kept as cancelled instead.
  Future<QueueHistoryCleared> clearHistory(List<QueueItem> shown) async {
    if (_hasHistoryRoute == true) {
      return guard(() async {
        final res = await _dio.post<dynamic>(Endpoints.queueHistoryClear);
        final data = res.data;
        return (
          cleared: data is Map ? toIntOrNull(data['cleared']) ?? 0 : 0,
          kept: data is Map ? toIntOrNull(data['kept']) ?? 0 : 0,
        );
      });
    }
    var cleared = 0;
    var kept = 0;
    for (final item in shown) {
      if (await delete(item.id)) {
        cleared++;
      } else {
        kept++;
      }
    }
    return (cleared: cleared, kept: kept);
  }

  /// The queue's history as the web's History tab listed it before
  /// [Endpoints.queueHistory]: every item that completed, failed, was skipped or
  /// was cancelled — one request per status, as the server filters on one at a
  /// time.
  ///
  /// Fetched only while the history is on screen: it is the bulk of an
  /// unfiltered queue (see [fetchActive]).
  Future<List<QueueItem>> fetchHistory() async {
    final lists = await Future.wait([
      for (final status in const [
        'completed',
        'failed',
        'skipped',
        'cancelled',
      ])
        fetch(status: status),
    ]);
    return [for (final list in lists) ...list];
  }

  /// PATCH /queue/{id} — assign printer to item (before start). Sends `target_model:
  /// null` too: an "any X" item already has a model, and the server refuses a row
  /// holding both with 400 (`print_queue.py::update_queue_item`). Keeps the detail
  /// like [updateItem], the same route.
  Future<void> assignPrinter(int itemId, int printerId) => guardKeepingDetail(
    () => _dio.patch<dynamic>(
      Endpoints.queueItem(itemId),
      data: {'printer_id': printerId, 'target_model': null},
    ),
  );

  /// PATCH /queue/{id} — set the AMS slot mapping (file filament slot → global
  /// AMS tray). Body: `{"ams_mapping": [..]}`.
  Future<void> setAmsMapping(int itemId, List<int> mapping) =>
      guardKeepingDetail(
        () => _dio.patch<dynamic>(
          Endpoints.queueItem(itemId),
          data: {'ams_mapping': mapping},
        ),
      );

  /// PATCH /queue/{id} — full edit of a pending item (Edit Queue Item screen). Keeps
  /// the detail: the route refuses a moved-on row only in the 400's text, which the
  /// screen shows. Mirrors `PrintQueueItemUpdate`: every field is optional and only
  /// applied when present, so `null` is meaningful — it clears a nullable column (e.g.
  /// `scheduled_time: null` = ASAP, `target_model: null` when switching to a specific
  /// printer). For the `Object?` params `null` is sent as an explicit clear;
  /// [kQueueUpdateUnset] (their default) omits the key.
  Future<void> updateItem(
    int itemId, {
    Object? printerId = kQueueUpdateUnset,
    Object? targetModel = kQueueUpdateUnset,
    Object? targetLocation = kQueueUpdateUnset,
    Object? filamentOverrides = kQueueUpdateUnset,
    Object? amsMapping = kQueueUpdateUnset,
    Object? plateId = kQueueUpdateUnset,
    Object? scheduledTime = kQueueUpdateUnset,
    bool? requirePreviousSuccess,
    bool? autoOffAfter,
    bool? manualStart,
    CalibrationOption? bedLevelling,
    CalibrationOption? flowCali,
    bool? vibrationCali,
    bool? layerInspect,
    bool? timelapse,
    bool? useAms,
    CalibrationOption? nozzleOffsetCali,
    bool? gcodeInjection,
    bool? confirmOutcome,
    String? preheatOverride,
    Object? preheatChamberTargetOverride = kQueueUpdateUnset,
    Object? nozzleRackChoice = kQueueUpdateUnset,
    int? costCenterId,
  }) async {
    final triState = await triStateCapability.supported;
    final body = <String, dynamic>{
      if (printerId != kQueueUpdateUnset) 'printer_id': printerId,
      if (targetModel != kQueueUpdateUnset) 'target_model': targetModel,
      if (targetLocation != kQueueUpdateUnset)
        'target_location': targetLocation,
      if (filamentOverrides != kQueueUpdateUnset)
        'filament_overrides': filamentOverrides,
      if (amsMapping != kQueueUpdateUnset) 'ams_mapping': amsMapping,
      if (plateId != kQueueUpdateUnset) 'plate_id': plateId,
      if (scheduledTime != kQueueUpdateUnset) 'scheduled_time': scheduledTime,
      'require_previous_success': ?requirePreviousSuccess,
      'auto_off_after': ?autoOffAfter,
      'manual_start': ?manualStart,
      // An `auto` the server cannot store drops out here rather than being sent
      // as a boolean: omitting the key leaves the stored value alone, whereas a
      // boolean would silently rewrite the user's `auto` as on-or-off.
      'bed_levelling': ?bedLevelling?.toWire(triState: triState),
      'flow_cali': ?flowCali?.toWire(triState: triState),
      'vibration_cali': ?vibrationCali,
      'layer_inspect': ?layerInspect,
      'timelapse': ?timelapse,
      'use_ams': ?useAms,
      'nozzle_offset_cali': ?nozzleOffsetCali?.toWire(triState: triState),
      'gcode_injection': ?gcodeInjection,
      'confirm_outcome': ?confirmOutcome,
      'preheat_override': ?preheatOverride,
      if (preheatChamberTargetOverride != kQueueUpdateUnset)
        'preheat_chamber_target_override': preheatChamberTargetOverride,
      if (nozzleRackChoice != kQueueUpdateUnset)
        'nozzle_rack_choice': rackChoiceWire(nozzleRackChoice),
      'cost_center_id': ?costCenterId,
    };
    return guardKeepingDetail(
      () => _dio.patch<dynamic>(Endpoints.queueItem(itemId), data: body),
    );
  }

  /// PATCH /queue/bulk — the same [changes] on every item of [itemIds]. Keeps the
  /// detail like [updateItem]: a missing printer and a refused permission are
  /// told apart only by the 400/403 text. A 200 is not "all done": read
  /// [QueueBulkResult.skipped].
  Future<QueueBulkResult> bulkUpdate(
    List<int> itemIds,
    QueueBulkChanges changes,
  ) async {
    final triState = await triStateCapability.supported;
    final body = <String, dynamic>{
      'item_ids': itemIds,
      ...changes.toJson(triState: triState),
    };
    return guardKeepingDetail(() async {
      final res = await _dio.patch<dynamic>(Endpoints.queueBulk, data: body);
      final data = res.data;
      return (
        updated: data is Map ? toIntOrNull(data['updated_count']) ?? 0 : 0,
        skipped: data is Map ? toIntOrNull(data['skipped_count']) ?? 0 : 0,
      );
    });
  }

  /// POST /queue/printer/{id}/resume — clear the previous-print gate on
  /// [printerId] and restore the jobs it skipped. One atomic route on the server
  /// (#1818); calling it again right after is a harmless no-op with zero counts.
  /// No detail kept: the route has no 400, and its 404 and 403 are plain
  /// statuses.
  Future<QueueResumeResult> resumeAfterFailure(int printerId) => guard(
    () async {
      final res = await _dio.post<dynamic>(
        Endpoints.queuePrinterResume(printerId),
      );
      final data = res.data;
      return (
        acknowledged: data is Map ? toIntOrNull(data['acknowledged']) ?? 0 : 0,
        restored: data is Map ? toIntOrNull(data['restored']) ?? 0 : 0,
      );
    },
  );

  /// POST /queue/model/{model}/resume — [resumeAfterFailure] for "any [model]"
  /// jobs: the gate is cleared on each of its printers, and there is nothing
  /// skipped to restore. Answers how many failures were acknowledged.
  Future<int> resumeModelAfterFailure(String model) => guard(() async {
    final res = await _dio.post<dynamic>(Endpoints.queueModelResume(model));
    final data = res.data;
    return data is Map ? toIntOrNull(data['acknowledged']) ?? 0 : 0;
  });

  /// POST /queue/{id}/start — manually start item.
  ///
  /// Keeps the detail: "Can only start pending items" names the status the
  /// server found, as the removals do.
  Future<void> start(int itemId) => guardKeepingDetail(
    () => _dio.post<dynamic>(Endpoints.queueItemStart(itemId)),
  );

  /// Puts [item] on [printerId] and starts it: assign when it is not there yet, then
  /// the optional [amsMapping], then `POST start`. Three requests with no transaction,
  /// and the start is the one most likely refused (409 filament deficit, 400 status
  /// moved on): a refused start puts the assignment back, or the row would stay bound
  /// to this printer with its "any X" model gone. A mapping on an item that was
  /// already here stays.
  Future<void> startOnPrinter(
    QueueItem item,
    int printerId, {
    List<int>? amsMapping,
  }) async {
    final moved = item.printerId != printerId;
    if (moved) await assignPrinter(item.id, printerId);
    try {
      if (amsMapping != null && amsMapping.isNotEmpty) {
        await setAmsMapping(item.id, amsMapping);
      }
      await start(item.id);
    } on Object {
      if (moved) await _restoreAssignment(item);
      rethrow;
    }
  }

  /// Best effort: the start's own error is what the caller has to see, and a
  /// failed restore has nothing better to say than that one.
  Future<void> _restoreAssignment(QueueItem item) async {
    try {
      await _dio.patch<dynamic>(
        Endpoints.queueItem(item.id),
        data: {
          'printer_id': item.printerId,
          'target_model': item.targetModel,
          'ams_mapping': item.amsMapping,
        },
      );
    } on DioException {
      // See above.
    }
  }

  /// Start the next pending queue item on [printerId] — the watch's "start
  /// next", both directly (REST fallback) and via the phone relay. Throws
  /// [StateError] when nothing pending can print there.
  Future<void> startNextPending(int printerId) async {
    final item = await _nextPendingFor(printerId);
    if (item == null) {
      throw StateError('empty-queue');
    }
    await startOnPrinter(item, printerId);
  }

  /// The item "start next" on [printerId] picks, most specific first: its own items,
  /// then "any model X" items for its model and location, then items with no printer
  /// and no model. By tier, not by position alone: positions all default to 1, so an
  /// old unassigned job would starve the one queued for this printer. Never another
  /// printer's item or a cross-model job. A tier costs a request only when the one
  /// before it came up empty.
  Future<QueueItem?> _nextPendingFor(int printerId) async {
    bool startable(QueueItem q) =>
        q.statusKind == QueueItemStatusKind.pending && q.variants.isEmpty;
    // The printer filter returns its own items plus unassigned ones for its
    // model (`print_queue.py::list_queue`) — but ignores `target_location`,
    // which the scheduler honours when it places such an item.
    final listed = (await fetch(
      printerId: printerId,
      status: 'pending',
    )).where(startable).toList();

    final own = _firstInQueue(listed.where((q) => q.printerId == printerId));
    if (own != null) return own;

    final forModel = listed.where((q) => q.printerId == null).toList();
    if (forModel.any((q) => q.targetLocation != null)) {
      final location = await _printerLocation(printerId);
      forModel.removeWhere(
        (q) => q.targetLocation != null && q.targetLocation != location,
      );
    }
    final modelItem = _firstInQueue(forModel);
    if (modelItem != null) return modelItem;

    final unassigned = await fetch(printerId: -1, status: 'pending');
    return _firstInQueue(
      unassigned.where(
        (q) => startable(q) && q.printerId == null && q.targetModel == null,
      ),
    );
  }

  /// Queue positions frequently all default to 1 (see queue notes), so id
  /// breaks the tie for a stable "first".
  static QueueItem? _firstInQueue(Iterable<QueueItem> items) =>
      items.sorted((a, b) {
        final byPos = a.position.compareTo(b.position);
        return byPos != 0 ? byPos : a.id.compareTo(b.id);
      }).firstOrNull;

  /// Read from the listing the app already uses; [Endpoints] has no
  /// single-printer route. Only asked when a candidate names a location.
  Future<String?> _printerLocation(int printerId) async {
    final printers = await guard(
      () async =>
          (await _dio.get<List<dynamic>>(Endpoints.printers)).data ?? const [],
    );
    for (final p in printers) {
      if (p is Map && p['id'] == printerId) {
        final location = p['location'];
        return location is String ? location : null;
      }
    }
    return null;
  }

  /// POST /queue/{id}/cancel — cancel queue item. Accepted for a `pending`
  /// item only; see [stop] for the rest and for why the detail is kept.
  Future<void> cancel(int itemId) => guardKeepingDetail(
    () => _dio.post<dynamic>(Endpoints.queueItemCancel(itemId)),
  );

  /// POST /queue/{id}/stop — stop the print a `printing` item is running and drop the
  /// item out of the queue (the server writes it `cancelled`). The escape hatch for a
  /// row held as `printing`: `/cancel` takes `pending` alone and `DELETE` refuses a
  /// printing row (issue #35). Harmless when the printer already stopped. Keeps the
  /// detail ([guardKeepingDetail]): the 400 names the status it found.
  Future<void> stop(int itemId) => guardKeepingDetail(
    () => _dio.post<dynamic>(Endpoints.queueItemStop(itemId)),
  );

  /// POST /queue/ — add new item from archive.
  ///
  /// Body: `{"archive_id": .., "printer_id": .., "quantity": ..}` plus whatever
  /// [options] configures; `printer_id` omitted if null. [insertAtTop] jumps
  /// ahead of other pending items in the same printer scope — the web's "ASAP"
  /// schedule, and how "reprint" prints next (the backend removed the direct
  /// `/reprint` endpoint; it's a queue item now).
  Future<void> addFromArchive(
    int archiveId, {
    int? printerId,
    int quantity = 1,
    bool insertAtTop = false,
    QueueCreateOptions? options,
  }) => _add(
    {'archive_id': archiveId},
    printerId: printerId,
    quantity: quantity,
    insertAtTop: insertAtTop,
    options: options,
  );

  /// POST /queue/ — add a library file (e.g. a sliced gcode) to the queue.
  ///
  /// Replaces the removed `POST /library/files/{id}/print` (now 410 Gone). Body
  /// carries `library_file_id`; `printer_id` omitted if null (unassigned).
  Future<void> addFromLibraryFile(
    int fileId, {
    int? printerId,
    int quantity = 1,
    bool insertAtTop = false,
    QueueCreateOptions? options,
  }) => _add(
    {'library_file_id': fileId},
    printerId: printerId,
    quantity: quantity,
    insertAtTop: insertAtTop,
    options: options,
  );

  /// POST /queue/ — one job offering several sliced files, whichever printer frees up
  /// first (server #671, **1.2.6+**). [fileIds] is the priority order, two minimum,
  /// with no `printer_id` (the server refuses the combination) and no per-file
  /// `target_model` (it reads each file's own `sliced_for_model`). The caller checks
  /// [LibraryRepository.variantsCapability] first: an older server answers 422 only
  /// because the rest of the body is then invalid.
  Future<void> addCrossModel(
    List<int> fileIds, {
    int quantity = 1,
    bool insertAtTop = false,
    QueueCreateOptions? options,
  }) => _add(
    {
      'variants': [
        for (final id in fileIds) <String, dynamic>{'library_file_id': id},
      ],
    },
    printerId: null,
    quantity: quantity,
    insertAtTop: insertAtTop,
    options: options,
  );

  /// Shared POST for both sources — [source] is the one key that differs.
  Future<void> _add(
    Map<String, dynamic> source, {
    required int? printerId,
    required int quantity,
    required bool insertAtTop,
    required QueueCreateOptions? options,
  }) async {
    final triState = await triStateCapability.supported;
    final body = <String, dynamic>{
      ...source,
      'printer_id': printerId,
      'quantity': quantity,
      if (insertAtTop) 'insert_at_top': true,
      ...?options?.toJson(triState: triState),
    }..removeWhere((_, v) => v == null);
    // Keeps the detail: a billing server refuses an item with no cost center
    // with 400, and its sentence is the only thing that says why (#3256).
    return guardKeepingDetail(
      () => _dio.post<dynamic>(Endpoints.queue, data: body),
    );
  }
}
