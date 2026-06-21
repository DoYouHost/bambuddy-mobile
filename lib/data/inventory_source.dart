import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/inventory.dart';
import '../core/models/inventory_reference.dart';

/// Backend magazynu filamentów. User korzysta z natywnego, ale aplikacja ma
/// działać też na Spoolman — wybór przez ustawienie (patrz `inventoryBackendProvider`).
enum InventoryBackend { native, spoolman }

/// Wspólny interfejs źródła danych magazynu — UI i providery nie wiedzą, który
/// backend działa (wzorzec swap-owalny jak `BackgroundMonitor`). Każda
/// implementacja mapuje surowy JSON swojego API do znormalizowanych modeli.
///
/// Odczyt (Faza 1) + zarządzanie szpulami (Faza 2: create/update/delete/
/// archive/restore/reset-usage). Przypisania AMS i katalog dojdą później.
/// Zapisy wymagają uprawnienia na kluczu API (brak → [AuthException] forbidden).
abstract class SpoolInventorySource {
  /// Wszystkie szpule. `includeArchived` dokłada zarchiwizowane.
  Future<List<Spool>> fetchSpools({bool includeArchived = false});

  /// Przypisania szpul do slotów AMS (do pokazania, gdzie szpula siedzi).
  Future<List<SpoolAssignment>> fetchAssignments();

  /// Przypisuje szpulę do slotu (drukarka/jednostka AMS/taca).
  Future<void> assignSpool(SpoolAssignmentDraft draft);

  /// Odpina szpulę z danego slotu.
  Future<void> unassignSpool(int printerId, int amsId, int trayId);

  /// Historia zużycia jednej szpuli (ładowana na żądanie w szczegółach).
  Future<List<SpoolUsageEntry>> fetchUsage(int spoolId);

  /// Tworzy nową szpulę; zwraca utworzony, znormalizowany rekord.
  Future<Spool> createSpool(SpoolDraft draft);

  /// Aktualizuje pola szpuli; zwraca zaktualizowany rekord.
  Future<Spool> updateSpool(int spoolId, SpoolDraft draft);

  /// Trwale usuwa szpulę (nieodwracalne — UI potwierdza).
  Future<void> deleteSpool(int spoolId);

  /// Archiwizuje / przywraca szpulę (miękkie ukrycie z listy aktywnych).
  Future<void> archiveSpool(int spoolId);
  Future<void> restoreSpool(int spoolId);

  /// Zeruje zużycie szpuli (pełna ponownie).
  Future<void> resetUsage(int spoolId);

  /// Dane referencyjne formularza (katalog rdzeni, baza kolorów, profile
  /// filamentów). Degradują się do pustej listy — formularz dopuszcza wpis ręczny.
  Future<List<CoreWeightEntry>> fetchCoreWeights();
  Future<List<ColorEntry>> fetchColors();
  Future<List<FilamentPreset>> fetchFilamentPresets();
}

/// Defensywne parsowanie listy: pojedynczy niesparsowalny wpis pomijamy,
/// żeby jeden zły rekord nie wywrócił całego ekranu.
List<T> _parseList<T>(
  List<dynamic> body,
  T Function(Map<String, dynamic>) fromJson,
) {
  final out = <T>[];
  for (final item in body) {
    if (item is! Map<String, dynamic>) continue;
    try {
      out.add(fromJson(item));
    } on Object {
      continue;
    }
  }
  return out;
}

/// Natywny backend `/inventory/*` (domyślny). Auth dokłada wspólny
/// `AuthInterceptor`; błędy mapujemy do typowanych [AppApiException].
class NativeInventorySource implements SpoolInventorySource {
  NativeInventorySource(this._dio);

  final Dio _dio;

  @override
  Future<List<Spool>> fetchSpools({bool includeArchived = false}) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.inventorySpools,
        queryParameters: {'include_archived': includeArchived},
      );
      return _parseList(res.data ?? const [], Spool.fromNative);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<SpoolAssignment>> fetchAssignments() async {
    try {
      final res =
          await _dio.get<List<dynamic>>(Endpoints.inventoryAssignments);
      return _parseList(res.data ?? const [], SpoolAssignment.fromNative);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> assignSpool(SpoolAssignmentDraft draft) async {
    try {
      await _dio.post<dynamic>(
        Endpoints.inventoryAssignments,
        data: draft.toNativeJson(),
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> unassignSpool(int printerId, int amsId, int trayId) async {
    try {
      await _dio.delete<dynamic>(
        Endpoints.inventoryAssignment(printerId, amsId, trayId),
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<SpoolUsageEntry>> fetchUsage(int spoolId) async {
    try {
      final res = await _dio
          .get<List<dynamic>>(Endpoints.inventorySpoolUsage(spoolId));
      return _parseList(res.data ?? const [], SpoolUsageEntry.fromNative);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Spool> createSpool(SpoolDraft draft) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.inventorySpools,
        data: draft.toNativeJson(),
      );
      return Spool.fromNative(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Spool> updateSpool(int spoolId, SpoolDraft draft) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        Endpoints.inventorySpool(spoolId),
        data: draft.toNativeJson(),
      );
      return Spool.fromNative(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> deleteSpool(int spoolId) async {
    try {
      await _dio.delete<dynamic>(Endpoints.inventorySpool(spoolId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> archiveSpool(int spoolId) async {
    try {
      await _dio.post<dynamic>(Endpoints.inventorySpoolArchive(spoolId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> restoreSpool(int spoolId) async {
    try {
      await _dio.post<dynamic>(Endpoints.inventorySpoolRestore(spoolId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> resetUsage(int spoolId) async {
    try {
      await _dio.post<dynamic>(Endpoints.inventorySpoolResetUsage(spoolId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<CoreWeightEntry>> fetchCoreWeights() async {
    try {
      final res = await _dio.get<List<dynamic>>(Endpoints.inventoryCatalog);
      return _parseList(res.data ?? const [], CoreWeightEntry.fromJson);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<ColorEntry>> fetchColors() async {
    try {
      final res = await _dio.get<List<dynamic>>(Endpoints.inventoryColors);
      return _parseList(res.data ?? const [], ColorEntry.fromJson);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<FilamentPreset>> fetchFilamentPresets() async {
    try {
      final res = await _dio.get<List<dynamic>>(Endpoints.filamentCatalog);
      return _parseList(res.data ?? const [], FilamentPreset.fromJson);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}

/// Backend Spoolman `/spoolman/inventory/*`. Spoolman zwraca luźny passthrough,
/// więc mappery [Spool.fromSpoolman]/[SpoolAssignment.fromSpoolman] są bardziej
/// tolerancyjne. Historia zużycia nie ma stabilnego kształtu — na razie pusta.
class SpoolmanInventorySource implements SpoolInventorySource {
  SpoolmanInventorySource(this._dio);

  final Dio _dio;

  @override
  Future<List<Spool>> fetchSpools({bool includeArchived = false}) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.spoolmanSpools,
        queryParameters: {'include_archived': includeArchived},
      );
      return _parseList(res.data ?? const [], Spool.fromSpoolman);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<SpoolAssignment>> fetchAssignments() async {
    try {
      final res =
          await _dio.get<List<dynamic>>(Endpoints.spoolmanAssignments);
      return _parseList(res.data ?? const [], SpoolAssignment.fromSpoolman);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  // Spoolman zarządza przypisaniami slotów po swojej stronie — backend nie
  // wystawia tu zapisu. Domyślny backend usera to natywny; gdyby ktoś przełączył
  // na Spoolman, UI dostaje czytelny komunikat zamiast cichej awarii.
  @override
  Future<void> assignSpool(SpoolAssignmentDraft draft) async =>
      throw UnsupportedError('Spoolman backend does not support slot assignment');

  @override
  Future<void> unassignSpool(int printerId, int amsId, int trayId) async =>
      throw UnsupportedError('Spoolman backend does not support slot assignment');

  @override
  Future<List<SpoolUsageEntry>> fetchUsage(int spoolId) async => const [];

  @override
  Future<Spool> createSpool(SpoolDraft draft) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.spoolmanSpools,
        data: draft.toSpoolmanJson(),
      );
      return Spool.fromSpoolman(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Spool> updateSpool(int spoolId, SpoolDraft draft) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        Endpoints.spoolmanSpool(spoolId),
        data: draft.toSpoolmanJson(),
      );
      return Spool.fromSpoolman(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> deleteSpool(int spoolId) async {
    try {
      await _dio.delete<dynamic>(Endpoints.spoolmanSpool(spoolId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> archiveSpool(int spoolId) async {
    try {
      await _dio.post<dynamic>(Endpoints.spoolmanSpoolArchive(spoolId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> restoreSpool(int spoolId) async {
    try {
      await _dio.post<dynamic>(Endpoints.spoolmanSpoolRestore(spoolId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> resetUsage(int spoolId) async {
    try {
      await _dio.post<dynamic>(Endpoints.spoolmanSpoolResetUsage(spoolId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  // Dane referencyjne to katalogi natywnego backendu — przy Spoolmanie formularz
  // korzysta z wpisu ręcznego (puste listy).
  @override
  Future<List<CoreWeightEntry>> fetchCoreWeights() async => const [];

  @override
  Future<List<ColorEntry>> fetchColors() async => const [];

  @override
  Future<List<FilamentPreset>> fetchFilamentPresets() async => const [];
}
