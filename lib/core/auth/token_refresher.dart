import 'dart:async';

import 'jwt.dart';

/// Fabryka timera — wstrzykiwalna, by testy mogły sterować upływem czasu
/// zamiast czekać godzinami realnego zegara.
typedef RefreshTimerFactory = Timer Function(Duration, void Function());

/// Proaktywna odnowa JWT: planuje cichy re-login tuż PRZED wygaśnięciem tokenu,
/// zamiast czekać na reaktywne 401 (które ubija żądanie/handshake WS i daje
/// chwilowy błąd, zanim interceptor go ponowi). Brak refresh-tokena po stronie
/// serwera — odnawiamy zapamiętanymi poświadczeniami (patrz [AuthService.silentReLogin]).
///
/// Czysta logika (zegar i timer wstrzykiwane) — testowalna bez Riverpoda i
/// pluginów; używana zarówno przez provider UI, jak i isolate foreground service'u.
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
        // Publiczne nazwy parametrów + prywatne pola — initializing formal
        // wymagałby prywatnego parametru, więc lint jest tu niespełnialny.
        // ignore: prefer_initializing_formals
        _readJwt = readJwt,
        // ignore: prefer_initializing_formals
        _refresh = refresh,
        _now = clock ?? DateTime.now,
        _timerFactory = timerFactory ?? Timer.new;

  /// Odczyt bieżącego JWT (do wyliczenia, ile zostało do wygaśnięcia).
  final Future<String?> Function() _readJwt;

  /// Cichy re-login; zwraca świeży token (już zapisany w storage) albo `null`,
  /// gdy się nie powiódł / nie ma czym (brak zapamiętanych poświadczeń).
  final Future<String?> Function() _refresh;

  /// Ile przed wygaśnięciem odnawiać (margines na zegar/sieć).
  final Duration leadTime;

  /// Dolny limit opóźnienia — chroni przed pętlą natychmiastowych prób, gdy
  /// token już wygasł, a my dopiero startujemy.
  final Duration minDelay;

  /// Gdy nie da się odczytać `exp` z tokenu albo odnowa zawiodła: sprawdź
  /// ponownie po tym czasie (reaktywne 401 i tak pozostaje siatką bezpieczeństwa).
  final Duration fallbackDelay;

  final DateTime Function() _now;
  final RefreshTimerFactory _timerFactory;

  Timer? _timer;
  bool _running = false;

  /// Unieważnia spóźnione, asynchroniczne kroki po [stop]/restarcie.
  int _generation = 0;

  /// Uruchamia harmonogram (idempotentne). Planuje pierwszą odnowę na podstawie
  /// wygaśnięcia AKTUALNEGO tokenu.
  void start() {
    if (_running) return;
    _running = true;
    final generation = ++_generation;
    unawaited(_schedule(generation));
  }

  /// Zatrzymuje harmonogram (np. apka w tle — przejmuje isolate FGS).
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
    // Sukces → planuj wg nowego tokenu; porażka → fallback (nie spinujemy na
    // wygasłym tokenie co [minDelay], bo reaktywne 401 i tak zadziała).
    _armTimer(fresh != null ? _delayFor(fresh) : fallbackDelay, generation);
  }
}
