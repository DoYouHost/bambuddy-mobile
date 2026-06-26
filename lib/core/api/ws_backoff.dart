import 'dart:math';

/// Exponential backoff with **full jitter** for WebSocket reconnect.
///
/// `delay = rand(0, min(cap, base * 2^attempt))` — full jitter (not just
/// exponential delay) disperses a herd of clients attempting server at once
/// after restart. Cap applies forever: this is a home LAN app, server restarts,
/// we don't give up.
///
/// Attempt counter reset by [reset] — called by [WsClient] only after
/// connection survives stability threshold, so flapping doesn't reset backoff.
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

  /// Current attempt number (0 = first after reset) — helpful in tests/logs.
  int get attempt => _attempt;

  /// Returns random delay for current attempt and increments counter.
  Duration nextDelay() {
    // Exponent overflow protection: 2^attempt grows fast, but we cap it anyway,
    // so clamping exponent to 30 is sufficient.
    final shifted = base.inMilliseconds * (1 << _attempt.clamp(0, 30));
    final ceilingMs = shifted.clamp(0, cap.inMilliseconds);
    _attempt++;
    return Duration(milliseconds: (_random() * ceilingMs).floor());
  }

  void reset() => _attempt = 0;
}
