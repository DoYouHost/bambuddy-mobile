import 'package:app_util/app_util.dart';
import 'package:dio/dio.dart';

import '../core/api/endpoints.dart';
import '../core/api/observed_capability.dart';
import '../core/api/server_version.dart';
import '../core/api/server_version_service.dart';
import '../core/models/inventory.dart';
import '../core/models/supplier.dart';
import 'inventory_source.dart';

/// Filament suppliers (server #2988): the master list, each spool's
/// assignments to it, and the per-supplier aggregate for the statistics.
///
/// Apart from [InventoryRepository] because the master list is one route
/// family whichever inventory is live — only [saveSpoolLinks] differs by
/// backend, and it takes that as an argument rather than a second source.
class SuppliersRepository {
  SuppliersRepository(this._dio, [this._serverVersion]);

  final Dio _dio;

  /// Answers [capability] until a listing or a spool row has.
  final ServerVersionService? _serverVersion;

  /// Whether the server has suppliers at all.
  late final capability = ObservedCapability(
    ServerFeature.spoolSuppliers,
    _serverVersion,
  );

  /// Settles [capability] from a spool listing: `SpoolResponse` defaults
  /// `suppliers` on every row from the feature on, and so does the Spoolman
  /// listing. An empty inventory says nothing either way.
  void observeSpools(List<Spool> spools) {
    final first = spools.firstOrNull;
    if (first != null) capability.observe(present: first.suppliers != null);
  }

  /// The master list, sorted case-insensitively by the server. A 404 or a 403
  /// answers with an empty list: every surface built on it is additive, and
  /// the latch has recorded why there is nothing to add.
  Future<List<Supplier>> listSuppliers() => capability.watching(
    () async {
      final res = await _dio.get<List<dynamic>>(Endpoints.inventorySuppliers);
      return parseJsonList(res.data, Supplier.fromJson);
    },
    absent: () => const [],
    observing: treat404AsAbsent,
  );

  /// A 409 is a name already taken, case-insensitively.
  Future<Supplier> createSupplier(SupplierDraft draft) =>
      capability.watching(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.inventorySuppliers,
          data: draft.toJson(),
        );
        return Supplier.fromJson(res.data ?? const {});
      });

  /// A 409 is a rename onto a name already taken; a 404 is the row gone.
  Future<Supplier> updateSupplier(int supplierId, SupplierDraft draft) =>
      capability.watching(() async {
        final res = await _dio.patch<Map<String, dynamic>>(
          Endpoints.inventorySupplier(supplierId),
          data: draft.toJson(),
        );
        return Supplier.fromJson(res.data ?? const {});
      });

  /// A 409 is a supplier still assigned to a spool: the server refuses rather
  /// than orphan the links.
  Future<void> deleteSupplier(int supplierId) => capability.watching(
    () => _dio.delete<dynamic>(Endpoints.inventorySupplier(supplierId)),
  );

  /// Replaces every assignment on [spoolId] — an empty list clears them. The
  /// route has no merge, so a caller must write back what it read.
  Future<void> saveSpoolLinks(
    int spoolId,
    List<SpoolSupplierLink> links, {
    required InventoryBackend backend,
  }) => capability.watching(
    () => _dio.put<dynamic>(
      switch (backend) {
        InventoryBackend.native => Endpoints.inventorySpoolSuppliers(spoolId),
        InventoryBackend.spoolman => Endpoints.spoolmanSpoolSuppliers(spoolId),
      },
      data: [for (final link in links) link.toJson()],
    ),
  );

  /// Stock and spend per purchase-source supplier; [from]/[to] are inclusive
  /// calendar days and narrow only the consumption and cost.
  Future<List<SupplierStats>> fetchStats({DateTime? from, DateTime? to}) =>
      capability.watching(
        () async {
          final res = await _dio.get<List<dynamic>>(
            Endpoints.inventorySupplierStats,
            queryParameters: {
              if (from != null) 'date_from': calendarDateToJson(from),
              if (to != null) 'date_to': calendarDateToJson(to),
            },
          );
          return parseJsonList(res.data, SupplierStats.fromJson);
        },
        absent: () => const [],
        observing: treat404AsAbsent,
      );
}
