import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/dio_json.dart';
import '../core/api/endpoints.dart';
import '../core/models/ai_detection.dart';

/// What the server's AI failure detection says about the running prints, for
/// the printer cards. Read only: configuring a provider is the web's.
class AiDetectionRepository {
  AiDetectionRepository(this._dio);

  final Dio _dio;

  /// The provider that is switched on, chosen as the web chooses it
  /// (`aiPrinterStatus` in `PrintersPage.tsx`): OctoEverywhere when it is
  /// enabled, otherwise Obico. The server refuses to enable both.
  ///
  /// Null when the server has neither route (every release before Obico) or
  /// refuses this session both.
  Future<AiDetectionStatus?> fetch() async {
    final octoEverywhere = await _read(Endpoints.octoEverywherePrinterStatus);
    if (octoEverywhere != null && octoEverywhere.enabled) return octoEverywhere;
    return await _read(Endpoints.obicoPrinterStatus) ?? octoEverywhere;
  }

  /// Null for a server without the route (404) and a session it refuses (403).
  /// Neither handler looks up a row by id, so a 404 can only be the route.
  Future<AiDetectionStatus?> _read(String path) =>
      guardAbsent<AiDetectionStatus?>(
        () => _dio.getObject(path, AiDetectionStatus.fromJson),
        null,
        statuses: {404, 403},
      );
}
