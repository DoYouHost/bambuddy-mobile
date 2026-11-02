import 'package:bambuddy_mobile/core/settings/controller_prefs.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('everything survives a round trip', () {
    const prefs = ControllerPrefs(
      saverAfterMinutes: 10,
      saverBrightness: 40,
      wakeOnWarnings: false,
      keepAwake: false,
      liveCamera: false,
    );

    final back = ControllerPrefs.fromJson(prefs.toJson());

    expect(back.saverAfterMinutes, 10);
    expect(back.saverBrightness, 40);
    expect(back.wakeOnWarnings, isFalse);
    expect(back.keepAwake, isFalse);
    expect(back.liveCamera, isFalse);
    expect(back.saverAfter, const Duration(minutes: 10));
  });

  test('nothing stored reads as the defaults', () {
    final prefs = ControllerPrefs.fromJson(const {});

    expect(prefs.saverAfterMinutes, ControllerPrefs.defaultSaverAfterMinutes);
    expect(prefs.saverBrightness, ControllerPrefs.defaultSaverBrightness);
    expect(prefs.wakeOnWarnings, isTrue);
    expect(prefs.keepAwake, isTrue);
    expect(prefs.liveCamera, isTrue);
  });

  test('a damaged field costs that field, not the others', () {
    final prefs = ControllerPrefs.fromJson({
      'saver_after_minutes': 'soon',
      'saver_brightness': 30,
      'wake_on_warnings': 'yes',
      'keep_awake': false,
      'live_camera': null,
    });

    expect(prefs.saverAfterMinutes, ControllerPrefs.defaultSaverAfterMinutes);
    expect(prefs.saverBrightness, 30);
    expect(prefs.wakeOnWarnings, isTrue);
    expect(prefs.keepAwake, isFalse);
    expect(prefs.liveCamera, isTrue);
  });

  test('an idle time the picker does not offer falls back to the default', () {
    // 7 is not a choice; a value the picker cannot show must not be silently
    // kept, or the screen would act on a number the user cannot see or change.
    expect(
      ControllerPrefs.fromJson({'saver_after_minutes': 7}).saverAfterMinutes,
      ControllerPrefs.defaultSaverAfterMinutes,
    );
    for (final minutes in ControllerPrefs.saverAfterOptions) {
      expect(
        ControllerPrefs.fromJson({
          'saver_after_minutes': minutes,
        }).saverAfterMinutes,
        minutes,
      );
    }
  });

  test('brightness runs from the floor to the full panel', () {
    expect(
      ControllerPrefs.fromJson({'saver_brightness': 0}).saverBrightness,
      ControllerPrefs.minSaverBrightness,
    );
    expect(
      ControllerPrefs.fromJson({'saver_brightness': 100}).saverBrightness,
      100,
    );
    expect(
      ControllerPrefs.fromJson({'saver_brightness': 150}).saverBrightness,
      100,
    );
  });

  test('"never" is a choice, and means no saver', () {
    final prefs = ControllerPrefs.fromJson({
      'saver_after_minutes': ControllerPrefs.saverNever,
    });

    expect(prefs.saverAfterMinutes, ControllerPrefs.saverNever);
    expect(prefs.saverAfter, isNull);
    expect(const ControllerPrefs().saverAfter, isNotNull);
  });

  test(
    '"never" survives a round trip, so it is not read back as the default',
    () {
      final back = ControllerPrefs.fromJson(
        const ControllerPrefs(
          saverAfterMinutes: ControllerPrefs.saverNever,
        ).toJson(),
      );

      expect(back.saverAfter, isNull);
    },
  );

  test('copyWith changes only what it is given', () {
    final prefs = const ControllerPrefs().copyWith(liveCamera: false);

    expect(prefs.liveCamera, isFalse);
    expect(prefs.keepAwake, isTrue);
    expect(prefs.saverAfterMinutes, ControllerPrefs.defaultSaverAfterMinutes);
  });

  group('SettingsRepository', () {
    late SettingsRepository repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repo = SettingsRepository(await SharedPreferences.getInstance());
    });

    test('loads the defaults before anything is saved', () {
      expect(repo.loadControllerPrefs().liveCamera, isTrue);
      expect(
        repo.loadControllerPrefs().saverAfterMinutes,
        ControllerPrefs.defaultSaverAfterMinutes,
      );
    });

    test('keeps what was saved', () async {
      await repo.saveControllerPrefs(
        const ControllerPrefs(saverAfterMinutes: 15, liveCamera: false),
      );

      final back = repo.loadControllerPrefs();

      expect(back.saverAfterMinutes, 15);
      expect(back.liveCamera, isFalse);
    });

    test('a stored blob that is not JSON reads as the defaults', () async {
      SharedPreferences.setMockInitialValues({'controller_prefs': '{oops'});
      final damaged = SettingsRepository(await SharedPreferences.getInstance());

      expect(damaged.loadControllerPrefs().keepAwake, isTrue);
    });
  });
}
