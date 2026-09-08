import 'package:bambuddy_mobile/core/models/queue_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// The whole compatibility story of the queue settings screen lives in this
/// class: which keys the server answered decides which rows exist and which
/// keys may be written. A server that predates a setting drops the write
/// silently rather than refusing it, so getting this wrong is a save that never
/// happened and never said so.
void main() {
  group('QueueSettings.fromSettings', () {
    test('a server answering nothing knows nothing', () {
      final settings = QueueSettings.fromSettings(const {});

      expect(settings.known, isEmpty);
      expect(settings.values, isEmpty);
    });

    test('unrelated settings do not become queue settings', () {
      final settings = QueueSettings.fromSettings(const {
        'use_slicer_api': true,
        'currency': 'PLN',
      });

      expect(settings.known, isEmpty);
    });

    test('a key the server answered is known, whatever its value', () {
      final settings = QueueSettings.fromSettings(const {
        'queue_keep_bed_warm': false,
      });

      expect(settings.known, {QueueSetting.keepBedWarm});
      expect(settings.flag(QueueSetting.keepBedWarm), isFalse);
    });

    test('off and absent are different answers', () {
      final off = QueueSettings.fromSettings(const {'preheat_enabled': false});
      final absent = QueueSettings.fromSettings(const {});

      expect(off.flag(QueueSetting.preheatEnabled), isFalse);
      expect(absent.flag(QueueSetting.preheatEnabled), isFalse);
      // Same reading, opposite meaning — only `known` tells them apart, which
      // is what decides whether the row is offered at all.
      expect(off.known, isNotEmpty);
      expect(absent.known, isEmpty);
    });

    test('numbers come back as numbers, strings included', () {
      final settings = QueueSettings.fromSettings(const {
        'queue_keep_warm_bed_temp': 100,
        // Settings live in a VARCHAR column server-side; a future response that
        // stops typing the field must not take the screen with it.
        'queue_keep_warm_max_minutes': '90',
      });

      expect(settings.number(QueueSetting.keepWarmBedTemp), 100);
      expect(settings.number(QueueSetting.keepWarmMaxMinutes), 90);
    });

    test(
      'an unreadable number falls back to what the server itself would use',
      () {
        final settings = QueueSettings.fromSettings(const {
          'queue_keep_warm_bed_temp': 'warm-ish',
        });

        expect(settings.known, contains(QueueSetting.keepWarmBedTemp));
        expect(settings.number(QueueSetting.keepWarmBedTemp), 90);
      },
    );

    test('a full modern response knows every setting', () {
      final settings = QueueSettings.fromSettings({
        for (final setting in QueueSetting.values)
          setting.key: setting.min == null ? true : setting.serverDefault,
      });

      expect(settings.known, QueueSetting.values.toSet());
    });
  });

  group('withValue', () {
    test('changes the one setting and leaves the rest', () {
      final before = QueueSettings.fromSettings(const {
        'queue_keep_bed_warm': false,
        'queue_keep_warm_bed_temp': 90,
      });

      final after = before.withValue(QueueSetting.keepBedWarm, true);

      expect(after.flag(QueueSetting.keepBedWarm), isTrue);
      expect(after.number(QueueSetting.keepWarmBedTemp), 90);
      expect(
        before.flag(QueueSetting.keepBedWarm),
        isFalse,
        reason: 'immutable',
      );
    });

    test('a setting this server does not have cannot be set', () {
      final before = QueueSettings.fromSettings(const {});

      final after = before.withValue(QueueSetting.keepBedWarm, true);

      expect(after.known, isEmpty);
      expect(after.values, isEmpty);
    });
  });

  group('patch', () {
    test('carries one key, in the server spelling', () {
      expect(QueueSettings.patch(QueueSetting.keepBedWarm, true), {
        'queue_keep_bed_warm': true,
      });
    });

    test('a value inside the range goes as it is', () {
      expect(QueueSettings.patch(QueueSetting.keepWarmBedTemp, 75), {
        'queue_keep_warm_bed_temp': 75,
      });
    });

    test('a value outside the range is clamped, never sent to a 422', () {
      expect(QueueSettings.patch(QueueSetting.keepWarmBedTemp, 200), {
        'queue_keep_warm_bed_temp': 110,
      });
      expect(QueueSettings.patch(QueueSetting.keepWarmMaxMinutes, 0), {
        'queue_keep_warm_max_minutes': 5,
      });
      expect(QueueSettings.patch(QueueSetting.preheatSoakSeconds, -1), {
        'preheat_soak_seconds': 0,
      });
    });

    test('the ranges are the server\'s own', () {
      // `schemas/settings.py::AppSettingsUpdate` — the validators that answer
      // 422 rather than clamping, which is why these are mirrored at all.
      expect(
        {
          for (final s in QueueSetting.values)
            if (s.min != null) s.key: [s.min, s.max],
        },
        {
          'queue_max_concurrent_uploads': [1, 16],
          'preheat_max_wait_seconds': [60, 3600],
          'preheat_soak_seconds': [0, 1800],
          'queue_keep_warm_bed_temp': [40, 110],
          'queue_keep_warm_max_minutes': [5, 480],
        },
      );
    });
  });
}
