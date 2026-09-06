import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/inventory.dart';
import '../core/models/inventory_bulk.dart';
import '../core/models/inventory_reference.dart';
import '../core/models/json_utils.dart';
import '../core/models/printer_status.dart';
import '../core/models/spool_label.dart';
import '../core/models/spool_preset_override.dart';

/// Filament inventory backend. User has native, but app should also work on Spoolman —
/// selected via setting (see `inventoryBackendProvider`).
enum InventoryBackend { native, spoolman }

/// Whether the server would accept [tag] as a link target, by its own rules
/// (`spoolman.py::link_spool`): 16 or 32 hex digits, not all zeros. The status
/// route already nulls an unwritten tag, so this catches what an older server
/// or third-party firmware lets through — a bare 400 otherwise.
bool _isLinkableTag(String? tag) {
  final t = tag?.trim().toUpperCase();
  if (t == null || (t.length != 16 && t.length != 32)) return false;
  if (!RegExp(r'^[0-9A-F]+$').hasMatch(t)) return false;
  return t.split('').any((c) => c != '0');
}

/// [guard] that also keeps what the server wrote when it answers 404.
///
/// The from-slot routes spend that status on two unrelated failures — the
/// printer is not connected, or the route does not exist on this server at all
/// — and the base mapper keeps `detail` only for 403, so without this the two
/// are indistinguishable and the user is told the wrong thing about half the
/// time.
Future<T> _guardKeeping404Detail<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on DioException catch (e) {
    final mapped = mapDioException(e);
    final detail = serverDetailOf(e.response?.data);
    if (mapped is! ApiException ||
        e.response?.statusCode != 404 ||
        detail == null) {
      throw mapped;
    }
    throw ApiException(
      mapped.code,
      statusCode: 404,
      detail: detail,
      method: mapped.method,
      path: mapped.path,
    );
  }
}

/// Common interface for inventory data source — UI and providers don't know which
/// backend is running (swappable pattern like `BackgroundMonitor`). Each implementation
/// maps raw JSON from its API to normalized models.
///
/// Read (Phase 1) + spool management (Phase 2: create/update/delete/archive/restore/
/// reset-usage). AMS assignments and catalog come later. Writes require API key
/// permission (missing → [AuthException] forbidden).
abstract class SpoolInventorySource {
  /// All spools. `includeArchived` includes archived ones.
  Future<List<Spool>> fetchSpools({bool includeArchived = false});

  /// Spool assignments to AMS slots (shows where a spool is placed).
  /// [printerId] narrows the answer to one printer, which both backends filter
  /// server-side.
  Future<List<SpoolAssignment>> fetchAssignments({int? printerId});

  /// Throws if the slot [draft] names cannot take a spool on this backend. A
  /// move unpins the old slot first, so a refusal that only surfaced from
  /// [assignSpool] would leave the spool in neither.
  Future<void> ensureAssignable(SpoolAssignmentDraft draft);

  /// Assigns a spool to a slot (printer/AMS unit/tray).
  Future<void> assignSpool(SpoolAssignmentDraft draft);

  /// Unassigns a spool from a slot.
  Future<void> unassignSpool(int printerId, int amsId, int trayId);

  /// Registers whatever the AMS slot currently holds as a new spool and pins
  /// it to that slot in one call. Returns the new spool's id, or null when the
  /// backend created one without saying which.
  ///
  /// The slot must carry a readable RFID tag: without one the server refuses
  /// (400), because a tagless slot has no identity to re-link to and every
  /// confirm would mint another row.
  Future<int?> createSpoolFromSlot({
    required int printerId,
    required int amsId,
    required int trayId,
  });

  /// Usage history for a single spool (loaded on-demand in details).
  Future<List<SpoolUsageEntry>> fetchUsage(int spoolId);

  /// Creates a new spool; returns the created, normalized record.
  Future<Spool> createSpool(SpoolDraft draft);

  /// Bulk-creates [quantity] identical spools ("restock"). Returns how many
  /// were actually created (Spoolman may create fewer than requested and
  /// report partial success — see [SpoolmanInventorySource.bulkCreateSpools]).
  Future<int> bulkCreateSpools(SpoolDraft draft, int quantity);

  /// Updates spool fields; returns the updated record.
  Future<Spool> updateSpool(int spoolId, SpoolDraft draft);

  /// Permanently deletes a spool (irreversible — UI confirms).
  Future<void> deleteSpool(int spoolId);

  /// Archives / restores a spool (soft hide from active list).
  Future<void> archiveSpool(int spoolId);
  Future<void> restoreSpool(int spoolId);

  /// Resets the spool's "Total Consumed" counter. Remaining weight is
  /// preserved and the weight lock is left alone, so the spool keeps taking
  /// AMS auto-sync from the next print on.
  Future<void> resetUsage(int spoolId);

  /// Bulk operations on a selection. Each returns what the server did, chunked
  /// to the 500-id cap and summed. All of them throw with `statusCode == 404`
  /// on a server older than the routes (0.2.5b1) — unknown ids are reported in
  /// the body, never as a status, so the caller can read that 404 as "this
  /// server has no bulk routes" and fall back to per-spool calls.
  Future<BulkOutcome> bulkUpdate(List<int> spoolIds, SpoolBulkPatch patch);
  Future<BulkOutcome> bulkArchive(List<int> spoolIds);
  Future<BulkOutcome> bulkRestore(List<int> spoolIds);
  Future<BulkOutcome> bulkDelete(List<int> spoolIds);
  Future<BulkOutcome> bulkResetUsage(List<int> spoolIds);

  /// Form reference data (core weight catalog, color database, filament profiles).
  /// Degrade to empty lists — form allows manual entry.
  Future<List<CoreWeightEntry>> fetchCoreWeights();
  Future<List<ColorEntry>> fetchColors();
  Future<List<FilamentPreset>> fetchFilamentPresets();

  /// Storage-location catalog for the location picker, and for matching a
  /// spool's free-text location to the row the server keys its Home Assistant
  /// sensors by. Native only; Spoolman degrades to empty (the picker still
  /// accepts free text).
  Future<List<StorageLocation>> fetchLocations();

  /// Renders the labels [request] describes and returns the PDF bytes.
  Future<Uint8List> renderLabels(SpoolLabelRequest request);

  /// One spool's per-printer-model preset overrides, and the replace that
  /// writes them back (server 1.2.6; see [SpoolPresetOverride]).
  ///
  /// The two exceptions to the rule that everything here answers with a mapped
  /// [AppApiException]: [InventoryRepository] runs them inside a latch that has
  /// to read the status off the [DioException] itself — a 403 to record the
  /// refusal, a 404 to answer the read with no rows. It maps what it rethrows,
  /// so nothing above the repository sees the difference.
  Future<List<SpoolPresetOverride>> fetchPresetOverrides(int spoolId);

  /// Replaces the whole list — an empty one clears every override. The route
  /// has no merge, so a caller that could not read the current rows must not
  /// call this: it would delete what it never saw.
  Future<void> savePresetOverrides(
    int spoolId,
    List<SpoolPresetOverride> overrides,
  );
}

/// Whether [bytes] open with `%PDF`, the magic number every PDF starts with.
bool _looksLikePdf(Uint8List bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x25 && // %
    bytes[1] == 0x50 && // P
    bytes[2] == 0x44 && // D
    bytes[3] == 0x46; //  F

/// Shared label-render call — the two backends differ only in path, since both
/// routes take the same body and stream back a PDF.
///
/// The result is verified to actually BE a PDF before it reaches the caller.
/// A server that answers 200 with something else (an older build without the
/// label routes, a captive portal, the demo backend — whose catch-all answers
/// every unrouted POST with `{}`) would otherwise reach the platform print
/// dialog, and Android's print framework rejects malformed input by throwing
/// on the main thread — a native crash Dart cannot catch.
Future<Uint8List> _postLabels(
  Dio dio,
  String path,
  SpoolLabelRequest request,
) => guard(() async {
  final res = await dio.post<List<int>>(
    path,
    data: request.toJson(),
    // The response is a PDF stream, not JSON — without this Dio's default
    // JSON transformer would try to decode it and throw.
    options: Options(responseType: ResponseType.bytes),
  );
  final bytes = Uint8List.fromList(res.data ?? const []);
  if (!_looksLikePdf(bytes)) {
    throw ApiException(
      AppErrorCode.malformedResponse,
      statusCode: res.statusCode,
      detail: 'Expected a PDF from $path, got ${bytes.length} bytes',
    );
  }
  return bytes;
});

/// Shared per-model preset override calls — the two backends differ only in
/// path, since both routes take and answer the same body.
///
/// Deliberately unguarded: the latch in [InventoryRepository] reads the status
/// off the [DioException] and maps what it rethrows. See
/// [SpoolInventorySource.fetchPresetOverrides].
Future<List<SpoolPresetOverride>> _getPresetOverrides(
  Dio dio,
  String path,
) async {
  final res = await dio.get<List<dynamic>>(path);
  return parseJsonList(res.data, SpoolPresetOverride.fromJson);
}

Future<void> _putPresetOverrides(
  Dio dio,
  String path,
  List<SpoolPresetOverride> overrides,
) async {
  await dio.put<dynamic>(path, data: [for (final o in overrides) o.toJson()]);
}

/// A JSON object out of a response body, or null when the server answered with
/// something else — the demo backend replies `{}` to unrouted POSTs and an old
/// build could answer a bare list, and neither may crash a bulk tally.
Map<String, dynamic>? _objectOf(Object? data) =>
    data is Map ? data.cast<String, dynamic>() : null;

/// Sends one request per chunk of the 500-id cap and sums what came back.
///
/// A refusal part-way through keeps what the earlier chunks already did: those
/// rows are mutated on the server, and throwing here would report the whole
/// selection as failed while hundreds of spools had in fact been archived. The
/// ids from the failing chunk on are counted as failed, since none of them took
/// effect.
///
/// With nothing accumulated yet the error propagates instead — that is the path
/// carrying "no permission" to the user, and the 404 the caller reads as "this
/// server has no bulk routes" before falling back to per-spool calls.
Future<BulkOutcome> _postChunked(
  List<int> ids,
  Future<BulkOutcome> Function(List<int> chunk) send,
) async {
  var total = BulkOutcome.empty;
  var done = 0;
  for (final chunk in chunkIds(ids)) {
    try {
      total += await send(chunk);
    } on Object {
      if (done == 0) rethrow;
      return total + BulkOutcome(failed: ids.length - done);
    }
    done += chunk.length;
  }
  return total;
}

/// The three `{ids: […]}` routes — archive, restore, delete. [okKey] and
/// [skippedKey] name the counters this particular route answers with.
Future<BulkOutcome> _postBulkIds(
  Dio dio,
  String path,
  List<int> ids, {
  required String okKey,
  String? skippedKey,
}) => _postChunked(
  ids,
  (chunk) => guard(() async {
    final res = await dio.post<dynamic>(path, data: {'ids': chunk});
    return BulkOutcome.fromJson(
      _objectOf(res.data),
      okKey: okKey,
      skippedKey: skippedKey,
    );
  }),
);

/// `bulk-update`. [update] is the backend's own serialization of the patch, so
/// an edit that only touches native-only columns arrives here empty on
/// Spoolman — nothing to apply, and the route answers 400 to an empty `update`,
/// so it is not sent at all.
Future<BulkOutcome> _postBulkUpdate(
  Dio dio,
  String path,
  List<int> ids,
  Map<String, dynamic> update,
) async {
  if (update.isEmpty) return BulkOutcome.empty;
  return _postChunked(
    ids,
    (chunk) => guard(() async {
      final res = await dio.post<dynamic>(
        path,
        data: {'ids': chunk, 'update': update},
      );
      return BulkOutcome.fromJson(_objectOf(res.data), okKey: 'updated');
    }),
  );
}

/// `reset-consumed-counter-bulk` — the one route keyed on `spool_ids` rather
/// than `ids`, and the one that reports only a count.
Future<BulkOutcome> _postBulkReset(Dio dio, String path, List<int> ids) =>
    _postChunked(
      ids,
      (chunk) => guard(() async {
        final res = await dio.post<dynamic>(path, data: {'spool_ids': chunk});
        return BulkOutcome.fromResetJson(_objectOf(res.data), chunk.length);
      }),
    );

/// POSTs [path], and on 404 posts [legacyPath] instead.
///
/// For a route the server renamed without leaving an alias: the two names never
/// coexist, so a 404 on the current one identifies an older server rather than
/// a missing spool. Written for `reset-consumed-counter`, which replaced
/// `reset-usage` (server issue #1644) — the app has to keep working on both
/// sides of that rename.
Future<void> _postWithLegacyFallback(Dio dio, String path, String legacyPath) =>
    guard(() async {
      try {
        await dio.post<dynamic>(path);
      } on DioException catch (e) {
        if (e.response?.statusCode != 404) rethrow;
        await dio.post<dynamic>(legacyPath);
      }
    });

/// Native backend `/inventory/*` (default). Auth adds shared `AuthInterceptor`;
/// errors mapped to typed [AppApiException].
class NativeInventorySource implements SpoolInventorySource {
  NativeInventorySource(this._dio);

  final Dio _dio;

  @override
  Future<List<Spool>> fetchSpools({bool includeArchived = false}) async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.inventorySpools,
        queryParameters: {'include_archived': includeArchived},
      );
      return res.data ?? const [];
    });
    return parseJsonList(body, Spool.fromNative);
  }

  @override
  Future<List<SpoolAssignment>> fetchAssignments({int? printerId}) async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.inventoryAssignments,
        queryParameters: {'printer_id': ?printerId},
      );
      return res.data ?? const [];
    });
    return parseJsonList(body, SpoolAssignment.fromNative);
  }

  /// The native route keys on the triple itself, so no slot can refuse.
  @override
  Future<void> ensureAssignable(SpoolAssignmentDraft draft) async {}

  @override
  Future<void> assignSpool(SpoolAssignmentDraft draft) => guard(
    () => _dio.post<dynamic>(
      Endpoints.inventoryAssignments,
      data: draft.toNativeJson(),
    ),
  );

  @override
  Future<void> unassignSpool(int printerId, int amsId, int trayId) => guard(
    () => _dio.delete<dynamic>(
      Endpoints.inventoryAssignment(printerId, amsId, trayId),
    ),
  );

  @override
  Future<int?> createSpoolFromSlot({
    required int printerId,
    required int amsId,
    required int trayId,
  }) => _guardKeeping404Detail(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      Endpoints.inventorySpoolFromSlot,
      data: {'printer_id': printerId, 'ams_id': amsId, 'tray_id': trayId},
    );
    return toIntOrNull(res.data?['id']);
  });

  @override
  Future<List<SpoolUsageEntry>> fetchUsage(int spoolId) async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.inventorySpoolUsage(spoolId),
      );
      return res.data ?? const [];
    });
    return parseJsonList(body, SpoolUsageEntry.fromNative);
  }

  @override
  Future<Spool> createSpool(SpoolDraft draft) => guard(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      Endpoints.inventorySpools,
      data: draft.toNativeJson(),
    );
    return Spool.fromNative(res.data ?? const {});
  });

  @override
  Future<int> bulkCreateSpools(SpoolDraft draft, int quantity) =>
      guard(() async {
        final res = await _dio.post<List<dynamic>>(
          Endpoints.inventorySpoolsBulk,
          data: {'spool': draft.toNativeJson(), 'quantity': quantity},
        );
        // Endpoint returns the list of created spools.
        return res.data?.length ?? 0;
      });

  @override
  Future<Spool> updateSpool(int spoolId, SpoolDraft draft) => guard(() async {
    final res = await _dio.patch<Map<String, dynamic>>(
      Endpoints.inventorySpool(spoolId),
      data: draft.toNativeJson(),
    );
    return Spool.fromNative(res.data ?? const {});
  });

  @override
  Future<void> deleteSpool(int spoolId) =>
      guard(() => _dio.delete<dynamic>(Endpoints.inventorySpool(spoolId)));

  @override
  Future<void> archiveSpool(int spoolId) =>
      guard(() => _dio.post<dynamic>(Endpoints.inventorySpoolArchive(spoolId)));

  @override
  Future<void> restoreSpool(int spoolId) =>
      guard(() => _dio.post<dynamic>(Endpoints.inventorySpoolRestore(spoolId)));

  @override
  Future<void> resetUsage(int spoolId) => _postWithLegacyFallback(
    _dio,
    Endpoints.inventorySpoolResetConsumedCounter(spoolId),
    Endpoints.inventorySpoolResetUsage(spoolId),
  );

  @override
  Future<BulkOutcome> bulkUpdate(List<int> spoolIds, SpoolBulkPatch patch) =>
      _postBulkUpdate(
        _dio,
        Endpoints.inventorySpoolsBulkUpdate,
        spoolIds,
        patch.toNativeJson(),
      );

  @override
  Future<BulkOutcome> bulkArchive(List<int> spoolIds) => _postBulkIds(
    _dio,
    Endpoints.inventorySpoolsBulkArchive,
    spoolIds,
    okKey: 'archived',
    skippedKey: 'already_archived',
  );

  @override
  Future<BulkOutcome> bulkRestore(List<int> spoolIds) => _postBulkIds(
    _dio,
    Endpoints.inventorySpoolsBulkRestore,
    spoolIds,
    okKey: 'restored',
    skippedKey: 'already_active',
  );

  @override
  Future<BulkOutcome> bulkDelete(List<int> spoolIds) => _postBulkIds(
    _dio,
    Endpoints.inventorySpoolsBulkDelete,
    spoolIds,
    okKey: 'deleted',
  );

  @override
  Future<BulkOutcome> bulkResetUsage(List<int> spoolIds) => _postBulkReset(
    _dio,
    Endpoints.inventorySpoolsResetConsumedCounterBulk,
    spoolIds,
  );

  @override
  Future<List<CoreWeightEntry>> fetchCoreWeights() async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(Endpoints.inventoryCatalog);
      return res.data ?? const [];
    });
    return parseJsonList(body, CoreWeightEntry.fromJson);
  }

  @override
  Future<List<ColorEntry>> fetchColors() async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(Endpoints.inventoryColors);
      return res.data ?? const [];
    });
    return parseJsonList(body, ColorEntry.fromJson);
  }

  @override
  Future<List<FilamentPreset>> fetchFilamentPresets() async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(Endpoints.filamentCatalog);
      return res.data ?? const [];
    });
    return parseJsonList(body, FilamentPreset.fromJson);
  }

  @override
  Future<List<StorageLocation>> fetchLocations() => guard(() async {
    final res = await _dio.get<List<dynamic>>(Endpoints.inventoryLocations);
    return [
      for (final loc in parseJsonList(res.data, StorageLocation.fromJson))
        if (loc.name.isNotEmpty) loc,
    ];
  });

  @override
  Future<Uint8List> renderLabels(SpoolLabelRequest request) =>
      _postLabels(_dio, Endpoints.inventoryLabels, request);

  @override
  Future<List<SpoolPresetOverride>> fetchPresetOverrides(int spoolId) =>
      _getPresetOverrides(
        _dio,
        Endpoints.inventorySpoolFilamentPresets(spoolId),
      );

  @override
  Future<void> savePresetOverrides(
    int spoolId,
    List<SpoolPresetOverride> overrides,
  ) => _putPresetOverrides(
    _dio,
    Endpoints.inventorySpoolFilamentPresets(spoolId),
    overrides,
  );
}

/// Spoolman backend `/spoolman/inventory/*`. Spoolman returns loose passthrough, so
/// [Spool.fromSpoolman]/[SpoolAssignment.fromSpoolman] mappers are more forgiving.
/// Usage history has no stable shape — empty for now.
class SpoolmanInventorySource implements SpoolInventorySource {
  SpoolmanInventorySource(this._dio);

  final Dio _dio;

  @override
  Future<List<Spool>> fetchSpools({bool includeArchived = false}) async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.spoolmanSpools,
        queryParameters: {'include_archived': includeArchived},
      );
      return res.data ?? const [];
    });
    return parseJsonList(body, Spool.fromSpoolman);
  }

  @override
  Future<List<SpoolAssignment>> fetchAssignments({int? printerId}) async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.spoolmanAssignments,
        queryParameters: {'printer_id': ?printerId},
      );
      return res.data ?? const [];
    });
    return parseJsonList(body, SpoolAssignment.fromSpoolman);
  }

  /// Spoolman binds a spool to the tag the slot reads, so the tag has to be
  /// looked up live first. The triple still travels with it: the server writes
  /// the same slot ledger [fetchAssignments] reads back, which is what keeps
  /// this path and the native one showing the same thing.
  @override
  Future<void> ensureAssignable(SpoolAssignmentDraft draft) =>
      _requireSlotTag(draft);

  @override
  Future<void> assignSpool(SpoolAssignmentDraft draft) async {
    final tag = await _requireSlotTag(draft);
    await guard(
      () => _dio.post<dynamic>(
        Endpoints.spoolmanSpoolLink(draft.spoolId),
        data: {
          ...tag,
          'printer_id': draft.printerId,
          'ams_id': draft.amsId,
          'tray_id': draft.trayId,
        },
      ),
    );
  }

  /// Unlink is keyed on the spool, so the slot resolves to one first. An empty
  /// slot is not an error, the same way it is not on the native path.
  @override
  Future<void> unassignSpool(int printerId, int amsId, int trayId) async {
    final held = (await fetchAssignments(printerId: printerId))
        .where((a) => a.amsId == amsId && a.trayId == trayId)
        .map((a) => a.spoolId)
        // An unparsed spool id reads as -1 — that would unlink `/spools/-1`.
        .where((id) => id > 0);
    if (held.isEmpty) return;
    await guard(
      () => _dio.post<dynamic>(Endpoints.spoolmanSpoolUnlink(held.first)),
    );
  }

  /// The slot's RFID identity as the `link` body wants it. `tray_uuid` wins for
  /// the reason the server prefers it too: only the UUID survives a re-spool.
  /// Throws rather than returning null, so the precheck and the write refuse
  /// identically.
  Future<Map<String, String>> _requireSlotTag(
    SpoolAssignmentDraft draft,
  ) async {
    final status = await guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.printerStatus(draft.printerId),
      );
      return PrinterStatus.fromJson(res.data ?? const {});
    });
    if (status.connected == false) {
      throw const ApiException(AppErrorCode.printerOffline);
    }
    final tray = status.trayAt(amsId: draft.amsId, trayId: draft.trayId);
    if (_isLinkableTag(tray?.trayUuid)) {
      return {'tray_uuid': tray!.trayUuid!.trim()};
    }
    if (_isLinkableTag(tray?.tagUid)) return {'tag_uid': tray!.tagUid!.trim()};
    throw const ApiException(AppErrorCode.slotTagUnreadable);
  }

  /// Unlike the assignment routes this one mints a spool from what the slot
  /// already holds, and it answers with `{success, spool_id}` rather than the
  /// spool itself
  /// (`backend/app/api/routes/spoolman.py::create_spool_from_slot`).
  @override
  Future<int?> createSpoolFromSlot({
    required int printerId,
    required int amsId,
    required int trayId,
  }) => _guardKeeping404Detail(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      Endpoints.spoolmanSpoolFromSlot,
      data: {'printer_id': printerId, 'ams_id': amsId, 'tray_id': trayId},
    );
    return toIntOrNull(res.data?['spool_id']);
  });

  @override
  Future<List<SpoolUsageEntry>> fetchUsage(int spoolId) async => const [];

  @override
  Future<Spool> createSpool(SpoolDraft draft) => guard(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      Endpoints.spoolmanSpools,
      data: draft.toSpoolmanJson(),
    );
    return Spool.fromSpoolman(res.data ?? const {});
  });

  @override
  Future<int> bulkCreateSpools(SpoolDraft draft, int quantity) =>
      guard(() async {
        final res = await _dio.post<dynamic>(
          Endpoints.spoolmanSpoolsBulk,
          data: {'spool': draft.toSpoolmanJson(), 'quantity': quantity},
        );
        // 200 → JSON list of created spools; 207 → partial success object
        // `{created: [...], requested_count, failed_count, failures}`.
        final data = res.data;
        if (data is List) return data.length;
        if (data is Map && data['created'] is List) {
          return (data['created'] as List).length;
        }
        return 0;
      });

  @override
  Future<Spool> updateSpool(int spoolId, SpoolDraft draft) => guard(() async {
    final res = await _dio.patch<Map<String, dynamic>>(
      Endpoints.spoolmanSpool(spoolId),
      data: draft.toSpoolmanJson(),
    );
    return Spool.fromSpoolman(res.data ?? const {});
  });

  @override
  Future<void> deleteSpool(int spoolId) =>
      guard(() => _dio.delete<dynamic>(Endpoints.spoolmanSpool(spoolId)));

  @override
  Future<void> archiveSpool(int spoolId) =>
      guard(() => _dio.post<dynamic>(Endpoints.spoolmanSpoolArchive(spoolId)));

  @override
  Future<void> restoreSpool(int spoolId) =>
      guard(() => _dio.post<dynamic>(Endpoints.spoolmanSpoolRestore(spoolId)));

  @override
  Future<void> resetUsage(int spoolId) => _postWithLegacyFallback(
    _dio,
    Endpoints.spoolmanSpoolResetConsumedCounter(spoolId),
    Endpoints.spoolmanSpoolResetUsage(spoolId),
  );

  /// Spoolman's `update` is the narrower one: `category` and
  /// `low_stock_threshold_pct` have no column there, so an edit that touches
  /// only those reaches the backend as nothing to do.
  @override
  Future<BulkOutcome> bulkUpdate(List<int> spoolIds, SpoolBulkPatch patch) =>
      _postBulkUpdate(
        _dio,
        Endpoints.spoolmanSpoolsBulkUpdate,
        spoolIds,
        patch.toSpoolmanJson(),
      );

  // No `skippedKey` on either of these: Spoolman re-issues the archive/restore
  // call per spool and counts it as done whatever state the spool was in, so
  // there is no already-in-state list to read.
  @override
  Future<BulkOutcome> bulkArchive(List<int> spoolIds) => _postBulkIds(
    _dio,
    Endpoints.spoolmanSpoolsBulkArchive,
    spoolIds,
    okKey: 'archived',
  );

  @override
  Future<BulkOutcome> bulkRestore(List<int> spoolIds) => _postBulkIds(
    _dio,
    Endpoints.spoolmanSpoolsBulkRestore,
    spoolIds,
    okKey: 'restored',
  );

  @override
  Future<BulkOutcome> bulkDelete(List<int> spoolIds) => _postBulkIds(
    _dio,
    Endpoints.spoolmanSpoolsBulkDelete,
    spoolIds,
    okKey: 'deleted',
  );

  @override
  Future<BulkOutcome> bulkResetUsage(List<int> spoolIds) => _postBulkReset(
    _dio,
    Endpoints.spoolmanSpoolsResetConsumedCounterBulk,
    spoolIds,
  );

  // Reference data comes from native backend catalogs — on Spoolman, form uses
  // manual entry (empty lists).
  @override
  Future<List<CoreWeightEntry>> fetchCoreWeights() async => const [];

  @override
  Future<List<ColorEntry>> fetchColors() async => const [];

  @override
  Future<List<FilamentPreset>> fetchFilamentPresets() async => const [];

  // Location catalog is a native-backend feature; on Spoolman the picker falls
  // back to free text + locations already used by spools.
  @override
  Future<List<StorageLocation>> fetchLocations() async => const [];

  @override
  Future<Uint8List> renderLabels(SpoolLabelRequest request) =>
      _postLabels(_dio, Endpoints.spoolmanLabels, request);

  @override
  Future<List<SpoolPresetOverride>> fetchPresetOverrides(int spoolId) =>
      _getPresetOverrides(
        _dio,
        Endpoints.spoolmanSpoolFilamentPresets(spoolId),
      );

  @override
  Future<void> savePresetOverrides(
    int spoolId,
    List<SpoolPresetOverride> overrides,
  ) => _putPresetOverrides(
    _dio,
    Endpoints.spoolmanSpoolFilamentPresets(spoolId),
    overrides,
  );
}
