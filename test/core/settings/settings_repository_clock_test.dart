import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SettingsRepository> _repo([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  return SettingsRepository(await SharedPreferences.getInstance());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the 12/24-hour switch', () {
    test('is absent on an install that predates it', () async {
      // Not `false`: the service reads this, and a false there is a 12-hour
      // clock forced on everyone who upgrades before the app is next opened.
      expect((await _repo()).loadUse24HourClock(), isNull);
    });

    test('survives the round trip in both positions', () async {
      final repo = await _repo();

      await repo.saveUse24HourClock(true);
      expect(repo.loadUse24HourClock(), isTrue);

      await repo.saveUse24HourClock(false);
      expect(repo.loadUse24HourClock(), isFalse);
    });

    test('is read from the key the other isolate writes', () async {
      // The service and the UI meet on this string alone; renaming it on one
      // side leaves the other reading nothing and no test failing.
      expect((await _repo({'clock_24h': true})).loadUse24HourClock(), isTrue);
    });
  });
}
