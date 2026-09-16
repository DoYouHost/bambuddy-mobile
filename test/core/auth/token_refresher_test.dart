import 'package:bambuddy_mobile/core/auth/token_refresher.dart';
import 'package:bambuddy_mobile/core/time/timer_factory.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  // Fixed "now" — installed as the ambient clock for each case, and every
  // exp below is measured against it.
  final t0 = DateTime.utc(2026, 1, 1, 12);

  /// A case in this file, on the ambient clock pinned to [t0].
  void testAt(String description, dynamic Function(TestClock time) body) =>
      testWithClock(description, t0, body);

  late List<FakeTimer> timers;
  TimerFactory factory() => (d, cb) {
    final t = FakeTimer(d, cb);
    timers.add(t);
    return t;
  };

  setUp(() => timers = []);

  // Lets the async steps finish (readExpiry/refresh → arming the timer).
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  testAt('schedules the refresh at exp − leadTime (valid token)', (_) async {
    ProactiveTokenRefresher(
      readExpiry: () async => t0.add(const Duration(hours: 1)),
      refresh: () async => null,
      timerFactory: factory(),
    ).start();
    await settle();
    expect(timers, hasLength(1));
    expect(timers.single.duration, const Duration(minutes: 55)); // 60 − 5
  });

  testAt('no exp in the token → fallbackDelay', (_) async {
    ProactiveTokenRefresher(
      readExpiry: () async => null,
      refresh: () async => null,
      fallbackDelay: const Duration(hours: 3),
      timerFactory: factory(),
    ).start();
    await settle();
    expect(timers.single.duration, const Duration(hours: 3));
  });

  testAt('already expired token → minDelay (not zero/negative)', (_) async {
    ProactiveTokenRefresher(
      readExpiry: () async => t0.subtract(const Duration(minutes: 1)),
      refresh: () async => null,
      minDelay: const Duration(seconds: 30),
      timerFactory: factory(),
    ).start();
    await settle();
    expect(timers.single.duration, const Duration(seconds: 30));
  });

  testAt('firing calls refresh and reschedules from the new token', (_) async {
    var refreshCount = 0;
    ProactiveTokenRefresher(
      readExpiry: () async => t0.add(const Duration(hours: 1)),
      refresh: () async {
        refreshCount++;
        return t0.add(const Duration(hours: 2));
      },
      timerFactory: factory(),
    ).start();
    await settle();

    timers.single.fire();
    await settle();

    expect(refreshCount, 1);
    expect(timers, hasLength(2));
    expect(timers.last.duration, const Duration(minutes: 115)); // 120 − 5
  });

  testAt('failed refresh → fallbackDelay (no spinning on an expired token)', (
    _,
  ) async {
    ProactiveTokenRefresher(
      readExpiry: () async => t0.add(const Duration(hours: 1)),
      refresh: () async => null, // e.g. no remembered credentials
      fallbackDelay: const Duration(hours: 6),
      timerFactory: factory(),
    ).start();
    await settle();
    timers.single.fire();
    await settle();
    expect(timers.last.duration, const Duration(hours: 6));
  });

  testAt('failed refresh with the password kept → keeps trying', (_) async {
    // The network was in the way: the password stayed in the store, so the next
    // wake-up has something to try with.
    ProactiveTokenRefresher(
      readExpiry: () async => t0.add(const Duration(hours: 1)),
      refresh: () async => null,
      canRetry: () async => true,
      fallbackDelay: const Duration(hours: 2),
      timerFactory: factory(),
    ).start();
    await settle();
    timers.single.fire();
    await settle();

    expect(timers, hasLength(2));
    expect(timers.last.duration, const Duration(hours: 2));
  });

  testAt('failed refresh after the password was rejected → stops scheduling', (
    _,
  ) async {
    // `silentReLogin` clears the remembered password only when the server
    // rejected it — waking up every two hours would repeat a login that has
    // nothing to succeed with, against the server's failed-attempt budget.
    var refreshCount = 0;
    ProactiveTokenRefresher(
      readExpiry: () async => t0.add(const Duration(hours: 1)),
      refresh: () async {
        refreshCount++;
        return null;
      },
      canRetry: () async => false,
      timerFactory: factory(),
    ).start();
    await settle();
    timers.single.fire();
    await settle();

    expect(refreshCount, 1);
    expect(timers, hasLength(1), reason: 'does not schedule another attempt');
    expect(timers.single.cancelled, isTrue);
  });

  testAt('a throw while reading the expiry does not kill the schedule', (
    _,
  ) async {
    // `flutter_secure_storage` throws on some OEMs. Nobody awaits this, so
    // without the guard the timer would never be armed, and `start()` is
    // idempotent — refreshing would be dead until the isolate restarts.
    ProactiveTokenRefresher(
      readExpiry: () async => throw StateError('keystore'),
      refresh: () async => null,
      fallbackDelay: const Duration(hours: 2),
      timerFactory: factory(),
    ).start();
    await settle();

    expect(timers.single.duration, const Duration(hours: 2));
  });

  testAt('a throw during the refresh reschedules instead of stopping', (
    _,
  ) async {
    var refreshCount = 0;
    ProactiveTokenRefresher(
      readExpiry: () async => t0.add(const Duration(hours: 1)),
      refresh: () async {
        refreshCount++;
        throw StateError('keystore');
      },
      // A throw says nothing about the password — unlike `null` — so the
      // question about further attempts must not be asked.
      canRetry: () async => fail('not asked when the step blew up'),
      fallbackDelay: const Duration(hours: 2),
      timerFactory: factory(),
    ).start();
    await settle();
    timers.single.fire();
    await settle();

    expect(refreshCount, 1);
    expect(timers.last.duration, const Duration(hours: 2));
  });

  testAt('stop() cancels the timer and blocks rescheduling after it fires', (
    _,
  ) async {
    var refreshCount = 0;
    final r = ProactiveTokenRefresher(
      readExpiry: () async => t0.add(const Duration(hours: 1)),
      refresh: () async {
        refreshCount++;
        return null;
      },
      timerFactory: factory(),
    )..start();
    await settle();
    final first = timers.single;
    r.stop();
    expect(first.cancelled, isTrue);
    first.fire(); // cancelled — must do nothing
    await settle();
    expect(refreshCount, 0);
    expect(timers, hasLength(1)); // no new timer
  });

  testAt('start() is idempotent (does not duplicate timers)', (_) async {
    final r = ProactiveTokenRefresher(
      readExpiry: () async => t0.add(const Duration(hours: 1)),
      refresh: () async => null,
      timerFactory: factory(),
    )..start();
    await settle();
    r.start(); // second start — no effect
    await settle();
    expect(timers, hasLength(1));
  });
}
