import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/supplier.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/data/suppliers_repository.dart';
import 'package:dio/dio.dart';

/// A server's supplier routes held in memory, recording every write the
/// screens send. [supported] settles the gate the way a listing would.
class FakeSuppliers extends SuppliersRepository {
  FakeSuppliers({
    List<Supplier> suppliers = const [],
    this.stats = const [],
    bool supported = true,
  }) : suppliers = [...suppliers],
       super(Dio()) {
    capability.observe(present: supported);
  }

  final List<Supplier> suppliers;
  final List<SupplierStats> stats;

  /// Thrown by the next write instead of applying it.
  AppApiException? failNextWrite;

  final created = <SupplierDraft>[];
  final updated = <(int, SupplierDraft)>[];
  final deleted = <int>[];
  final savedLinks = <(int, List<SpoolSupplierLink>, InventoryBackend)>[];
  final statsAsked = <(DateTime?, DateTime?)>[];

  void _maybeFail() {
    final failure = failNextWrite;
    failNextWrite = null;
    if (failure != null) throw failure;
  }

  @override
  Future<List<Supplier>> listSuppliers() async => List.of(suppliers);

  @override
  Future<Supplier> createSupplier(SupplierDraft draft) async {
    _maybeFail();
    created.add(draft);
    final row = Supplier(id: 100 + created.length, name: draft.name);
    suppliers.add(row);
    return row;
  }

  @override
  Future<Supplier> updateSupplier(int supplierId, SupplierDraft draft) async {
    _maybeFail();
    updated.add((supplierId, draft));
    return Supplier(id: supplierId, name: draft.name);
  }

  @override
  Future<void> deleteSupplier(int supplierId) async {
    _maybeFail();
    deleted.add(supplierId);
    suppliers.removeWhere((s) => s.id == supplierId);
  }

  @override
  Future<void> saveSpoolLinks(
    int spoolId,
    List<SpoolSupplierLink> links, {
    required InventoryBackend backend,
  }) async {
    _maybeFail();
    savedLinks.add((spoolId, links, backend));
  }

  @override
  Future<List<SupplierStats>> fetchStats({DateTime? from, DateTime? to}) async {
    statsAsked.add((from, to));
    return stats;
  }
}

/// A 409 as the supplier routes send it.
const conflict = ApiException(AppErrorCode.badResponse, statusCode: 409);
