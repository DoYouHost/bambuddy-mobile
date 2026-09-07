import 'package:clock/clock.dart';
import 'package:dio/dio.dart';

import 'endpoints.dart';
import 'server_version.dart';

/// Reads and caches the connected server's version, for the queue write path
/// (which needs to know whether tri-state calibration can be stored) and the
/// bug-report log header — the one line that would have turned the queue-enum
/// diagnosis (`docs/plans/07-queue-cali-enum.md`) into a lookup.
///
/// Never throws: an unreachable or unrecognisable server reads as unknown, and
/// every caller treats unknown as the older, more conservative contract.
class ServerVersionService {
  ServerVersionService(this._dio);

  final Dio _dio;

  /// A read that failed is retried rather than remembered forever: a probe that
  /// ran while the network was down must not disable `auto` for the session. A
  /// *successful* read is fixed — the server would have to restart to change
  /// it, which drops our connection anyway.
  static const _retryAfter = Duration(minutes: 5);

  ServerVersion? _version;
  DateTime? _failedAt;
  Future<ServerVersion?>? _pending;

  /// For callers on a synchronous path, a `build`. `null` means "not read yet",
  /// which is not "old server" — prefer [current] wherever an await is possible.
  ServerVersion? get cached => _version;

  /// Concurrent callers share one in-flight request.
  Future<ServerVersion?> current() async {
    final known = _version;
    if (known != null) return known;

    final failedAt = _failedAt;
    if (failedAt != null && clock.now().difference(failedAt) < _retryAfter) {
      return null;
    }

    final pending = _pending;
    if (pending != null) return pending;
    final future = _read();
    _pending = future;
    try {
      return await future;
    } finally {
      _pending = null;
    }
  }

  /// Whether the connected server has [feature], per
  /// [ServerVersion.introducedIn].
  ///
  /// Unknown → `false` for every feature, which is always the older contract: a
  /// hidden control costs a new-server user one feature until the version read
  /// lands, while a shown one costs an old-server user a 422 — or, for the
  /// slice fields, a switch that silently does nothing.
  Future<bool> supports(ServerFeature feature) async =>
      (await current())?.supports(feature) ?? false;

  /// Unknown → 60, the ceiling every server generation accepts. See
  /// [ServerVersion.chamberMaxTargetC] for why this one cannot be observed.
  Future<int> chamberMaxTargetC() async =>
      (await current())?.chamberMaxTargetC ?? 60;

  Future<String?> reportedVersion() async => (await current())?.raw;

  Future<ServerVersion?> _read() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.updatesVersion,
      );
      final parsed = ServerVersion.tryParse(res.data?['version'] as String?);
      if (parsed == null) {
        // Reached the server but got a proxy's error page, or a numbering
        // scheme from the future. Retry later rather than never.
        _failedAt = clock.now();
        return null;
      }
      _version = parsed;
      _failedAt = null;
      return parsed;
    } on Object {
      // Including a 404: no version is a usable answer, an exception on the
      // queue save path is not.
      _failedAt = clock.now();
      return null;
    }
  }
}
