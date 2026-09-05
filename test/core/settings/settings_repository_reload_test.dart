import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for the other isolate: it writes the file, and this side's handle
/// hears nothing about it.
void writeBehindOurBack(Map<String, Object> values) =>
    SharedPreferences.setMockInitialValues(values);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an open handle keeps serving the snapshot it was opened with', () async {
    writeBehindOurBack({'clock_24h': false});
    final settings = SettingsRepository(await SharedPreferences.getInstance());

    writeBehindOurBack({'clock_24h': true});

    expect(settings.loadUse24HourClock(), isFalse,
        reason: 'this is the trap every caller of reloaded() is avoiding');
    expect((await settings.reloaded()).loadUse24HourClock(), isTrue);
  });

  test('opened() is that, for an isolate holding no handle yet', () async {
    // A notification action wakes its own isolate: nothing there has read
    // preferences, and `getInstance` may still hand back a cache from earlier
    // in the process's life.
    writeBehindOurBack({'clock_24h': false});
    await SharedPreferences.getInstance();

    writeBehindOurBack({'clock_24h': true});

    expect((await SettingsRepository.opened()).loadUse24HourClock(), isTrue);
  });
}
