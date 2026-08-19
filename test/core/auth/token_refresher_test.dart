import 'dart:async';

import 'package:bambuddy_mobile/core/auth/token_refresher.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTimer implements Timer {
  _FakeTimer(this.duration, this.callback);
  final Duration duration;
  final void Function() callback;
  bool cancelled = false;
  @override
  void cancel() => cancelled = true;
  @override
  bool get isActive => !cancelled;
  @override
  int get tick => 0;
  void fire() {
    if (!cancelled) callback();
  }
}

void main() {
  // Stały „teraz"; wszystkie exp liczone względem niego.
  final t0 = DateTime.utc(2026, 1, 1, 12);

  late List<_FakeTimer> timers;
  RefreshTimerFactory factory() => (d, cb) {
        final t = _FakeTimer(d, cb);
        timers.add(t);
        return t;
      };

  setUp(() => timers = []);

  // Pozwala dobiec asynchronicznym krokom (readExpiry/refresh → arm timera).
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('planuje odnowę na exp − leadTime (token ważny)', () async {
    ProactiveTokenRefresher(
      readExpiry: () async => t0.add(const Duration(hours: 1)),
      refresh: () async => null,
      clock: () => t0,
      timerFactory: factory(),
    ).start();
    await settle();
    expect(timers, hasLength(1));
    expect(timers.single.duration, const Duration(minutes: 55)); // 60 − 5
  });

  test('brak exp w tokenie → fallbackDelay', () async {
    ProactiveTokenRefresher(
      readExpiry: () async => null,
      refresh: () async => null,
      clock: () => t0,
      fallbackDelay: const Duration(hours: 3),
      timerFactory: factory(),
    ).start();
    await settle();
    expect(timers.single.duration, const Duration(hours: 3));
  });

  test('token już wygasły → minDelay (a nie zero/ujemny)', () async {
    ProactiveTokenRefresher(
      readExpiry: () async => t0.subtract(const Duration(minutes: 1)),
      refresh: () async => null,
      clock: () => t0,
      minDelay: const Duration(seconds: 30),
      timerFactory: factory(),
    ).start();
    await settle();
    expect(timers.single.duration, const Duration(seconds: 30));
  });

  test('odpalenie woła refresh i przeplanowuje wg nowego tokenu', () async {
    var refreshCount = 0;
    ProactiveTokenRefresher(
      readExpiry: () async => t0.add(const Duration(hours: 1)),
      refresh: () async {
        refreshCount++;
        return t0.add(const Duration(hours: 2));
      },
      clock: () => t0,
      timerFactory: factory(),
    ).start();
    await settle();

    timers.single.fire();
    await settle();

    expect(refreshCount, 1);
    expect(timers, hasLength(2));
    expect(timers.last.duration, const Duration(minutes: 115)); // 120 − 5
  });

  test('porażka odnowy → fallbackDelay (bez spinu na wygasłym tokenie)',
      () async {
    ProactiveTokenRefresher(
      readExpiry: () async => t0.add(const Duration(hours: 1)),
      refresh: () async => null, // np. brak zapamiętanych poświadczeń
      clock: () => t0,
      fallbackDelay: const Duration(hours: 6),
      timerFactory: factory(),
    ).start();
    await settle();
    timers.single.fire();
    await settle();
    expect(timers.last.duration, const Duration(hours: 6));
  });

  test('porażka odnowy przy zachowanym haśle → próbuje dalej', () async {
    // Sieć była na przeszkodzie: hasło zostało w schowku, więc kolejne obudzenie
    // ma czym spróbować.
    ProactiveTokenRefresher(
      readExpiry: () async => t0.add(const Duration(hours: 1)),
      refresh: () async => null,
      canRetry: () async => true,
      clock: () => t0,
      fallbackDelay: const Duration(hours: 2),
      timerFactory: factory(),
    ).start();
    await settle();
    timers.single.fire();
    await settle();

    expect(timers, hasLength(2));
    expect(timers.last.duration, const Duration(hours: 2));
  });

  test('porażka odnowy po odrzuceniu hasła → koniec planowania', () async {
    // `silentReLogin` czyści zapamiętane hasło tylko wtedy, gdy serwer je
    // odrzucił — budzenie się co dwie godziny powtarzałoby logowanie, które nie
    // ma czym się udać, przeciwko limitowi nieudanych prób na serwerze.
    var refreshCount = 0;
    ProactiveTokenRefresher(
      readExpiry: () async => t0.add(const Duration(hours: 1)),
      refresh: () async {
        refreshCount++;
        return null;
      },
      canRetry: () async => false,
      clock: () => t0,
      timerFactory: factory(),
    ).start();
    await settle();
    timers.single.fire();
    await settle();

    expect(refreshCount, 1);
    expect(timers, hasLength(1), reason: 'nie planuje kolejnej próby');
    expect(timers.single.cancelled, isTrue);
  });

  test('rzut przy odczycie ważności nie zabija harmonogramu', () async {
    // `flutter_secure_storage` rzuca na części OEM-ów. Nikt na to nie czeka, więc
    // bez osłony timer nie zostałby uzbrojony nigdy, a `start()` jest
    // idempotentne — odświeżanie byłoby martwe do restartu izolatu.
    ProactiveTokenRefresher(
      readExpiry: () async => throw StateError('keystore'),
      refresh: () async => null,
      clock: () => t0,
      fallbackDelay: const Duration(hours: 2),
      timerFactory: factory(),
    ).start();
    await settle();

    expect(timers.single.duration, const Duration(hours: 2));
  });

  test('rzut przy odnowie przeplanowuje, a nie kończy', () async {
    var refreshCount = 0;
    ProactiveTokenRefresher(
      readExpiry: () async => t0.add(const Duration(hours: 1)),
      refresh: () async {
        refreshCount++;
        throw StateError('keystore');
      },
      // Rzut nic nie mówi o haśle — inaczej niż `null` — więc pytanie o dalsze
      // próby nie powinno paść.
      canRetry: () async => fail('nie pytamy, gdy krok się wywalił'),
      clock: () => t0,
      fallbackDelay: const Duration(hours: 2),
      timerFactory: factory(),
    ).start();
    await settle();
    timers.single.fire();
    await settle();

    expect(refreshCount, 1);
    expect(timers.last.duration, const Duration(hours: 2));
  });

  test('stop() anuluje timer i blokuje przeplanowanie po odpaleniu', () async {
    var refreshCount = 0;
    final r = ProactiveTokenRefresher(
      readExpiry: () async => t0.add(const Duration(hours: 1)),
      refresh: () async {
        refreshCount++;
        return null;
      },
      clock: () => t0,
      timerFactory: factory(),
    )..start();
    await settle();
    final first = timers.single;
    r.stop();
    expect(first.cancelled, isTrue);
    first.fire(); // anulowany — nie powinien nic zrobić
    await settle();
    expect(refreshCount, 0);
    expect(timers, hasLength(1)); // brak nowego timera
  });

  test('start() jest idempotentne (nie dubluje timerów)', () async {
    final r = ProactiveTokenRefresher(
      readExpiry: () async => t0.add(const Duration(hours: 1)),
      refresh: () async => null,
      clock: () => t0,
      timerFactory: factory(),
    )..start();
    await settle();
    r.start(); // drugi start — bez efektu
    await settle();
    expect(timers, hasLength(1));
  });
}
