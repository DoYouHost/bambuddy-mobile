import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/discovery.dart';

/// Network discovery for the Add-Printer flow: environment info, subnet scan,
/// and the list of printers found so far. All endpoints require the
/// `DISCOVERY_SCAN` permission (missing → [AuthException] forbidden).
class DiscoveryRepository {
  DiscoveryRepository(this._dio);

  final Dio _dio;

  Future<DiscoveryInfo> info() => guard(() async {
    final res = await _dio.get<Map<String, dynamic>>(Endpoints.discoveryInfo);
    return DiscoveryInfo.fromJson(res.data ?? const {});
  });

  /// Start a background subnet scan; poll [scanStatus] until `running` is false.
  Future<ScanStatus> startScan(String subnet, {double timeout = 1.0}) =>
      guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.discoveryScan,
          data: {'subnet': subnet, 'timeout': timeout},
        );
        return ScanStatus.fromJson(res.data ?? const {});
      });

  Future<ScanStatus> scanStatus() => guard(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      Endpoints.discoveryScanStatus,
    );
    return ScanStatus.fromJson(res.data ?? const {});
  });

  /// Start SSDP multicast discovery (native installs). Poll [discoveredPrinters]
  /// and call [stopSsdp] when done.
  Future<void> startSsdp({double duration = 10.0}) => guard(() async {
    await _dio.post<Map<String, dynamic>>(
      Endpoints.discoveryStart,
      queryParameters: {'duration': duration},
    );
  });

  Future<void> stopSsdp() => guard(() async {
    await _dio.post<Map<String, dynamic>>(Endpoints.discoveryStop);
  });

  Future<List<DiscoveredPrinter>> discoveredPrinters() => guard(() async {
    final res = await _dio.get<List<dynamic>>(Endpoints.discoveryPrinters);
    return [
      for (final e in res.data ?? const [])
        if (e is Map) DiscoveredPrinter.fromJson(Map<String, dynamic>.from(e)),
    ];
  });
}
