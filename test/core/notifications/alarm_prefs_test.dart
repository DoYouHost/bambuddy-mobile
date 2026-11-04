import 'dart:convert';

import 'package:bambuddy_mobile/core/notifications/notification_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stored', () {
    test('round-trips through the notification prefs', () {
      const alarm = AlarmPrefs(
        enabled: true,
        events: {AlarmEvent.dryingFinished},
        windowEnabled: false,
        windowStart: 23 * 60 + 30,
        windowEnd: 6 * 60,
        ringMinutes: 3,
      );
      final decoded = NotificationPrefs.decode(
        NotificationPrefs.defaults.copyWith(alarm: alarm).encode(),
      ).alarm;
      expect(decoded.enabled, isTrue);
      expect(decoded.events, {AlarmEvent.dryingFinished});
      expect(decoded.windowEnabled, isFalse);
      expect(decoded.windowStart, 23 * 60 + 30);
      expect(decoded.windowEnd, 6 * 60);
      expect(decoded.ringMinutes, 3);
    });

    test('prefs written before the alarm existed read it as off', () {
      final alarm = NotificationPrefs.decode(
        jsonEncode({
          'enabled': ['printFinished'],
        }),
      ).alarm;
      expect(alarm.enabled, isFalse);
      expect(alarm.events, AlarmEvent.values.toSet());
      expect(alarm.windowEnabled, isTrue);
      expect(alarm.windowStart, 22 * 60);
      expect(alarm.windowEnd, 7 * 60);
      expect(alarm.ringMinutes, 10);
    });

    test('every event cleared stays cleared', () {
      final alarm = AlarmPrefs.fromJson({'enabled': true, 'events': []});
      expect(alarm.events, isEmpty);
      expect(alarm.wants(AlarmEvent.printFinished), isFalse);
    });

    test('malformed fields fall back to their defaults one by one', () {
      final alarm = AlarmPrefs.fromJson({
        'enabled': 'yes',
        'events': ['printFinished', 'futureEvent', 7],
        'windowEnabled': 1,
        'windowStart': 24 * 60,
        'windowEnd': -1,
        // Not one of the slider's stops.
        'ringMinutes': 7,
      });
      expect(alarm.enabled, isFalse);
      expect(alarm.events, {AlarmEvent.printFinished});
      expect(alarm.windowEnabled, isTrue);
      expect(alarm.windowStart, AlarmPrefs.defaultWindowStart);
      expect(alarm.windowEnd, AlarmPrefs.defaultWindowEnd);
      expect(alarm.ringMinutes, AlarmPrefs.defaultRingMinutes);
    });

    test('a whole number stored as a double does not throw', () {
      // 10.0 == 10 in Dart, so membership alone let it through to a cast.
      final prefs = NotificationPrefs.decode(
        jsonEncode({
          'enabled': ['printStarted'],
          'known': [for (final e in NotifEvent.values) e.name],
          'alarm': {'enabled': true, 'ringMinutes': 10.5 - 0.5},
        }),
      );
      expect(prefs.alarm.ringMinutes, AlarmPrefs.defaultRingMinutes);
      expect(prefs.alarm.enabled, isTrue);
      expect(prefs.enabled, {NotifEvent.printStarted});
    });

    test('a non-map value is the defaults', () {
      expect(AlarmPrefs.fromJson('garbage').enabled, isFalse);
      expect(AlarmPrefs.fromJson(null).ringMinutes, 10);
    });
  });

  group('wants', () {
    test('needs the alarm on and the event chosen', () {
      expect(AlarmPrefs.defaults.wants(AlarmEvent.printFinished), isFalse);
      const on = AlarmPrefs(enabled: true);
      expect(on.wants(AlarmEvent.printFinished), isTrue);
      expect(
        on
            .withEvent(AlarmEvent.printFinished, false)
            .wants(AlarmEvent.printFinished),
        isFalse,
      );
    });
  });

  group('inWindow', () {
    DateTime at(int h, int m) => DateTime(2026, 11, 4, h, m);

    test('22:00–07:00 spans midnight, start in and end out', () {
      const alarm = AlarmPrefs();
      expect(alarm.inWindow(at(21, 59)), isFalse);
      expect(alarm.inWindow(at(22, 0)), isTrue);
      expect(alarm.inWindow(at(0, 0)), isTrue);
      expect(alarm.inWindow(at(6, 59)), isTrue);
      expect(alarm.inWindow(at(7, 0)), isFalse);
      expect(alarm.inWindow(at(12, 0)), isFalse);
    });

    test('a window inside one day', () {
      const alarm = AlarmPrefs(windowStart: 9 * 60, windowEnd: 17 * 60);
      expect(alarm.inWindow(at(8, 59)), isFalse);
      expect(alarm.inWindow(at(9, 0)), isTrue);
      expect(alarm.inWindow(at(16, 59)), isTrue);
      expect(alarm.inWindow(at(17, 0)), isFalse);
      expect(alarm.inWindow(at(23, 0)), isFalse);
    });

    test('equal ends cover the whole day', () {
      const alarm = AlarmPrefs(windowStart: 8 * 60, windowEnd: 8 * 60);
      for (final h in [0, 7, 8, 12, 23]) {
        expect(alarm.inWindow(at(h, 0)), isTrue, reason: '$h:00');
      }
    });

    test('the window switched off rings at any hour', () {
      const alarm = AlarmPrefs(windowEnabled: false);
      expect(alarm.inWindow(at(12, 0)), isTrue);
    });
  });
}
