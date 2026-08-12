import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/api/server_version_service.dart';
import '../core/models/calibration_option.dart';
import '../core/models/json_utils.dart';
import '../core/models/queue_item.dart';

/// Sentinel distinguishing "argument not passed" from an explicit `null` in
/// [QueueRepository.updateItem], where `null` is a meaningful value that clears
/// a nullable column server-side. Public so callers can request an explicit
/// omission (e.g. keep `ams_mapping` untouched in model-based assignment).
const Object kQueueUpdateUnset = Object();

/// Everything the print form decides before a queue item exists — the create
/// counterpart of [QueueRepository.updateItem]'s named parameters.
///
/// Mirrors the server's `PrintQueueItemCreate`, where every field has a default:
/// a null here means "not configured", the key is left out of the body, and the
/// server's own default applies. That is why this is a plain object rather than
/// the sentinel dance `updateItem` needs — on create there is no stored value a
/// null could clear.
///
/// Sending the whole configuration with the POST is the point: it closes the
/// window in which the scheduler could dispatch a freshly added item while the
/// user is still configuring it (see `docs/plans/06b-log-findings.md`).
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
    this.preheatOverride,
    this.preheatChamberTargetOverride,
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

  final String? preheatOverride;
  final int? preheatChamberTargetOverride;

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
        'nozzle_offset_cali':
            ?nozzleOffsetCali?.toCreateWire(triState: triState),
        'gcode_injection': ?gcodeInjection,
        'preheat_override': ?preheatOverride,
        'preheat_chamber_target_override': ?preheatChamberTargetOverride,
      };
}

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

  /// What the server's own queue payload showed, once one has arrived.
  ///
  /// This outranks the version number, because the version number cannot always
  /// answer the question. bambuddy renumbered the 0.2.5 development cycle to
  /// 1.2.5 partway through, so a server reporting `0.2.5b2` is a beta of the very
  /// release that introduced the tri-state options — yet `0.2.5b2` sorts below
  /// `1.2.5` on every sane comparison, and no ordering of those two strings can
  /// tell you whether that particular beta predates the change. What the server
  /// puts in `bed_levelling` answers it outright.
  bool? _observedTriState;

  static const _calibrationKeys = [
    'bed_levelling',
    'flow_cali',
    'nozzle_offset_cali',
  ];

  /// Whether this server stores the calibration options as `off`/`on`/`auto`.
  /// Observed contract first, version second, and `false` when neither knows —
  /// the boolean form is the one every server accepts.
  Future<bool> supportsTriStateCalibration() async =>
      _observedTriState ??
      (await _serverVersion?.supportsTriStateCalibration() ?? false);

  /// Records which spelling a queue payload used. Reads the raw JSON rather than
  /// the parsed [QueueItem], because the whole point of the parsed form is that
  /// both spellings collapse into one enum.
  void _observeCalibrationWire(List<dynamic> records) {
    for (final record in records) {
      if (record is! Map) continue;
      for (final key in _calibrationKeys) {
        final value = record[key];
        if (value is String) {
          _observedTriState = true;
          return;
        }
        if (value is bool) {
          _observedTriState = false;
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
    final query = <String, dynamic>{
      'printer_id': printerId,
      'status': status,
    }..removeWhere((_, v) => v == null);
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.queue,
        queryParameters: query.isNotEmpty ? query : null,
      );
      return res.data ?? const [];
    });
    _observeCalibrationWire(body);
    return parseJsonList(body, QueueItem.fromJson);
  }

  /// The queue as the app shows it: everything waiting plus whatever is
  /// printing, in two filtered requests instead of one unfiltered one.
  ///
  /// Unfiltered, `GET /queue/` answers with every item the server has ever
  /// queued — measured on a real server after two months: 163 records, 218 kB,
  /// growing with each print, all of it to render the handful that are still
  /// active. The queue screen polls every 10 s, so that was the whole print
  /// history on the wire six times a minute, and it is what made the endpoint
  /// take eight seconds in a user's diagnostic log.
  ///
  /// The server takes one status per call, hence two calls; they run
  /// concurrently, so the wait is the slower one rather than their sum. A paused
  /// print needs no third call — the server keeps such an item `printing` and
  /// the pause lives in the printer's state.
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

  /// DELETE /queue/{id} — delete item from queue.
  Future<void> delete(int itemId) =>
      guard(() => _dio.delete<dynamic>(Endpoints.queueItem(itemId)));

  /// PATCH /queue/{id} — assign printer to item (before start).
  /// Body: `{"printer_id": ..}`.
  Future<void> assignPrinter(int itemId, int printerId) => guard(() => _dio.patch<dynamic>(
        Endpoints.queueItem(itemId),
        data: {'printer_id': printerId},
      ));

  /// PATCH /queue/{id} — set the AMS slot mapping (file filament slot → global
  /// AMS tray). Body: `{"ams_mapping": [..]}`.
  Future<void> setAmsMapping(int itemId, List<int> mapping) => guard(() => _dio.patch<dynamic>(
        Endpoints.queueItem(itemId),
        data: {'ams_mapping': mapping},
      ));

  /// PATCH /queue/{id} — full edit of a pending item (Edit Queue Item screen).
  ///
  /// Mirrors the server's `PrintQueueItemUpdate`: every field is optional and
  /// only applied when present, so `null` is meaningful — it clears a nullable
  /// column (e.g. `scheduled_time: null` = ASAP/queue, `target_model: null` when
  /// switching to a specific printer). For the `Object?` params, `null` is sent
  /// as an explicit clear; pass [kQueueUpdateUnset] (their default) to omit the
  /// key entirely and leave the server value untouched.
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
    String? preheatOverride,
    Object? preheatChamberTargetOverride = kQueueUpdateUnset,
  }) async {
    final triState = await supportsTriStateCalibration();
    final body = <String, dynamic>{
      if (printerId != kQueueUpdateUnset) 'printer_id': printerId,
      if (targetModel != kQueueUpdateUnset) 'target_model': targetModel,
      if (targetLocation != kQueueUpdateUnset) 'target_location': targetLocation,
      if (filamentOverrides != kQueueUpdateUnset) 'filament_overrides': filamentOverrides,
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
      'preheat_override': ?preheatOverride,
      if (preheatChamberTargetOverride != kQueueUpdateUnset)
        'preheat_chamber_target_override': preheatChamberTargetOverride,
    };
    return guard(
        () => _dio.patch<dynamic>(Endpoints.queueItem(itemId), data: body));
  }

  /// POST /queue/{id}/start — manually start item.
  Future<void> start(int itemId) =>
      guard(() => _dio.post<dynamic>(Endpoints.queueItemStart(itemId)));

  /// Start the next pending queue item on [printerId]. Assigns the printer
  /// first if the item isn't already bound to it (server requires the printer
  /// set before start). Throws [StateError] when the queue has nothing
  /// pending. Shared by the watch ("start next" button) both directly (REST
  /// fallback) and via the phone relay.
  Future<void> startNextPending(int printerId) async {
    final items = await fetch();
    // Queue positions frequently all default to 1 (see queue notes), so sort
    // by position then id for a stable "first" pick.
    final pending = items
        .where((q) => q.statusKind == QueueItemStatusKind.pending)
        .toList()
      ..sort((a, b) {
        final byPos = a.position.compareTo(b.position);
        return byPos != 0 ? byPos : a.id.compareTo(b.id);
      });
    if (pending.isEmpty) {
      throw StateError('empty-queue');
    }
    final item = pending.first;
    if (item.printerId != printerId) {
      await assignPrinter(item.id, printerId);
    }
    await start(item.id);
  }

  /// POST /queue/{id}/cancel — cancel queue item.
  Future<void> cancel(int itemId) =>
      guard(() => _dio.post<dynamic>(Endpoints.queueItemCancel(itemId)));

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
  }) =>
      _add({'archive_id': archiveId},
          printerId: printerId,
          quantity: quantity,
          insertAtTop: insertAtTop,
          options: options);

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
  }) =>
      _add({'library_file_id': fileId},
          printerId: printerId,
          quantity: quantity,
          insertAtTop: insertAtTop,
          options: options);

  /// POST /queue/ — one job offering several sliced files, whichever printer
  /// frees up first (server #671, **1.2.6+**).
  ///
  /// [fileIds] is the priority order: when more than one printer is idle at the
  /// same moment, the earlier candidate wins. Two files minimum, and no
  /// `printer_id` — naming a printer defeats the purpose and the server rejects
  /// the combination outright.
  ///
  /// `target_model` per candidate is deliberately not sent: the server reads it
  /// from each file's own `sliced_for_model`, and overriding that is only for
  /// legacy 3MFs that declare none — which the phone has no way to identify.
  ///
  /// The caller must have checked [LibraryRepository.supportsCrossModelVariants]
  /// first; an older server answers 422 for the unknown `variants` shape only
  /// because the rest of the body is then invalid, which is a confusing way to
  /// learn the feature is missing.
  Future<void> addCrossModel(
    List<int> fileIds, {
    int quantity = 1,
    bool insertAtTop = false,
    QueueCreateOptions? options,
  }) =>
      _add(
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
    final triState = await supportsTriStateCalibration();
    final body = <String, dynamic>{
      ...source,
      'printer_id': printerId,
      'quantity': quantity,
      if (insertAtTop) 'insert_at_top': true,
      ...?options?.toJson(triState: triState),
    }..removeWhere((_, v) => v == null);
    return guard(() => _dio.post<dynamic>(Endpoints.queue, data: body));
  }
}
