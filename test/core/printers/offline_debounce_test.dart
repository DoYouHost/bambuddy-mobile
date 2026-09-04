import 'dart:async';

import 'package:bambuddy_mobile/core/printers/offline_debounce.dart';
import 'package:flutter_test/flutter_test.dart';

/// A timer the test fires by hand, so the window costs no wall time.
class _FakeTimer implements Timer {
  _FakeTimer(this.duration, this._callback);

  final Duration duration;
  final void Function() _callback;
  bool cancelled = false;

  void fire() {
    if (cancelled) return;
    _callback();
  }

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}

void main() {
  late List<_FakeTimer> timers;
  late List<String> events;
  late OfflineDebounce debounce;

  setUp(() {
    timers = [];
    events = [];
    debounce = OfflineDebounce(timerFactory: (d, cb) {
      final t = _FakeTimer(d, cb);
      timers.add(t);
      return t;
    });
  });

  void observe(bool? connected, {bool debounceIt = true}) => debounce.observe(
        connected,
        debounce: debounceIt,
        onSustained: () => events.add('sustained'),
        onFlicker: () => events.add('flicker'),
      );

  test('a disconnect is believed only after the window', () {
    observe(true);
    observe(false);

    expect(debounce.offline, isFalse, reason: 'still counting');
    expect(debounce.counting, isTrue);
    expect(events, isEmpty);
    expect(timers.single.duration, OfflineDebounce.defaultWindow);

    timers.single.fire();
    expect(debounce.offline, isTrue);
    expect(events, ['sustained']);
  });

  test('a printer that answers again cancels the wait and says so once', () {
    observe(true);
    observe(false);
    observe(true);

    expect(timers.single.cancelled, isTrue);
    expect(debounce.offline, isFalse);
    expect(events, ['flicker']);

    // A second connected frame is not a second flicker: nothing was pending.
    observe(true);
    expect(events, ['flicker']);
  });

  test('a disconnect already believed holds nothing back', () {
    observe(false);
    timers.single.fire();
    expect(events, ['sustained']);

    observe(true);
    expect(events, ['sustained'], reason: 'the alert had already gone out');
    expect(debounce.offline, isFalse);
  });

  test('repeated disconnects do not restart the countdown', () {
    observe(false);
    observe(false);
    observe(false);

    expect(timers, hasLength(1));
  });

  test('a partial frame says nothing either way', () {
    observe(true);
    observe(null);

    expect(debounce.counting, isFalse);
    expect(debounce.offline, isFalse);
    expect(events, isEmpty);

    // And it does not disturb a wait that is already running.
    observe(false);
    observe(null);
    expect(timers, hasLength(1));
    expect(timers.single.cancelled, isFalse);
  });

  test('a frame nothing could contradict is believed at once', () {
    observe(false, debounceIt: false);

    expect(timers, isEmpty);
    expect(debounce.offline, isTrue);
    expect(events, ['sustained']);
  });

  test('a seeded state is adopted, never announced', () {
    debounce.seed(false);
    expect(debounce.offline, isTrue);
    expect(events, isEmpty);

    // Seeding also drops a wait in progress — the caller is declaring the
    // state, not observing a change.
    final fresh = OfflineDebounce(timerFactory: (d, cb) {
      final t = _FakeTimer(d, cb);
      timers.add(t);
      return t;
    });
    fresh.observe(false, onSustained: () => events.add('sustained'));
    fresh.seed(true);
    expect(timers.last.cancelled, isTrue);
    expect(fresh.offline, isFalse);
    expect(events, isEmpty);
  });

  test('seeding on a partial frame keeps what the caller already had', () {
    debounce.seed(false);
    debounce.seed(null);

    expect(debounce.offline, isTrue);
  });

  test('dispose stops a pending wait from ever firing', () {
    observe(false);
    debounce.dispose();

    timers.single.fire();
    expect(events, isEmpty);
    expect(debounce.counting, isFalse);
  });
}
