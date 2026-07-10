import 'dart:async';

/// Timer factory — injectable so tests can control time flow instead of waiting
/// real clock hours.
typedef RefreshTimerFactory = Timer Function(Duration, void Function());

/// Proactive token refresh: schedules a re-mint just BEFORE token expiry,
/// instead of waiting for a reactive 401 (which kills a request/WS handshake
/// and causes a brief error before the interceptor retries).
///
/// Expiry-agnostic: [readExpiry]/[refresh] return the token's expiry as a
/// [DateTime], so the same machinery drives both the login JWT (expiry parsed
/// from the token) and the camera token (a TTL-based server token). No refresh
/// token on the server for JWT — that path refreshes with saved credentials
/// (see [AuthService.silentReLogin]).
///
/// Pure logic (clock and timer injected) — testable without Riverpod and
/// plugins; used by both UI providers and the foreground service isolate.
class ProactiveTokenRefresher {
  ProactiveTokenRefresher({
    required Future<DateTime?> Function() readExpiry,
    required Future<DateTime?> Function() refresh,
    this.leadTime = const Duration(minutes: 5),
    this.minDelay = const Duration(seconds: 30),
    this.fallbackDelay = const Duration(hours: 6),
    DateTime Function()? clock,
    RefreshTimerFactory? timerFactory,
  })  :
        // Public parameter names + private fields — initializing formal
        // would require private parameter, so lint is unsatisfiable here.
        // ignore: prefer_initializing_formals
        _readExpiry = readExpiry,
        // ignore: prefer_initializing_formals
        _refresh = refresh,
        _now = clock ?? DateTime.now,
        _timerFactory = timerFactory ?? Timer.new;

  /// Read the current token's expiry (to compute time until it lapses).
  /// `null` → expiry unknown, schedule [fallbackDelay].
  final Future<DateTime?> Function() _readExpiry;

  /// Perform the refresh; returns the fresh token's expiry, or `null` if the
  /// refresh failed (schedule [fallbackDelay] — reactive 401 is the safety net).
  final Future<DateTime?> Function() _refresh;

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
    final expiry = await _readExpiry();
    if (!_running || generation != _generation) return;
    _armTimer(_delayFor(expiry), generation);
  }

  void _armTimer(Duration delay, int generation) {
    _timer?.cancel();
    _timer = _timerFactory(delay, () => unawaited(_fire(generation)));
  }

  Duration _delayFor(DateTime? expiry) {
    if (expiry == null) return fallbackDelay;
    final delay = expiry.difference(_now()) - leadTime;
    return delay < minDelay ? minDelay : delay;
  }

  Future<void> _fire(int generation) async {
    if (!_running || generation != _generation) return;
    final freshExpiry = await _refresh();
    if (!_running || generation != _generation) return;
    // Success → schedule per new expiry; failure → fallback (don't spin on an
    // expired token every [minDelay], reactive 401 will catch it).
    _armTimer(
        freshExpiry != null ? _delayFor(freshExpiry) : fallbackDelay,
        generation);
  }
}
