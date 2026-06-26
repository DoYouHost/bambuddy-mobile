import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
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
    final List<dynamic> body;
    try {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.queue,
        queryParameters: query.isNotEmpty ? query : null,
      );
      body = res.data ?? const [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
    final items = <QueueItem>[];
    for (final item in body) {
      if (item is! Map<String, dynamic>) continue;
      try {
        items.add(QueueItem.fromJson(item));
      } on Object {
        continue;
      }
    }
    return items;
  }

  /// POST /queue/reorder — change element order.
  ///
  /// Body: `{"items": [{"id": .., "position": ..}, ...]}`.
  Future<void> reorder(List<({int id, int position})> items) async {
    final body = {
      'items': [
        for (final it in items) {'id': it.id, 'position': it.position},
      ],
    };
    try {
      await _dio.post<dynamic>(Endpoints.queueReorder, data: body);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// DELETE /queue/{id} — delete item from queue.
  Future<void> delete(int itemId) async {
    try {
      await _dio.delete<dynamic>(Endpoints.queueItem(itemId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// PATCH /queue/{id} — assign printer to item (before start).
  /// Body: `{"printer_id": ..}`.
  Future<void> assignPrinter(int itemId, int printerId) async {
    try {
      await _dio.patch<dynamic>(
        Endpoints.queueItem(itemId),
        data: {'printer_id': printerId},
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// POST /queue/{id}/start — manually start item.
  Future<void> start(int itemId) async {
    try {
      await _dio.post<dynamic>(Endpoints.queueItemStart(itemId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// POST /queue/{id}/cancel — cancel queue item.
  Future<void> cancel(int itemId) async {
    try {
      await _dio.post<dynamic>(Endpoints.queueItemCancel(itemId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// POST /queue/ — add new item from archive.
  ///
  /// Body: `{"archive_id": .., "printer_id": .., "quantity": ..}`;
  /// `printer_id` omitted if null.
  Future<void> addFromArchive(
    int archiveId, {
    int? printerId,
    int quantity = 1,
  }) async {
    final body = <String, dynamic>{
      'archive_id': archiveId,
      'printer_id': printerId,
      'quantity': quantity,
    }..removeWhere((_, v) => v == null);
    try {
      await _dio.post<dynamic>(Endpoints.queue, data: body);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
