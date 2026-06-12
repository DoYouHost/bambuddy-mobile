import 'package:dio/dio.dart';

import 'api_exceptions.dart';
import 'endpoints.dart';

/// Mint i cache tokenu strumienia kamery (`POST /printers/camera/stream-token`).
///
/// Token jest wspólny dla serwera, ważny ~60 min i wymagany jako `?token=`
/// przy pobieraniu okładki wydruku (`cover_url`). To zalążek pod M2: ten sam
/// token autoryzuje strumień MJPEG i snapshot kamery — wtedy dojdzie
/// proaktywne odświeżanie (~50. min) i reakcja na kod zamknięcia 4401.
class CameraTokenService {
  CameraTokenService(this._dio);

  final Dio _dio;

  /// Konserwatywnie krócej niż serwerowe 60 min, żeby token nie wygasł
  /// w trakcie użycia.
  static const _ttl = Duration(minutes: 55);

  String? _token;
  DateTime? _expiresAt;

  /// Zwraca ważny token; mintuje nowy, gdy brak lub po wygaśnięciu (albo
  /// gdy [forceRefresh], np. po odpowiedzi 401 z zasobu chronionego tokenem).
  Future<String> token({bool forceRefresh = false}) async {
    final cached = _token;
    final expiry = _expiresAt;
    if (!forceRefresh &&
        cached != null &&
        expiry != null &&
        DateTime.now().isBefore(expiry)) {
      return cached;
    }

    final Response<Map<String, dynamic>> res;
    try {
      res = await _dio.post<Map<String, dynamic>>(Endpoints.cameraStreamToken);
    } on DioException catch (e) {
      throw mapDioException(e);
    }

    final token = res.data?['token'];
    if (token is! String || token.isEmpty) {
      throw const ApiException(AppErrorCode.malformedResponse);
    }
    _token = token;
    _expiresAt = DateTime.now().add(_ttl);
    return token;
  }

  /// Wymusza ponowny mint przy następnym [token] (np. po 401).
  void invalidate() {
    _token = null;
    _expiresAt = null;
  }
}
