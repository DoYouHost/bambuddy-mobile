import '../core/models/inventory.dart';
import '../core/models/inventory_reference.dart';
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

  Future<void> assignSpool(SpoolAssignmentDraft draft) =>
      _source.assignSpool(draft);

  Future<void> unassignSpool(int printerId, int amsId, int trayId) =>
      _source.unassignSpool(printerId, amsId, trayId);

  Future<List<SpoolUsageEntry>> fetchUsage(int spoolId) =>
      _source.fetchUsage(spoolId);

  Future<Spool> createSpool(SpoolDraft draft) => _source.createSpool(draft);

  Future<Spool> updateSpool(int spoolId, SpoolDraft draft) =>
      _source.updateSpool(spoolId, draft);

  Future<void> deleteSpool(int spoolId) => _source.deleteSpool(spoolId);

  Future<void> archiveSpool(int spoolId) => _source.archiveSpool(spoolId);

  Future<void> restoreSpool(int spoolId) => _source.restoreSpool(spoolId);

  Future<void> resetUsage(int spoolId) => _source.resetUsage(spoolId);

  Future<List<CoreWeightEntry>> fetchCoreWeights() => _source.fetchCoreWeights();

  Future<List<ColorEntry>> fetchColors() => _source.fetchColors();

  Future<List<FilamentPreset>> fetchFilamentPresets() =>
      _source.fetchFilamentPresets();
}
