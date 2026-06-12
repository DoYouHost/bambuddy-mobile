import 'dart:math';

/// Backoff wykładniczy z **pełnym jitterem** dla reconnectu WebSocketa.
///
/// `delay = rand(0, min(cap, base * 2^attempt))` — pełny jitter (a nie samo
/// wykładnicze opóźnienie) rozprasza stado klientów, które ruszają do
/// serwera w tej samej chwili po jego restarcie. Cap obowiązuje na zawsze:
/// to aplikacja domowego LAN-u, serwer bywa restartowany, nie poddajemy się.
///
/// Licznik prób zeruje [reset] — wołane przez [WsClient] dopiero gdy
/// połączenie przeżyło próg stabilności, żeby flapping nie kasował narastania.
class WsBackoff {
  WsBackoff({
    this.base = const Duration(seconds: 1),
    this.cap = const Duration(seconds: 30),
    double Function()? random,
  }) : _random = random ?? Random().nextDouble;

  final Duration base;
  final Duration cap;
  final double Function() _random;

  int _attempt = 0;

  /// Numer kolejnej próby (0 = pierwsza po resecie) — pomocne w testach/logach.
  int get attempt => _attempt;

  /// Zwraca losowe opóźnienie dla bieżącej próby i inkrementuje licznik.
  Duration nextDelay() {
    // Wykładnik z ochroną przed przepełnieniem: 2^attempt rośnie szybko,
    // ale i tak ścinamy do cap, więc clamp wykładnika na 30 wystarcza.
    final shifted = base.inMilliseconds * (1 << _attempt.clamp(0, 30));
    final ceilingMs = shifted.clamp(0, cap.inMilliseconds);
    _attempt++;
    return Duration(milliseconds: (_random() * ceilingMs).floor());
  }

  void reset() => _attempt = 0;
}
