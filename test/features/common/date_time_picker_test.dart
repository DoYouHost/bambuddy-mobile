import 'package:bambuddy_mobile/features/common/date_time_picker.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// What the picker answered, and whether it answered at all — a dismissed
/// dialog and a picker still open both leave a null instant, and only the flag
/// tells them apart.
class _Answer {
  DateTime? at;
  bool done = false;
}

void main() {
  /// A Thursday evening, so "an hour from now" stays on the same day and the
  /// calendar cannot be ambiguous about which cell it opened on.
  final now = DateTime(2026, 9, 3, 20);

  Future<void> open(
    WidgetTester tester,
    _Answer answer, {
    DateTime? initial,
    DateTime? firstDate,
  }) async {
    await tester.pumpWidget(plApp(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                answer.at = await pickDateTime(
                  context,
                  initial: initial,
                  firstDate: firstDate,
                );
                answer.done = true;
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  /// Accepts a dialog as it opened — the day the calendar landed on, the time
  /// the clock face started at.
  Future<void> accept(WidgetTester tester) async {
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  Future<void> dismiss(WidgetTester tester) async {
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
  }

  testWidgets('a date and a time become one instant', (tester) async {
    final answer = _Answer();

    await withClock(Clock.fixed(now), () async {
      await open(tester, answer);
      await accept(tester);
      await accept(tester);
    });

    expect(answer.done, isTrue);
    expect(answer.at, DateTime(2026, 9, 3, 21));
  });

  testWidgets('an instant to edit is where both dialogs start', (tester) async {
    final answer = _Answer();

    await withClock(Clock.fixed(now), () async {
      await open(tester, answer, initial: DateTime(2026, 9, 10, 6, 30));
      await accept(tester);
      await accept(tester);
    });

    expect(answer.at, DateTime(2026, 9, 10, 6, 30));
  });

  testWidgets('backing out of the date answers nothing', (tester) async {
    final answer = _Answer();

    await withClock(Clock.fixed(now), () async {
      await open(tester, answer);
      await dismiss(tester);
    });

    expect(answer.done, isTrue);
    expect(answer.at, isNull);
  });

  testWidgets('backing out of the time answers nothing either', (tester) async {
    final answer = _Answer();

    await withClock(Clock.fixed(now), () async {
      await open(tester, answer);
      await accept(tester);
      await dismiss(tester);
    });

    expect(answer.done, isTrue);
    expect(answer.at, isNull);
  });

  /// `showDatePicker` asserts when the day it is told to open on is before the
  /// first day it may show, and a stored instant that has since passed is
  /// exactly how a form gets there — a queue row scheduled for this morning, or
  /// a drying time picked before the user went back to the sliders.
  testWidgets('an instant already gone opens the calendar, it does not assert',
      (tester) async {
    final answer = _Answer();

    await withClock(Clock.fixed(now), () async {
      await open(tester, answer, initial: DateTime(2026, 8, 30, 6));
      await accept(tester);
      await accept(tester);
    });

    expect(tester.takeException(), isNull);
    // The *day* is clamped to the earliest one on offer; the hour is the one
    // that was stored, because no clock value was ever out of range.
    expect(answer.at, DateTime(2026, 9, 3, 6));
  });

  /// The queue edits jobs whose time has passed, so its calendar reaches back a
  /// day — otherwise "the same day, an hour later" cannot be expressed.
  testWidgets('a caller can ask for a day the default would refuse',
      (tester) async {
    final answer = _Answer();

    await withClock(Clock.fixed(now), () async {
      await open(
        tester,
        answer,
        initial: DateTime(2026, 9, 2, 18),
        firstDate: now.subtract(const Duration(days: 1)),
      );
      await accept(tester);
      await accept(tester);
    });

    expect(answer.at, DateTime(2026, 9, 2, 18));
  });
}
