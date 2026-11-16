import 'dart:convert';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:app_util/app_util.dart' show DemoHttpClientAdapter;
import 'package:bambuddy_mobile/core/diagnostics/report_config.dart';
import 'package:bambuddy_mobile/core/format/datetime_format.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/app_context.dart';
import 'package:bambuddy_mobile/core/demo/demo_backend.dart';
import 'package:bambuddy_mobile/features/notifications/print_monitor.dart'
    show alertBandWidth;
import 'package:bambuddy_mobile/core/notifications/background_sync.dart';
import 'package:bambuddy_mobile/core/notifications/notification_prefs.dart';
import 'package:bambuddy_mobile/core/notifications/print_monitor_task_handler.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
// Not re-exported by the library above, and the only seam the plugin offers:
// swapping this out is what keeps `stopService` off a channel no test has.
import 'package:flutter_foreground_task/flutter_foreground_task_platform_interface.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

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

  // The socket never says a printer was deleted, so the list the server gives
  // is what ends one in the service. Without it a printer that was printing
  // when it was deleted stays on the ongoing notification and the widgets.
  group('printers deleted on the server', () {
    test('names the ones the server no longer lists', () {
      expect(printersGone({1, 2, 3}, {1, 3}), {2});
    });

    test('an empty roster drops everything, a full one nothing', () {
      expect(printersGone({1, 2}, <int>{}), {1, 2});
      expect(printersGone({1, 2}, {1, 2}), isEmpty);
    });

    test('one the service has not heard from is no reason to add one', () {
      expect(printersGone({1}, {1, 9}), isEmpty);
      expect(printersGone(<int>{}, {1}), isEmpty);
    });
  });

  // The wiring itself, on the demo: its server lives in the process, so the
  // service can really start, fetch the printer list and publish. The real tick
  // is half an hour; here it is a few hundred milliseconds.
  group('a printer deleted while the service runs', () {
    const channel = MethodChannel(
      'page.codeberg.morganmlgman.bambuddy/ongoing',
    );

    late List<MethodCall> posts;
    late DemoBackend demo;
    late int printingBefore;
    PrintMonitorTaskHandler? handler;

    Future<void> until(bool Function() done, {String? what}) async {
      final end = DateTime.now().add(const Duration(seconds: 8));
      while (!done()) {
        if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    setUp(() {
      posts = [];
      printingBefore = DemoBackend.printingPrinters;
      demo = DemoBackend.instance;
      DemoBackend.instance = DemoBackend.fresh();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            posts.add(call);
            return true;
          });
      // The count the service reads at start (it overwrites the static), set
      // here rather than left to the default.
      SharedPreferences.setMockInitialValues({
        'demo_printing_count': 2,
        'server_profile': jsonEncode(
          const ServerProfile(
            baseUrl: DemoConfig.baseUrl,
            authMode: AuthMode.none,
          ).toJson(),
        ),
      });
      handler = PrintMonitorTaskHandler(
        serverRefreshEvery: const Duration(milliseconds: 150),
      );
    });

    tearDown(() async {
      await handler?.onDestroy(DateTime.now(), false);
      // What `onStart` left running (the widget publishes, the first probes).
      await pumpEventQueue();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      SharedPreferences.setMockInitialValues({});
      DemoBackend.instance = demo;
      DemoBackend.printingPrinters = printingBefore;
    });

    /// What the ongoing notification says now: the last post, not any earlier
    /// one, since a stale post says nothing about the state it is in.
    Map<Object?, Object?>? now() =>
        posts.isEmpty ? null : posts.last.arguments as Map<Object?, Object?>;

    bool showsTwoPrinting() => now()?['title'] == '2 printing';

    test(
      'stops being counted on the ongoing notification, and stays gone',
      () async {
        await handler!.onStart(DateTime.now(), TaskStarter.developer);
        await until(showsTwoPrinting, what: 'two printers printing');

        // Printer 1 is one of the two printing machines (`DemoBackend`).
        DemoBackend.instance.removePrinter(1);

        // Still a print going on, now one printer's: not the notification gone
        // idle, which would also say something other than "2 printing".
        await until(
          () => now()?['printing'] == true && !showsTwoPrinting(),
          what: 'the notification with the one printer that is left',
        );

        // A frame from a printer that is still there carries the whole map into
        // the monitor again; a printer kept in it would come back with that. An
        // unchanged notification is not posted again, so what is expected here
        // is silence, and the mutation of not trimming the map is what shows the
        // test can see the difference.
        //
        // Any post, not the last: the next tick of the roster check can undo a
        // wrong one within the wait, and a wrong one is what is being looked
        // for.
        posts.clear();
        DemoBackend.pokeSockets();
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(
          posts.any((c) => (c.arguments as Map)['title'] == '2 printing'),
          isFalse,
        );
      },
    );

    // No frame follows when every printer is gone, so nothing but the roster
    // check can end the notification.
    test('with none left, the ongoing notification ends', () async {
      await handler!.onStart(DateTime.now(), TaskStarter.developer);
      await until(showsTwoPrinting, what: 'two printers printing');

      for (final id in DemoBackend.instance.printerIds) {
        DemoBackend.instance.removePrinter(id);
      }

      await until(
        () => now()?['printing'] == false,
        what: 'the monitoring notification back to idle',
      );
    });
  });

  // The whole path, on the demo: the service asks the inventory over HTTP,
  // records what is low as the baseline, and alerts for a spool that drops
  // below its threshold while it watches. The real safety-net tick is five
  // minutes; here it is a hundred milliseconds.
  group('low filament from the spool inventory', () {
    const plugin = MethodChannel('dexterous.com/flutter/local_notifications');
    // Printer 1 holds spool 1 in slot 0 of its AMS (`DemoBackend`), 66% full,
    // against the demo server's own threshold of 15.
    const spoolId = 1;

    late List<MethodCall> shown;
    late DemoBackend demo;
    late int printingBefore;
    PrintMonitorTaskHandler? handler;

    Dio demoDio() => Dio(BaseOptions(baseUrl: DemoConfig.baseUrl))
      ..httpClientAdapter = DemoHttpClientAdapter(DemoBackend.instance.handle);

    Future<void> useSpool(double used) async {
      await demoDio().patch<dynamic>(
        '/api/v1/inventory/spools/$spoolId',
        data: {'weight_used': used},
      );
    }

    bool alertedForPrinter1() => shown.any(
      (c) =>
          c.method == 'show' &&
          (c.arguments as Map)['id'] == 9 * alertBandWidth + 1,
    );

    Future<void> until(bool Function() done, {required String what}) async {
      final end = DateTime.now().add(const Duration(seconds: 8));
      while (!done()) {
        if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    setUp(() {
      shown = [];
      // The plugin picks its Android half by platform, and only that half talks
      // over the channel below.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      printingBefore = DemoBackend.printingPrinters;
      demo = DemoBackend.instance;
      DemoBackend.instance = DemoBackend.fresh();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(plugin, (call) async {
            shown.add(call);
            // `initialize` is typed to answer a bool; the rest may say nothing.
            return call.method == 'initialize' ? true : null;
          });
      SharedPreferences.setMockInitialValues({
        'demo_printing_count': 2,
        'server_profile': jsonEncode(
          const ServerProfile(
            baseUrl: DemoConfig.baseUrl,
            authMode: AuthMode.none,
          ).toJson(),
        ),
        // Off until the user switches it on, like every event that is not
        // actionable by default.
        'notification_prefs': NotificationPrefs(
          enabled: {
            ...NotificationPrefs.defaults.enabled,
            NotifEvent.lowFilament,
          },
        ).encode(),
      });
      handler = PrintMonitorTaskHandler(
        lowStockRefreshEvery: const Duration(milliseconds: 100),
      );
    });

    tearDown(() async {
      await handler?.onDestroy(DateTime.now(), false);
      await pumpEventQueue();
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(plugin, null);
      SharedPreferences.setMockInitialValues({});
      DemoBackend.instance = demo;
      DemoBackend.printingPrinters = printingBefore;
    });

    test(
      'the feed is stopped with the service, so a late answer is dropped',
      () async {
        await handler!.onStart(DateTime.now(), TaskStarter.developer);
        final feed = handler!.lowStockFeed;
        expect(feed, isNotNull);
        expect(feed!.stopped, isFalse);
        await handler!.onDestroy(DateTime.now(), false);
        expect(feed.stopped, isTrue);
      },
    );

    test(
      'a spool that runs low while the service watches is announced',
      () async {
        await handler!.onStart(DateTime.now(), TaskStarter.developer);
        // Long enough for the first look, which only records.
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(alertedForPrinter1(), isFalse);

        await useSpool(900); // 10% left, below the demo's 15
        await until(alertedForPrinter1, what: 'the low filament alert');
      },
    );

    test('one that was already low when the service started is not', () async {
      await useSpool(900);
      await handler!.onStart(DateTime.now(), TaskStarter.developer);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(alertedForPrinter1(), isFalse);
    });

    test(
      'a spool above the demo\'s threshold but under the old 20% is not',
      () async {
        await handler!.onStart(DateTime.now(), TaskStarter.developer);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await useSpool(830); // 17% left: low for 20, not for the server's 15
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(alertedForPrinter1(), isFalse);
      },
    );
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

  group('the ongoing notification goes out natively when it can', () {
    // The same channel name `FgsNotificationService` holds. Declared here rather
    // than exported from the library: the name is the contract with the Kotlin
    // side, and a test that reads it from the code under test would pass while
    // the two drifted apart.
    const channel = MethodChannel(
      'page.codeberg.morganmlgman.bambuddy/ongoing',
    );

    late List<MethodCall> calls;

    /// Installs a handler answering [answer]; null leaves the channel unserved,
    /// which is what a `MissingPluginException` looks like from Dart.
    void serve(Object? answer) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return answer;
          });
    }

    FgsNotificationService build() =>
        FgsNotificationService(RecordingNotifications(), en);

    setUp(() => calls = []);

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('a progress update reaches the channel and not the plugin', () async {
      serve(true);

      await build().showOngoing(title: 'cube.3mf', body: '42%', progress: 42);

      expect(calls.single.method, 'show');
      expect(calls.single.arguments, {
        'title': 'cube.3mf',
        'body': '42%',
        'progress': 42,
        'printing': true,
      });
      expect(platform.updates, isEmpty, reason: 'the plugin was not asked');
    });

    test(
      'clearing says the print is over, not that it is unmeasured',
      () async {
        // Two different nulls reach the native side, and only `printing` tells
        // them apart: no print at all leaves no bar, while a print before its
        // first percent gets the animated one. On Android 16 the first also has
        // to drop the ProgressStyle, the chip and the promotion request.
        serve(true);

        await build().clearOngoing();

        expect(calls.single.arguments['progress'], isNull);
        expect(calls.single.arguments['printing'], isFalse);
        expect(platform.updates, isEmpty);
      },
    );

    test('a print with no measured position keeps printing true', () async {
      serve(true);

      await build().showOngoing(title: 'cube.3mf', body: '0%', progress: null);

      expect(calls.single.arguments['progress'], isNull);
      expect(calls.single.arguments['printing'], isTrue);
    });

    test('a refusal falls back to the plugin with the same content', () async {
      // `false` is the native side saying it had no notification to rebuild —
      // the race with `startForeground`, and every OEM that refuses the
      // recovery. Losing the bar is fine; losing the notification is not.
      serve(false);

      await build().showOngoing(title: 'cube.3mf', body: '42%', progress: 42);

      expect(calls, hasLength(1));
      expect(platform.updates.single, ('cube.3mf', '42%'));
    });

    test('an unserved channel falls back the same way', () async {
      // The watch flavor, which strips the Application that registers the
      // handler — and every test that installs none.
      await build().showOngoing(title: 'cube.3mf', body: '42%', progress: 42);

      expect(platform.updates.single, ('cube.3mf', '42%'));
    });

    test('a re-post after a swipe carries the progress, not a null', () async {
      // Android 14+ lets the user swipe the service's notification away. What
      // comes back has to be what was there, bar included.
      serve(true);
      final fgs = build();
      await fgs.showOngoing(title: 'cube.3mf', body: '42%', progress: 42);

      await fgs.repost();

      expect(calls, hasLength(2));
      expect(calls.last.arguments['progress'], 42);
      expect(calls.last.arguments['title'], 'cube.3mf');
    });

    test('the log records a change of path, not every post', () async {
      // A print posts hundreds of these and the answer is the same every
      // time; what a report needs is whether this device ever took the
      // native path at all.
      final recorder = DiagnosticRecorder(
        sessions: MemorySessionStore(),
        redactor: bambuddyRedactor,
        sessionDuration: recordingLimit,
        sessionBytes: recordingSizeLimit,
        loadFacts: () async =>
            const SessionFacts(app: '0.13.0+1300000', extra: {}),
        resolveDirectory: () async => null,
      );
      addTearDown(recorder.discard);

      await recorder.start();
      serve(true);
      final fgs = build();
      await fgs.showOngoing(title: 'a', body: '1%', progress: 1);
      await fgs.showOngoing(title: 'a', body: '2%', progress: 2);
      serve(false);
      await fgs.showOngoing(title: 'a', body: '3%', progress: 3);
      final jsonl = await recorder.stop();

      final records = [
        for (final line in const LineSplitter().convert(jsonl))
          if (jsonDecode(line) case final Map<String, Object?> row
              when row['evt'] == 'ongoing_native')
            row,
      ];
      expect(records, hasLength(2), reason: 'three posts, two paths');
      expect(records.first['native'], true);
      expect(records.last['native'], false);
    });
  });
}
