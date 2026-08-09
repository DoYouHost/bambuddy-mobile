import 'dart:async';

/// Injectable so tests can drive the schedule without waiting clock hours.
typedef RefreshTimerFactory = Timer Function(Duration, void Function());

/// Re-mints a token just *before* it expires, rather than waiting for a 401 —
/// which kills the request or WS handshake that hit it and shows as a brief
/// error before the interceptor retries.
///
/// Expiry-agnostic: both callbacks answer with a [DateTime], so the same
/// machinery drives the login JWT (expiry parsed out of the token) and the
/// camera token (a server-side TTL). The server issues no refresh token, so the
/// JWT path re-mints with the saved credentials — `AuthService.silentReLogin`.
///
/// Clock and timer are injected, so this runs in the foreground-service isolate
/// as readily as under Riverpod.
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
        // An initializing formal would need a private parameter name, so the
        // lint cannot be satisfied while the fields stay private.
        // ignore: prefer_initializing_formals
        _readExpiry = readExpiry,
        // ignore: prefer_initializing_formals
        _refresh = refresh,
        _now = clock ?? DateTime.now,
        _timerFactory = timerFactory ?? Timer.new;

  /// `null` when the expiry cannot be read.
  final Future<DateTime?> Function() _readExpiry;

  /// The fresh expiry, or `null` when the refresh failed.
  final Future<DateTime?> Function() _refresh;

  /// Margin for clock skew and a slow network.
  final Duration leadTime;

  /// Floor, so an already-expired token cannot spin the timer.
  final Duration minDelay;

  /// Used whenever the next expiry is unknown; a reactive 401 remains the
  /// safety net underneath all of this.
  final Duration fallbackDelay;

  final DateTime Function() _now;
  final RefreshTimerFactory _timerFactory;

  Timer? _timer;
  bool _running = false;

  /// Invalidates async steps left in flight by a [stop] or a restart.
  int _generation = 0;

  /// Idempotent.
  void start() {
    if (_running) return;
    _running = true;
    final generation = ++_generation;
    unawaited(_schedule(generation));
  }

  /// Called when the app goes to the background and the FGS isolate takes over.
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
    _armTimer(
        freshExpiry != null ? _delayFor(freshExpiry) : fallbackDelay,
        generation);
  }
}
