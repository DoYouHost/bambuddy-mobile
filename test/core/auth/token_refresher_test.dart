import 'dart:async';
import 'dart:convert';

import 'package:bambuddy_mobile/core/auth/token_refresher.dart';
import 'package:flutter_test/flutter_test.dart';

String _jwt(DateTime exp) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${seg({'alg': 'HS256'})}'
      '.${seg({'exp': exp.millisecondsSinceEpoch ~/ 1000})}.sig';
}

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

  // Pozwala dobiec asynchronicznym krokom (readJwt/refresh → arm timera).
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('planuje odnowę na exp − leadTime (token ważny)', () async {
    ProactiveTokenRefresher(
      readJwt: () async => _jwt(t0.add(const Duration(hours: 1))),
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
      readJwt: () async => 'nie-jwt',
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
      readJwt: () async => _jwt(t0.subtract(const Duration(minutes: 1))),
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
      readJwt: () async => _jwt(t0.add(const Duration(hours: 1))),
      refresh: () async {
        refreshCount++;
        return _jwt(t0.add(const Duration(hours: 2)));
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
      readJwt: () async => _jwt(t0.add(const Duration(hours: 1))),
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

  test('stop() anuluje timer i blokuje przeplanowanie po odpaleniu', () async {
    var refreshCount = 0;
    final r = ProactiveTokenRefresher(
      readJwt: () async => _jwt(t0.add(const Duration(hours: 1))),
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
      readJwt: () async => _jwt(t0.add(const Duration(hours: 1))),
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
