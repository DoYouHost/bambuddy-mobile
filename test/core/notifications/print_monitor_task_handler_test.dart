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

  setUp(() {
    platform = _FakeForegroundTask();
    FlutterForegroundTaskPlatform.instance = platform;
    // Without this the plugin polls the channel for the service state change it
    // just asked for, which no fake can answer.
    FlutterForegroundTask.skipServiceResponseCheck = true;
  });

  tearDown(() {
    // Process-wide, and the service is the only thing that writes it — a value
    // left behind here would decide the clock of every later test in this file.
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
    test('a clock sync reads the 24-hour switch back out of preferences', () async {
      // The bare engine behind the service is never told the 12/24-hour setting,
      // so it reads it from preferences — and a service that was already up when
      // the user flipped the switch only hears about it through this message.
      SharedPreferences.setMockInitialValues({'clock_24h': true});
      expect(
        DateTimeFormats.system().use24Hour,
        isFalse,
        reason: 'the test locale is a 12-hour one, so the sync is visible',
      );

      PrintMonitorTaskHandler().onReceiveData(BackgroundSync.clock.message);
      await pumpEventQueue();

      expect(DateTimeFormats.system().use24Hour, isTrue);
    });

    test('a message the isolate does not know changes nothing', () async {
      SharedPreferences.setMockInitialValues({'clock_24h': true});

      PrintMonitorTaskHandler().onReceiveData(const {'something': 'sync'});
      await pumpEventQueue();

      expect(DateTimeFormats.system().use24Hour, isFalse);
    });
  });
}
