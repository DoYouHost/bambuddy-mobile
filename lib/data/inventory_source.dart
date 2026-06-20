import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/inventory.dart';

/// Backend magazynu filamentów. User korzysta z natywnego, ale aplikacja ma
/// działać też na Spoolman — wybór przez ustawienie (patrz `inventoryBackendProvider`).
enum InventoryBackend { native, spoolman }

/// Wspólny interfejs źródła danych magazynu — UI i providery nie wiedzą, który
/// backend działa (wzorzec swap-owalny jak `BackgroundMonitor`). Każda
/// implementacja mapuje surowy JSON swojego API do znormalizowanych modeli.
///
/// Na razie tylko odczyt (Faza 1); zapisy (CRUD, przypisania) dojdą w Fazie 2.
abstract class SpoolInventorySource {
  /// Wszystkie szpule. `includeArchived` dokłada zarchiwizowane.
  Future<List<Spool>> fetchSpools({bool includeArchived = false});

  /// Przypisania szpul do slotów AMS (do pokazania, gdzie szpula siedzi).
  Future<List<SpoolAssignment>> fetchAssignments();

  /// Historia zużycia jednej szpuli (ładowana na żądanie w szczegółach).
  Future<List<SpoolUsageEntry>> fetchUsage(int spoolId);
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
  Future<List<SpoolUsageEntry>> fetchUsage(int spoolId) async {
    try {
      final res = await _dio
          .get<List<dynamic>>(Endpoints.inventorySpoolUsage(spoolId));
      return _parseList(res.data ?? const [], SpoolUsageEntry.fromNative);
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

  @override
  Future<List<SpoolUsageEntry>> fetchUsage(int spoolId) async => const [];
}
