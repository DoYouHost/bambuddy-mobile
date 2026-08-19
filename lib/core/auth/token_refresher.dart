import 'dart:async';

import '../diagnostics/auth_probe.dart';
import 'auth_service.dart';
import 'credentials_store.dart';
import 'jwt.dart';

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
    this.fallbackDelay = const Duration(hours: 2),
    Future<bool> Function()? canRetry,
    DateTime Function()? clock,
    RefreshTimerFactory? timerFactory,
  })  :
        // An initializing formal would need a private parameter name, so the
        // lint cannot be satisfied while the fields stay private.
        // ignore: prefer_initializing_formals
        _readExpiry = readExpiry,
        // ignore: prefer_initializing_formals
        _refresh = refresh,
        // ignore: prefer_initializing_formals
        _canRetry = canRetry,
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

  /// Whether a failed [_refresh] is worth repeating. A refusal ends the
  /// schedule: the two ways a refresh fails are "the network was in the way"
  /// and "the credentials this retries with are gone", and only the first one
  /// can be fixed by waking up later. `null` retries either way.
  final Future<bool> Function()? _canRetry;

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
    final DateTime? expiry;
    try {
      expiry = await _readExpiry();
    } on Object catch (error) {
      // Nothing awaits this, so an escaping error would leave the timer unarmed
      // for good while `_running` still says otherwise — and `start` is
      // idempotent, so nothing would ever arm it again. The keystore read throws
      // on some OEMs; fall back to the blind interval instead of going dark.
      AuthProbe.refreshStepFailed(error);
      if (!_running || generation != _generation) return;
      _armTimer(fallbackDelay, generation);
      return;
    }
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
    final DateTime? freshExpiry;
    try {
      freshExpiry = await _refresh();
    } on Object catch (error) {
      // Same reasoning as `_schedule`: a throw here would stop the schedule
      // dead. A thrown step says nothing about the credentials — unlike the
      // null below — so it always earns another try.
      AuthProbe.refreshStepFailed(error);
      if (!_running || generation != _generation) return;
      _armTimer(fallbackDelay, generation);
      return;
    }
    if (!_running || generation != _generation) return;
    if (freshExpiry != null) {
      _armTimer(_delayFor(freshExpiry), generation);
      return;
    }
    if (_canRetry != null) {
      final bool retry;
      try {
        retry = await _canRetry();
      } on Object catch (error) {
        // Reads the same store that can throw above. Ending the schedule is the
        // heavier mistake of the two, so an unanswered question keeps it alive.
        AuthProbe.refreshStepFailed(error);
        if (!_running || generation != _generation) return;
        _armTimer(fallbackDelay, generation);
        return;
      }
      if (!_running || generation != _generation) return;
      // Nothing left to retry with, so stop rather than repeat a login that
      // cannot succeed until the user signs in again — which restarts this.
      if (!retry) return stop();
    }
    _armTimer(fallbackDelay, generation);
  }
}

/// The JWT refresher both isolates run.
///
/// They renew the same session from the same saved login, so the wiring is the
/// same by necessity rather than by coincidence — and a difference between the
/// two would show up only as one of them quietly not renewing, which is the
/// hardest kind of difference to notice.
ProactiveTokenRefresher jwtTokenRefresher({
  required CredentialsStore credentials,
  required AuthService auth,
  required String baseUrl,
}) =>
    ProactiveTokenRefresher(
      readExpiry: () async => jwtExpiry(await credentials.readJwt()),
      refresh: () async => jwtExpiry(await auth.silentReLogin(baseUrl)),
      // `silentReLogin` clears the saved login only when the server rejected it,
      // so an empty store separates that from the network being in the way.
      canRetry: () async => await credentials.readRememberedLogin() != null,
    );
