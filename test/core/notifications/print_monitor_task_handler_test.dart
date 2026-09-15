import 'package:bambuddy_mobile/core/format/datetime_format.dart';
import 'package:bambuddy_mobile/core/notifications/background_sync.dart';
import 'package:bambuddy_mobile/core/notifications/print_monitor_task_handler.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
// Not re-exported by the library above, and the only seam the plugin offers:
// swapping this out is what keeps `stopService` off a channel no test has.
import 'package:flutter_foreground_task/flutter_foreground_task_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for the plugin's platform channel, which a test has no engine for.
///
/// Only the calls this handler makes are implemented; anything else throwing
/// `UnimplementedError` from the base class is the point — a new platform call
/// added to the handler shows up here as a failure rather than as silence.
class _FakeForegroundTask extends FlutterForegroundTaskPlatform {
  var stopped = 0;
  final updates = <(String?, String?)>[];

  @override
  Future<bool> get isRunningService async => true;

  @override
  Future<void> stopService() async => stopped++;

  @override
  Future<void> updateService({
    ForegroundTaskOptions? foregroundTaskOptions,
    String? notificationTitle,
    String? notificationText,
    NotificationIcon? notificationIcon,
    List<NotificationButton>? notificationButtons,
    String? notificationInitialRoute,
    Function? callback,
  }) async => updates.add((notificationTitle, notificationText));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeForegroundTask platform;
  late FlutterForegroundTaskPlatform realPlatform;
  late bool realSkipCheck;

  setUp(() {
    realPlatform = FlutterForegroundTaskPlatform.instance;
    realSkipCheck = FlutterForegroundTask.skipServiceResponseCheck;
    platform = _FakeForegroundTask();
    FlutterForegroundTaskPlatform.instance = platform;
    // Without this the plugin polls the channel for the service state change it
    // just asked for, which no fake can answer.
    FlutterForegroundTask.skipServiceResponseCheck = true;
  });

  tearDown(() {
    // All three are process-wide statics, and this file is the only thing that
    // writes them — anything left behind would decide the plugin and the clock
    // of every later test sharing this process.
    FlutterForegroundTaskPlatform.instance = realPlatform;
    FlutterForegroundTask.skipServiceResponseCheck = realSkipCheck;
    DateTimeFormats.rememberSystemClock(null);
  });

  group('the service never outlives what it has to monitor', () {
    test('a start with no profile stops the service', () async {
      // The profile can be cleared while the app is backgrounded. What must not
      // happen is an idle service left behind with a notification still saying
      // it is monitoring.
      SharedPreferences.setMockInitialValues({});

      await PrintMonitorTaskHandler().onStart(
        DateTime(2026, 9, 15),
        TaskStarter.developer,
      );

      expect(platform.stopped, 1);
    });

    test('a start with a corrupt profile stops the service too', () async {
      // `loadProfile` answers null for unreadable JSON rather than throwing, so
      // this arrives at the same door as the cleared profile — and has to, or
      // the service runs on with nothing behind it.
      SharedPreferences.setMockInitialValues({
        'server_profile': 'not json at all',
      });

      await PrintMonitorTaskHandler().onStart(
        DateTime(2026, 9, 15),
        TaskStarter.system,
      );

      expect(platform.stopped, 1);
    });

    test('a teardown before anything started completes and stays quiet', () async {
      // Android can destroy a service whose `onStart` stopped it on the way in,
      // so every field `onDestroy` touches is still null. It disposes them in a
      // fixed order and awaits four of them; a null slipping past a `?.` would
      // throw here, inside a callback nothing else is watching.
      SharedPreferences.setMockInitialValues({});
      final handler = PrintMonitorTaskHandler();

      await expectLater(
        handler.onDestroy(DateTime(2026, 9, 15), false),
        completes,
      );
      expect(platform.stopped, 0, reason: 'teardown does not stop the service');
    });
  });

  group('facts the app pushes into a service that is already running', () {
    // Both directions, and never against a hardcoded expectation: with nothing
    // remembered, `use24Hour` falls back to whatever locale the runner reports,
    // so a test that assumed a 12-hour one would pass or fail on the machine
    // rather than on the code. A remembered value wins outright over the locale
    // (`DateTimeFormats.isolateClock`), so each of these holds on any runner —
    // and a sync that stopped working fails one of them whichever locale it is.
    for (final wanted in [true, false]) {
      test(
        'a clock sync reads a $wanted switch back out of preferences',
        () async {
          // The bare engine behind the service is never told the 12/24-hour
          // setting, so it reads it from preferences — and a service that was
          // already up when the user flipped the switch only hears about it
          // through this message.
          SharedPreferences.setMockInitialValues({'clock_24h': wanted});

          PrintMonitorTaskHandler().onReceiveData(BackgroundSync.clock.message);
          await pumpEventQueue();

          expect(DateTimeFormats.system().use24Hour, wanted);
        },
      );
    }

    test('a message the isolate does not know changes nothing', () async {
      // Stored as the opposite of what this runner's locale answers, so a stray
      // sync is visible here on any machine rather than only on a 12-hour one.
      final fromLocale = DateTimeFormats.system().use24Hour;
      SharedPreferences.setMockInitialValues({'clock_24h': !fromLocale});

      PrintMonitorTaskHandler().onReceiveData(const {'something': 'sync'});
      await pumpEventQueue();

      expect(DateTimeFormats.system().use24Hour, fromLocale);
    });
  });
}
