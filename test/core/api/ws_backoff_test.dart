import 'package:bambuddy_mobile/core/api/ws_backoff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WsBackoff (pełny jitter)', () {
    test('rand=0 → zero; rand=1 → pełny sufit próby', () {
      var r = 0.0;
      final b = WsBackoff(random: () => r);
      expect(b.nextDelay(), Duration.zero); // próba 0, sufit 1s, rand 0
      r = 1.0;
      expect(b.nextDelay(), const Duration(seconds: 2)); // próba 1, sufit 2s
    });

    test('sufit rośnie 2^n i jest ścinany do cap 30 s', () {
      final b = WsBackoff(random: () => 1.0);
      expect(b.nextDelay(), const Duration(seconds: 1)); // 2^0
      expect(b.nextDelay(), const Duration(seconds: 2)); // 2^1
      expect(b.nextDelay(), const Duration(seconds: 4)); // 2^2
      expect(b.nextDelay(), const Duration(seconds: 8)); // 2^3
      expect(b.nextDelay(), const Duration(seconds: 16)); // 2^4
      expect(b.nextDelay(), const Duration(seconds: 30)); // 2^5=32 → cap
      expect(b.nextDelay(), const Duration(seconds: 30)); // dalej cap
    });

    test('reset wraca do pierwszej próby', () {
      final b = WsBackoff(random: () => 1.0);
      b.nextDelay();
      b.nextDelay();
      b.nextDelay();
      expect(b.attempt, 3);
      b.reset();
      expect(b.attempt, 0);
      expect(b.nextDelay(), const Duration(seconds: 1));
    });

    test('opóźnienie nigdy nie przekracza sufitu', () {
      final b = WsBackoff(random: () => 0.999);
      expect(b.nextDelay().inMilliseconds, lessThanOrEqualTo(1000));
    });
  });
}
