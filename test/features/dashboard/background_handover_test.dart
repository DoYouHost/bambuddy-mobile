import 'dart:async';

import 'package:bambuddy_mobile/core/api/ws_messages.dart';
import 'package:bambuddy_mobile/core/notifications/background_monitor.dart';
import 'package:bambuddy_mobile/core/notifications/background_sync.dart';
import 'package:bambuddy_mobile/core/notifications/finish_alert_memory.dart';
import 'package:bambuddy_mobile/core/notifications/finish_photo_notifier.dart';
import 'package:bambuddy_mobile/core/watch/wear_relay_handler.dart';
import 'package:bambuddy_mobile/features/dashboard/background_handover.dart';
import 'package:bambuddy_mobile/features/notifications/finish_photo_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

import '../../helpers.dart';

/// Who watches the printers across the app's lifecycle. Run on a bare
/// container on purpose: no screen is mounted in any of these, which is the
/// point of the hand-over living in the app.
void main() {
  late SharedPreferences prefs;
  late List<String> order;
  late _Service service;
  late _Relay relay;
  late _Hunt hunt;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    order = [];
    service = _Service(order);
    relay = _Relay(order);
    hunt = _Hunt(order, prefs);
  });

  ProviderContainer app(
    WidgetTester tester, {
    bool profile = true,
    List<Override> extra = const [],
  }) {
    final container = ProviderContainer(
      retry: neverRetry,
      overrides: layerOverrides([
        sharedPreferencesProvider.overrideWithValue(prefs),
        credentialsStoreProvider.overrideWithValue(InMemoryCredentialsStore()),
        profile ? fakeServerProfileOverride() : noServerProfileOverride,
        backgroundMonitorProvider.overrideWithValue(service),
        wearRelayHandlerProvider.overrideWithValue(relay),
        finishPhotoNotifierProvider.overrideWithValue(profile ? hunt : null),
        tokenRefresherProvider.overrideWithValue(null),
        cameraTokenRefresherProvider.overrideWithValue(null),
        mediaAuthRefresherProvider.overrideWithValue(null),
      ], extra),
    );
    addTearDown(container.dispose);
    return container;
  }

  // AppLifecycleListener recognises transitions, not states.
  Future<void> background(WidgetTester tester) async {
    for (final s in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump();
  }

  Future<void> foreground(WidgetTester tester) async {
    for (final s in const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump();
  }

  Future<void> launch(WidgetTester tester, ProviderContainer container) async {
    container.read(backgroundHandoverProvider).start();
    await tester.pump();
    order.clear();
  }

  group('coming up', () {
    // A service Android restarted after a swipe-away answers the watch and
    // hunts photos on its own. The relay used to start in `app.dart` before
    // the dashboard's first frame had stopped it.
    testWidgets('a surviving service is stopped before anything is taken', (
      tester,
    ) async {
      service.running = true;

      app(tester).read(backgroundHandoverProvider).start();
      await tester.pump();

      expect(order, ['service stopped', 'relay started', 'hunt started']);
    });

    testWidgets('with no service running, the relay and the hunt start', (
      tester,
    ) async {
      app(tester).read(backgroundHandoverProvider).start();
      await tester.pump();

      expect(order, ['relay started', 'hunt started']);
    });

    testWidgets('started twice, it listens once', (tester) async {
      final handover = app(tester).read(backgroundHandoverProvider)
        ..start()
        ..start();
      await tester.pump();
      order.clear();

      await background(tester);

      expect(order.where((e) => e == 'service started'), hasLength(1));
      handover.dispose();
    });

    // The watch is told the phone has no server; nothing else exists yet.
    testWidgets('without a server only the relay starts', (tester) async {
      app(tester, profile: false).read(backgroundHandoverProvider).start();
      await tester.pump();

      expect(order, ['relay started']);
    });
  });

  group('pause and resume', () {
    testWidgets('the service takes over, then gives everything back', (
      tester,
    ) async {
      await launch(tester, app(tester));

      await background(tester);
      expect(order, ['relay stopped', 'hunt stopped', 'service started']);
      expect(service.running, isTrue);

      order.clear();
      await foreground(tester);
      expect(order, ['service stopped', 'relay started', 'hunt started']);
    });

    // A stop that threw says nothing about whether the service is still up.
    // Taking the relay and the hunt anyway risks two of each; leaving them
    // costs this foreground session its photos, which is the cheaper mistake.
    testWidgets('a stop that fails takes nothing back', (tester) async {
      await launch(tester, app(tester));
      await background(tester);
      order.clear();

      service.stopFails = true;
      // The failure goes on to the uncaught handler, as a bug in the app does.
      Object? uncaught;
      await runZonedGuarded(
        () => foreground(tester),
        (error, _) => uncaught = error,
      );

      expect(uncaught, isStateError);
      expect(order, isEmpty);
    });

    testWidgets('with monitoring switched off the service never starts', (
      tester,
    ) async {
      await prefs.setBool('bg_monitoring_enabled', false);
      await launch(tester, app(tester));

      await background(tester);

      expect(service.running, isFalse);
      expect(order, ['hunt stopped'], reason: 'the relay stays with the UI');
    });

    testWidgets('without a server a pause starts nothing', (tester) async {
      await launch(tester, app(tester, profile: false));

      await background(tester);

      expect(order, isEmpty);
    });

    testWidgets('a notifier rebuilt in the foreground is started', (
      tester,
    ) async {
      final rebuild = StateProvider<int>((_) => 0);
      final container = app(
        tester,
        extra: [
          finishPhotoNotifierProvider.overrideWith((ref) {
            ref.watch(rebuild);
            return _Hunt(order, prefs);
          }),
        ],
      );
      await launch(tester, container);

      container.read(rebuild.notifier).state++;
      // A bare container flushes on a timer, not on a frame.
      await tester.pump(const Duration(milliseconds: 1));

      expect(order, ['hunt started']);
    });

    testWidgets('one rebuilt in the background is left stopped', (
      tester,
    ) async {
      final rebuild = StateProvider<int>((_) => 0);
      final container = app(
        tester,
        extra: [
          finishPhotoNotifierProvider.overrideWith((ref) {
            ref.watch(rebuild);
            return _Hunt(order, prefs);
          }),
        ],
      );
      await launch(tester, container);
      await background(tester);
      order.clear();

      container.read(rebuild.notifier).state++;
      // A bare container flushes on a timer, not on a frame.
      await tester.pump(const Duration(milliseconds: 1));

      expect(order, isEmpty);
    });
  });

  // Starting and stopping the service are platform calls that take time, and
  // the app can change its mind before one lands. Whichever isolate ends up
  // running, it must be exactly one.
  group('a lifecycle change before the last one landed', () {
    testWidgets('paused again while the stop is in the air', (tester) async {
      await launch(tester, app(tester));
      await background(tester);
      order.clear();

      service.stopGate = Completer<void>();
      await foreground(tester);
      await background(tester);
      service.stopGate!.complete();
      await tester.pump();

      expect(order, isNot(contains('hunt started')));
      expect(order, isNot(contains('relay started')));
      expect(service.running, isTrue, reason: 'the service has to watch');
    });

    testWidgets('paused while a surviving service is being stopped', (
      tester,
    ) async {
      service
        ..running = true
        ..stopGate = Completer<void>();
      app(tester).read(backgroundHandoverProvider).start();
      await tester.pump();

      await background(tester);
      service.stopGate!.complete();
      await tester.pump();

      expect(order, isNot(contains('hunt started')));
      expect(order, isNot(contains('relay started')));
      expect(service.running, isTrue, reason: 'the service has to watch');
    });

    testWidgets('resumed while the start is in the air', (tester) async {
      await launch(tester, app(tester));

      service.startGate = Completer<void>();
      await background(tester);
      await foreground(tester);
      service.startGate!.complete();
      await tester.pump();

      expect(service.running, isFalse, reason: 'the app is in the foreground');
      expect(order.last, 'hunt started');
    });
  });

  group('the service lane in the log', () {
    /// One record per thing that actually happened to the service. `ui_stop`
    /// used to be written for having *asked*, and the app asks on every
    /// resume whether or not monitoring is on.
    Future<String> record(
      WidgetTester tester,
      Future<void> Function(ProviderContainer container) run,
    ) async {
      final recorder = testRecorder();
      addTearDown(recorder.discard);
      await tester.runAsync(recorder.start);
      await run(app(tester));
      return (await tester.runAsync(recorder.stop))!;
    }

    // The exact field, not the bare word: `ui_stop_survivor` contains it.
    const stopRecord = '"evt":"ui_stop"';

    testWidgets('a resume that stopped nothing writes no stop', (tester) async {
      await prefs.setBool('bg_monitoring_enabled', false);
      final log = await record(tester, (container) async {
        await launch(tester, container);
        await background(tester);
        await foreground(tester);
      });

      expect(log, isNot(contains(stopRecord)));
    });

    testWidgets('a resume that really stopped one writes it', (tester) async {
      final log = await record(tester, (container) async {
        await launch(tester, container);
        await background(tester);
        await foreground(tester);
      });

      expect(log, contains(stopRecord));
      expect(log, contains('"evt":"ui_start"'));
    });

    testWidgets('a survivor stopped at launch has a verb of its own', (
      tester,
    ) async {
      service.running = true;
      final log = await record(
        tester,
        (container) => launch(tester, container),
      );

      expect(log, contains('"evt":"ui_stop_survivor"'));
    });

    testWidgets(
      'switching monitoring off stops a running service and says so',
      (tester) async {
        final log = await record(tester, (container) async {
          await launch(tester, container);
          service.running = true;
          await container
              .read(backgroundHandoverProvider)
              .stopDisabledService();
        });

        expect(service.running, isFalse);
        expect(log, contains('"evt":"ui_stop_disabled"'));
      },
    );
  });
}

/// A service whose start and stop take as long as the test says, and which
/// answers as the real one does: by whether one is running right then.
class _Service implements BackgroundMonitor {
  _Service(this._order);

  final List<String> _order;
  bool running = false;
  Completer<void>? startGate;
  Completer<void>? stopGate;
  bool stopFails = false;

  @override
  Future<bool> start() async {
    if (running) return false;
    await startGate?.future;
    running = true;
    _order.add('service started');
    return true;
  }

  @override
  Future<bool> stop() async {
    if (stopFails) throw StateError('platform refused');
    if (!running) return false;
    await stopGate?.future;
    running = false;
    _order.add('service stopped');
    return true;
  }

  @override
  Future<bool> isRunning() async => running;

  @override
  void sync(BackgroundSync what) {}
}

class _Relay extends WearRelayHandler {
  _Relay(this._order) : super(watch: WatchConnectivity(), dio: () => null);

  final List<String> _order;

  @override
  Future<void> start() async => _order.add('relay started');

  @override
  Future<void> stop() async => _order.add('relay stopped');
}

/// Counts the hand-off alone; what the notifier does inside is covered by its
/// own test.
class _Hunt extends FinishPhotoNotifier {
  _Hunt(this._order, SharedPreferences prefs)
    : super(
        updates: const Stream<WsArchiveUpdated>.empty(),
        fetchArchive: (_) async => null,
        recentArchives: (_) async => const [],
        fetchPicture: (_, _) async => null,
        notifications: RecordingNotifications(),
        memory: FinishAlertMemory(prefs),
        isEnabled: () => true,
      );

  final List<String> _order;

  @override
  void start() => _order.add('hunt started');

  @override
  Future<void> stop() async => _order.add('hunt stopped');
}
