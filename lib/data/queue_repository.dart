import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/json_utils.dart';
import '../core/models/queue_item.dart';

/// REST data source for print queue (M5).
///
/// Auth adds [AuthInterceptor] to the shared Dio.
/// Each method maps [DioException] to [AppApiException].
class QueueRepository {
  QueueRepository(this._dio);

  final Dio _dio;

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
    return parseJsonList(body, QueueItem.fromJson);
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

  /// POST /queue/{id}/start — manually start item.
  Future<void> start(int itemId) =>
      guard(() => _dio.post<dynamic>(Endpoints.queueItemStart(itemId)));

  /// POST /queue/{id}/cancel — cancel queue item.
  Future<void> cancel(int itemId) =>
      guard(() => _dio.post<dynamic>(Endpoints.queueItemCancel(itemId)));

  /// POST /queue/ — add new item from archive.
  ///
  /// Body: `{"archive_id": .., "printer_id": .., "quantity": ..}`;
  /// `printer_id` omitted if null. [insertAtTop] jumps ahead of other pending
  /// items in the same printer scope — used by "reprint" to print next
  /// (the backend removed the direct `/reprint` endpoint; it's a queue item now).
  Future<void> addFromArchive(
    int archiveId, {
    int? printerId,
    int quantity = 1,
    bool insertAtTop = false,
  }) {
    final body = <String, dynamic>{
      'archive_id': archiveId,
      'printer_id': printerId,
      'quantity': quantity,
      if (insertAtTop) 'insert_at_top': true,
    }..removeWhere((_, v) => v == null);
    return guard(() => _dio.post<dynamic>(Endpoints.queue, data: body));
  }
}
