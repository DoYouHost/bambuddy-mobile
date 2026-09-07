import 'package:bambuddy_mobile/core/api/ws_backoff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WsBackoff (full jitter)', () {
    test('rand=0 → zero; rand=1 → attempt\'s full ceiling', () {
      var r = 0.0;
      final b = WsBackoff(random: () => r);
      expect(b.nextDelay(), Duration.zero); // attempt 0, ceiling 1s, rand 0
      r = 1.0;
      expect(
        b.nextDelay(),
        const Duration(seconds: 2),
      ); // attempt 1, ceiling 2s
    });

    test('the ceiling grows 2^n and is clamped to a 30s cap', () {
      final b = WsBackoff(random: () => 1.0);
      expect(b.nextDelay(), const Duration(seconds: 1)); // 2^0
      expect(b.nextDelay(), const Duration(seconds: 2)); // 2^1
      expect(b.nextDelay(), const Duration(seconds: 4)); // 2^2
      expect(b.nextDelay(), const Duration(seconds: 8)); // 2^3
      expect(b.nextDelay(), const Duration(seconds: 16)); // 2^4
      expect(b.nextDelay(), const Duration(seconds: 30)); // 2^5=32 → cap
      expect(b.nextDelay(), const Duration(seconds: 30)); // still capped
    });

    test('reset goes back to the first attempt', () {
      final b = WsBackoff(random: () => 1.0);
      b.nextDelay();
      b.nextDelay();
      b.nextDelay();
      expect(b.attempt, 3);
      b.reset();
      expect(b.attempt, 0);
      expect(b.nextDelay(), const Duration(seconds: 1));
    });

    test('the delay never exceeds the ceiling', () {
      final b = WsBackoff(random: () => 0.999);
      expect(b.nextDelay().inMilliseconds, lessThanOrEqualTo(1000));
    });
  });
}
