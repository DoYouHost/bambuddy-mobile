import 'package:app_util/app_util.dart';
import 'package:clock/clock.dart';
import 'package:dio/dio.dart';

import 'endpoints.dart';
import 'server_version.dart';

/// Reads and caches the connected server's version, for the queue write path
/// (which needs to know whether tri-state calibration can be stored) and the
/// bug-report log header — the one line that would have turned the queue-enum
/// diagnosis into a lookup.
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

  /// What the server answered, verbatim, even when [ServerVersion.tryParse]
  /// made nothing of it. Displaying a numbering scheme this build has never
  /// seen beats displaying nothing, and the capability table stays out of it —
  /// that one keeps reading [_version], which such an answer leaves null.
  String? _rawVersion;

  DateTime? _failedAt;
  Future<ServerVersion?>? _pending;

  /// For callers on a synchronous path, a `build`. `null` means "not read yet",
  /// which is not "old server" — prefer [current] wherever an await is possible.
  ServerVersion? get cached => _version;

  /// [reportedVersion] for a synchronous path; `null` also means "not read
  /// yet". See [_rawVersion] for why this is not `cached?.raw`.
  String? get cachedRaw => _rawVersion;

  /// Lets the next [current] ask at once instead of waiting out [_retryAfter] —
  /// for when contact with the server has just been regained.
  void forgetFailure() => _failedAt = null;

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

  /// The server's own version string, for the bug-report header and the two
  /// screens that show it. `null` until a read succeeds, and after one that
  /// could not reach the server at all.
  Future<String?> reportedVersion() async {
    await current();
    return _rawVersion;
  }

  Future<ServerVersion?> _read() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        Endpoints.updatesVersion,
      );
      final raw = toStringOrNull(res.data?['version']);
      final parsed = ServerVersion.tryParse(raw);
      if (parsed == null) {
        // Still worth showing: only the version→capability comparison needs
        // the parse to have worked.
        _rawVersion = raw;
        // Reached the server but got a proxy's error page, or a numbering
        // scheme from the future. Retry later rather than never.
        _failedAt = clock.now();
        return null;
      }
      _version = parsed;
      _rawVersion = raw;
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
