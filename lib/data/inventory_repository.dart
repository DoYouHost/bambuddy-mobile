import '../core/models/inventory.dart';
import 'inventory_source.dart';

/// Fasada magazynu filamentów nad wybranym [SpoolInventorySource]. Cienka
/// warstwa: ujednolica API dla providerów i jest punktem rozszerzenia na zapisy
/// (Faza 2). Wybór backendu (natywny/Spoolman) zapada w providerze, który tu
/// wstrzykuje gotowe źródło.
class InventoryRepository {
  InventoryRepository(this._source);

  final SpoolInventorySource _source;

  Future<List<Spool>> fetchSpools({bool includeArchived = false}) =>
      _source.fetchSpools(includeArchived: includeArchived);

  Future<List<SpoolAssignment>> fetchAssignments() =>
      _source.fetchAssignments();

  Future<List<SpoolUsageEntry>> fetchUsage(int spoolId) =>
      _source.fetchUsage(spoolId);
}
