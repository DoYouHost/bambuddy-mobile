import 'dart:async';

import 'jwt.dart';

/// Timer factory — injectable so tests can control time flow instead of waiting
/// real clock hours.
typedef RefreshTimerFactory = Timer Function(Duration, void Function());

/// Proactive JWT refresh: schedules silent re-login just BEFORE token expiry,
/// instead of waiting for reactive 401 (which kills request/WS handshake and
/// causes brief error before interceptor retries). No refresh token on server
/// — we refresh with saved credentials (see [AuthService.silentReLogin]).
///
/// Pure logic (clock and timer injected) — testable without Riverpod and
/// plugins; used by both UI provider and foreground service isolate.
class ProactiveTokenRefresher {
  ProactiveTokenRefresher({
    required Future<String?> Function() readJwt,
    required Future<String?> Function() refresh,
    this.leadTime = const Duration(minutes: 5),
    this.minDelay = const Duration(seconds: 30),
    this.fallbackDelay = const Duration(hours: 6),
    DateTime Function()? clock,
    RefreshTimerFactory? timerFactory,
  })  :
        // Public parameter names + private fields — initializing formal
        // would require private parameter, so lint is unsatisfiable here.
        // ignore: prefer_initializing_formals
        _readJwt = readJwt,
        // ignore: prefer_initializing_formals
        _refresh = refresh,
        _now = clock ?? DateTime.now,
        _timerFactory = timerFactory ?? Timer.new;

  /// Read current JWT (to compute time until expiry).
  final Future<String?> Function() _readJwt;

  /// Silent re-login; returns fresh token (already stored) or `null` if failed
  /// or no saved credentials.
  final Future<String?> Function() _refresh;

  /// How far before expiry to refresh (margin for clock/network).
  final Duration leadTime;

  /// Minimum delay floor — protects against instant retry loop when token
  /// already expired and we just started.
  final Duration minDelay;

  /// If `exp` can't be read from token or refresh failed: retry after this
  /// (reactive 401 is still the safety net).
  final Duration fallbackDelay;

  final DateTime Function() _now;
  final RefreshTimerFactory _timerFactory;

  Timer? _timer;
  bool _running = false;

  /// Invalidates stale async steps after [stop]/restart.
  int _generation = 0;

  /// Start schedule (idempotent). Schedules first refresh based on
  /// CURRENT token expiry.
  void start() {
    if (_running) return;
    _running = true;
    final generation = ++_generation;
    unawaited(_schedule(generation));
  }

  /// Stop schedule (e.g., app in background — FGS isolate takes over).
  void stop() {
    _running = false;
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _schedule(int generation) async {
    final token = await _readJwt();
    if (!_running || generation != _generation) return;
    _armTimer(_delayFor(token), generation);
  }

  void _armTimer(Duration delay, int generation) {
    _timer?.cancel();
    _timer = _timerFactory(delay, () => unawaited(_fire(generation)));
  }

  Duration _delayFor(String? token) {
    final exp = jwtExpiry(token);
    if (exp == null) return fallbackDelay;
    final delay = exp.difference(_now()) - leadTime;
    return delay < minDelay ? minDelay : delay;
  }

  Future<void> _fire(int generation) async {
    if (!_running || generation != _generation) return;
    final fresh = await _refresh();
    if (!_running || generation != _generation) return;
    // Success → schedule per new token; failure → fallback (don't spin on
    // expired token every [minDelay], reactive 401 will catch it).
    _armTimer(fresh != null ? _delayFor(fresh) : fallbackDelay, generation);
  }
}
