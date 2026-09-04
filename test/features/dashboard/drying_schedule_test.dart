import 'package:bambuddy_mobile/features/dashboard/drying_schedule.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final at = DateTime(2026, 9, 3, 20);

  DryingStart start(
    DryStartMode mode, {
    int delayMinutes = 60,
    DateTime? pickedAt,
  }) =>
      withClock(
        Clock.fixed(at),
        () => dryingStart(
          mode: mode,
          delayMinutes: delayMinutes,
          at: pickedAt,
        ),
      );

  test('Now schedules nothing — the printer is told directly', () {
    expect(start(DryStartMode.now),
        (startAfter: null, problem: null));
  });

  test('a delay is counted from now, not from when the chip was tapped', () {
    expect(
      start(DryStartMode.delay, delayMinutes: 120).startAfter,
      DateTime(2026, 9, 3, 22),
    );
  });

  test('every delay preset lands in the future', () {
    for (final minutes in dryingDelayPresets) {
      final result = start(DryStartMode.delay, delayMinutes: minutes);
      expect(result.problem, isNull, reason: '$minutes min');
      expect(result.startAfter!.isAfter(at), isTrue, reason: '$minutes min');
    }
  });

  test('the longest preset is a full day ahead', () {
    expect(
      start(DryStartMode.delay, delayMinutes: dryingDelayPresets.last)
          .startAfter,
      DateTime(2026, 9, 4, 20),
    );
  });

  test('a picked instant is sent as picked', () {
    final picked = DateTime(2026, 9, 4, 6, 30);

    expect(
      start(DryStartMode.atTime, pickedAt: picked),
      (startAfter: picked, problem: null),
    );
  });

  /// The trap this guard exists for: falling through to `startAfter == null`
  /// would read as "start now" and heat an AMS the user only meant to schedule.
  test('"at time" with nothing picked asks for a time, it does not start now',
      () {
    expect(
      start(DryStartMode.atTime),
      (startAfter: null, problem: DryingStartProblem.noTimePicked),
    );
  });

  test('an instant already gone is refused here, not by the server', () {
    expect(
      start(DryStartMode.atTime, pickedAt: DateTime(2026, 9, 3, 19, 59)),
      (startAfter: null, problem: DryingStartProblem.timeInPast),
    );
  });

  /// The server's check is `start_after <= now`, so the boundary is a refusal
  /// on both sides.
  test('this very instant is not in the future either', () {
    expect(
      start(DryStartMode.atTime, pickedAt: at).problem,
      DryingStartProblem.timeInPast,
    );
  });

  test('one minute out is enough', () {
    final picked = at.add(const Duration(minutes: 1));

    expect(start(DryStartMode.atTime, pickedAt: picked).startAfter, picked);
  });
}
