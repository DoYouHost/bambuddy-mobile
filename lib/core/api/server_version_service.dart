import 'package:dio/dio.dart';

import 'endpoints.dart';
import 'server_version.dart';

/// Reads and caches the connected server's version.
///
/// Two callers, both of which have to work before anything is known: the queue
/// write path asks whether the server can store a tri-state calibration option
/// (see [CalibrationOption]), and the bug-report recorder stamps the version into
/// the log header — the one line that would have turned the queue-enum diagnosis
/// (`docs/plans/07-queue-cali-enum.md`) from a day of guessing into a lookup.
///
/// Never throws. An unreachable or unrecognisable server reads as "version
/// unknown", and every caller treats unknown as the older, more conservative
/// contract.
class ServerVersionService {
  ServerVersionService(this._dio);

  final Dio _dio;

  /// A version, once read, is treated as fixed: the server would have to restart
  /// to change it, which drops our connection anyway. A failed read is retried
  /// after [_retryAfter] rather than remembered forever — a probe that happened
  /// to run while the network was down must not disable `auto` for the whole
  /// session.
  static const _retryAfter = Duration(minutes: 5);

  ServerVersion? _version;
  DateTime? _failedAt;
  Future<ServerVersion?>? _pending;

  /// Last successfully read version without touching the network — for callers
  /// on a synchronous path (a `build`). `null` means "not read yet", which is not
  /// the same as "old server"; prefer [current] where an await is possible.
  ServerVersion? get cached => _version;

  /// The server's version, reading it once and reusing it afterwards.
  /// Concurrent callers share one in-flight request.
  Future<ServerVersion?> current() async {
    final known = _version;
    if (known != null) return known;

    final failedAt = _failedAt;
    if (failedAt != null &&
        DateTime.now().difference(failedAt) < _retryAfter) {
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

  /// Whether the server stores `bed_levelling` / `flow_cali` /
  /// `nozzle_offset_cali` as `off` / `on` / `auto`. Unknown → `false`, so we send
  /// the boolean form every server version accepts.
  Future<bool> supportsTriStateCalibration() async =>
      (await current())?.supportsTriStateCalibration ?? false;

  /// The raw version string for the diagnostic log header, or `null` when it
  /// could not be read.
  Future<String?> reportedVersion() async => (await current())?.raw;

  Future<ServerVersion?> _read() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(Endpoints.updatesVersion);
      final parsed = ServerVersion.tryParse(res.data?['version'] as String?);
      if (parsed == null) {
        // Reached the server but got something we cannot read — a proxy's error
        // page, or a future numbering scheme. Retry later rather than never.
        _failedAt = DateTime.now();
        return null;
      }
      _version = parsed;
      _failedAt = null;
      return parsed;
    } on Object {
      // Includes the 404 an older server would give if this route ever moves:
      // no version is a usable answer, an exception on the queue save path is
      // not.
      _failedAt = DateTime.now();
      return null;
    }
  }
}
