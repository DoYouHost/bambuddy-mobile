import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/archive_slim.dart';
import '../core/models/archive_stats.dart';
import '../core/models/failure_analysis.dart';

/// REST-owe źródło statystyk archiwum (`GET /archives/stats`).
///
/// Auth dokłada [AuthInterceptor] na współdzielonym Dio. [DioException]
/// mapujemy na [AppApiException]; parsowanie odpowiedzi jest defensywne
/// (patrz [ArchiveStats.fromJson]).
class StatsRepository {
  StatsRepository(this._dio);

  final Dio _dio;

  /// Rozmiar strony przy pobieraniu lekkiej listy.
  static const _pageSize = 500;

  /// Twardy limit pobranych wpisów (bezpiecznik na patologicznie duże archiwa).
  static const _maxSlim = 10000;

  /// Pobiera statystyki dla opcjonalnego zakresu dat i autora.
  ///
  /// [from]/[to] wysyłamy jako `YYYY-MM-DD` (włącznie). [createdById] filtruje
  /// po autorze wydruku (`-1` = bez przypisanego użytkownika); `null` pomija
  /// filtr.
  Future<ArchiveStats> fetch({
    DateTime? from,
    DateTime? to,
    int? createdById,
  }) async {
    final query = <String, dynamic>{
      'date_from': _ymd(from),
      'date_to': _ymd(to),
      'created_by_id': createdById,
    }..removeWhere((_, v) => v == null);
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.archivesStats,
        queryParameters: query,
      );
      return ArchiveStats.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// Pobiera pełną listę lekkich wpisów dla zakresu (paginując po [_pageSize]
  /// aż serwer zwróci niepełną stronę). Używana do liczenia bogatych statystyk
  /// po stronie klienta. Zwykle archiwum to setki wpisów, nie miliony.
  Future<List<ArchiveSlim>> fetchSlim({
    DateTime? from,
    DateTime? to,
    int? createdById,
  }) async {
    final out = <ArchiveSlim>[];
    var offset = 0;
    while (true) {
      final query = <String, dynamic>{
        'date_from': _ymd(from),
        'date_to': _ymd(to),
        'created_by_id': createdById,
        'limit': _pageSize,
        'offset': offset,
      }..removeWhere((_, v) => v == null);
      final List<dynamic> body;
      try {
        final res = await _dio.get<List<dynamic>>(
          Endpoints.archivesSlim,
          queryParameters: query,
        );
        body = res.data ?? const [];
      } on DioException catch (e) {
        throw mapDioException(e);
      }
      for (final item in body) {
        if (item is! Map<String, dynamic>) continue;
        try {
          out.add(ArchiveSlim.fromJson(item));
        } on Object {
          continue; // pojedynczy niesparsowalny wpis nie psuje całości
        }
      }
      if (body.length < _pageSize) break;
      offset += _pageSize;
      if (offset >= _maxSlim) break; // bezpiecznik na patologiczne archiwa
    }
    return out;
  }

  /// Pobiera analizę niepowodzeń. Podaj [days] (ostatnie N dni) ALBO zakres
  /// [from]/[to]. Odpowiedź bez zadeklarowanego schematu — parsujemy defensywnie.
  Future<FailureAnalysis> fetchFailures({
    int? days,
    DateTime? from,
    DateTime? to,
    int? createdById,
  }) async {
    final query = <String, dynamic>{
      'days': days,
      'date_from': _ymd(from),
      'date_to': _ymd(to),
      'created_by_id': createdById,
    }..removeWhere((_, v) => v == null);
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.archivesFailures,
        queryParameters: query,
      );
      return FailureAnalysis.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// Formatuje datę jako `YYYY-MM-DD` (bez strefy/czasu) — kontrakt serwera.
  static String? _ymd(DateTime? d) {
    if (d == null) return null;
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }
}
