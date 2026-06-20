import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/firmware.dart';

/// REST-owe źródło danych o firmware drukarek.
///
/// Dziś używane są tylko odczyty ([fetchUpdates]/[fetchForPrinter]) — pokazanie
/// wersji i flagi „dostępna aktualizacja". Metody wykonania ([prepareUpload]/
/// [startUpload]/[uploadStatus]) są już gotowe (typowane), by przyszły flow
/// aktualizacji wpiąć bez ruszania warstwy danych.
///
/// Auth dokłada [AuthInterceptor] na współdzielonym Dio. Parsowanie defensywne;
/// odczyt pojedynczej drukarki degraduje się do `null` przy błędach innych niż
/// auth — brak danych firmware nie może wywrócić karty.
class FirmwareRepository {
  FirmwareRepository(this._dio);

  final Dio _dio;

  /// `GET /firmware/updates` — firmware całej farmy jednym zapytaniem.
  Future<FirmwareUpdatesResponse> fetchUpdates() async {
    try {
      final res =
          await _dio.get<Map<String, dynamic>>(Endpoints.firmwareUpdates);
      return FirmwareUpdatesResponse.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// `GET /firmware/updates/{id}` — firmware jednej drukarki. Auth wypływa
  /// (UI → /setup); reszta degraduje się do `null`.
  Future<FirmwareUpdateInfo?> fetchForPrinter(int printerId) async {
    try {
      final res = await _dio
          .get<Map<String, dynamic>>(Endpoints.firmwareUpdate(printerId));
      final body = res.data;
      return body == null ? null : FirmwareUpdateInfo.fromJson(body);
    } on DioException catch (e) {
      final mapped = mapDioException(e);
      if (mapped is AuthException) throw mapped;
      return null;
    } on Object {
      return null;
    }
  }

  // --- Wykonywanie aktualizacji (na przyszłość; jeszcze nieużywane w UI) ---

  /// `GET /firmware/updates/{id}/prepare` — sonda przed wgraniem firmware.
  Future<FirmwareUploadPrepare> prepareUpload(int printerId) async {
    try {
      final res = await _dio
          .get<Map<String, dynamic>>(Endpoints.firmwarePrepare(printerId));
      return FirmwareUploadPrepare.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// `POST /firmware/updates/{id}/upload` — start wgrywania. Opcjonalna
  /// `version` (gdy brak — serwer bierze najnowszą). 403 = klucz bez uprawnień.
  Future<FirmwareUploadStartResult> startUpload(
    int printerId, {
    String? version,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.firmwareUpload(printerId),
        queryParameters: {'version': ?version},
      );
      return FirmwareUploadStartResult.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// `GET /firmware/updates/{id}/upload/status` — postęp wgrywania.
  Future<FirmwareUploadStatus> uploadStatus(int printerId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.firmwareUploadStatus(printerId),
      );
      return FirmwareUploadStatus.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
