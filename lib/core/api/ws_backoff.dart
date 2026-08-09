import 'dart:math';

/// `delay = rand(0, min(cap, base * 2^attempt))`. Full jitter rather than plain
/// exponential, so a server restart does not bring every client back at the
/// same instant; the cap never lapses, because a home LAN server restarting is
/// normal and giving up is not.
///
/// `WsClient` calls [reset] only once a connection survives its stability
/// threshold, so flapping cannot walk the backoff back to zero.
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

  int get attempt => _attempt;

  Duration nextDelay() {
    // The result is capped anyway, so clamping the exponent at 30 is enough to
    // keep the shift from overflowing.
    final shifted = base.inMilliseconds * (1 << _attempt.clamp(0, 30));
    final ceilingMs = shifted.clamp(0, cap.inMilliseconds);
    _attempt++;
    return Duration(milliseconds: (_random() * ceilingMs).floor());
  }

  void reset() => _attempt = 0;
}
