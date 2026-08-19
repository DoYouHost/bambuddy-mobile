import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/notifications/notification_prefs.dart';
import 'package:bambuddy_mobile/core/notifications/notification_service.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/core/api/ws_client.dart';
import 'package:bambuddy_mobile/core/api/ws_messages.dart';
import 'package:bambuddy_mobile/core/notifications/background_monitor.dart';
import 'package:bambuddy_mobile/core/notifications/finish_alert_memory.dart';
import 'package:bambuddy_mobile/core/notifications/finish_photo_notifier.dart';
import 'package:bambuddy_mobile/core/watch/wear_relay_handler.dart';
import 'package:bambuddy_mobile/features/dashboard/dashboard_screen.dart';
import 'package:bambuddy_mobile/features/notifications/finish_photo_providers.dart';
import 'package:watch_connectivity/watch_connectivity.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/dashboard/smart_plugs_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/connection_banner.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// Notification onboarding in initState reads these providers; inert in tests.
class _NoopNotifications implements NotificationService {
  _NoopNotifications({this.permissionGranted = false});

  /// What the system answers to the permission request — denial is the default,
  /// because that is what the test host looks like.
  final bool permissionGranted;

  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => permissionGranted;
  @override
  Future<void> showOngoing({
    required String title,
    required String body,
    required int progress,
  }) async {}
  @override
  Future<void> clearOngoing() async {}
  @override
  Future<void> showAlert({
    required NotifEvent event,
    required int printerId,
    required int id,
    required String title,
    required String body,
    String? payload,
    List<NotificationAction>? actions,
    AlertPicture? picture,
  }) async {}
  @override
  Future<bool> isAlertActive(int id) async => true;
}

late SharedPreferences _prefs;

class _FakeDashboardNotifier extends DashboardNotifier {
  _FakeDashboardNotifier(this._fixed);

  final DashboardState _fixed;

  @override
  DashboardState build() => _fixed;

  @override
  Future<void> refresh() async {}
}

class _FakeProfileNotifier extends ServerProfileNotifier {
  @override
  ServerProfile? build() => const ServerProfile(
        baseUrl: 'http://s.local:8000',
        authMode: AuthMode.none,
      );
}

/// Inert WS: dashboard tests check the render from polling, not a live socket.
class _InertStatusesNotifier extends PrinterStatusesNotifier {
  @override
  Map<int, PrinterStatus> build() => const {};
}

/// Inert smart plugs: no server polling (the header sums power from this
/// provider, but these tests do not check plugs).
class _InertSmartPlugsNotifier extends SmartPlugsNotifier {
  @override
  SmartPlugsState build() => const SmartPlugsState();
}

/// Background service with no Android underneath — the lifecycle tests check who
/// the dashboard hands work to and takes it back from, not the service itself.
class _FakeBackgroundMonitor implements BackgroundMonitor {
  _FakeBackgroundMonitor({this.running = false});

  /// Whether Android is keeping the service alive from a previous app launch.
  final bool running;
  int stops = 0;

  @override
  Future<bool> start() async => true;
  @override
  Future<void> stop() async => stops++;
  @override
  Future<bool> isRunning() async => running;
  @override
  void syncDiagnostics() {}
}

/// Watch relay stubbed only so it does not reach for the platform channel.
class _InertWearRelay extends WearRelayHandler {
  _InertWearRelay() : super(watch: WatchConnectivity(), dio: () => null);
  @override
  void start() {}
  @override
  void stop() {}
}

/// Counts the hand-off alone; what the notifier does inside is covered by its
/// own test.
class _SpyFinishPhoto extends FinishPhotoNotifier {
  _SpyFinishPhoto()
      : super(
          updates: const Stream<WsArchiveUpdated>.empty(),
          fetchArchive: (_) async => null,
          recentArchives: (_) async => const [],
          fetchPicture: (_, _) async => null,
          notifications: _NoopNotifications(),
          memory: FinishAlertMemory(_prefs),
          isEnabled: () => true,
        );

  int starts = 0;
  int stops = 0;

  @override
  void start() => starts++;

  @override
  Future<void> stop() async => stops++;
}

List<Override> _overrides(DashboardState state) => [
      dashboardProvider.overrideWith(() => _FakeDashboardNotifier(state)),
      serverProfileProvider.overrideWith(_FakeProfileNotifier.new),
      printerStatusesProvider.overrideWith(_InertStatusesNotifier.new),
      smartPlugsProvider.overrideWith(_InertSmartPlugsNotifier.new),
      inertFirmwareOverride,
      inertTotalPrintHoursOverride,
      sharedPreferencesProvider.overrideWithValue(_prefs),
      // Touched on the very first frame (taking over from a surviving service), so
      // without a stub every test here would reach for the platform channel.
      backgroundMonitorProvider.overrideWithValue(_FakeBackgroundMonitor()),
      notificationServiceProvider.overrideWithValue(_NoopNotifications()),
      wsConnectionStateProvider.overrideWith(
        (ref) => Stream.value(WsConnectionState.connected),
      ),
    ];

Widget _app(DashboardState state, {List<Override> extra = const []}) =>
    ProviderScope(
      overrides: [..._overrides(state), ...extra],
      child: MaterialApp(
        locale: const Locale('pl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DashboardScreen(),
      ),
    );

/// Same dashboard, but reachable through a router — for the paths that navigate
/// away (`context.go('/setup')`).
Widget _routedApp(DashboardState state) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
      GoRoute(
        path: '/setup',
        builder: (_, _) => const Scaffold(body: Text('SETUP SCREEN')),
      ),
    ],
  );
  return ProviderScope(
    overrides: _overrides(state),
    child: MaterialApp.router(
      locale: const Locale('pl'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  setUp(() async {
    // Notification onboarding also runs after the first frame; mark it done so
    // no test depends on another having run first.
    await _prefs.setBool('notif_onboarded', true);
    await _prefs.remove('sign_in_required');
  });

  testWidgets(
      'pad pollingu pokazuje baner NAD ostatnimi danymi, nie zamiast nich',
      (tester) async {
    await tester.pumpWidget(_app(const DashboardState(
      printers: [
        PrinterWithStatus(printer: Printer(id: 1, name: 'X1C Warsztat')),
      ],
      error: NetworkException(AppErrorCode.serverUnreachable),
    )));

    expect(find.byType(ConnectionBanner), findsOneWidget);
    expect(find.text('X1C Warsztat'), findsOneWidget);
  });

  testWidgets('a first-load failure shows the error and a retry button',
      (tester) async {
    await tester
        .pumpWidget(_app(const DashboardState(
            error: NetworkException(AppErrorCode.serverUnreachable))));

    expect(find.textContaining('Serwer nieosiągalny'), findsOneWidget);
    expect(find.text('Spróbuj ponownie'), findsOneWidget);
    expect(find.byType(ConnectionBanner), findsNothing);
  });

  testWidgets('the search box filters the list by name', (tester) async {
    await tester.pumpWidget(_app(const DashboardState(printers: [
      PrinterWithStatus(printer: Printer(id: 1, name: 'X1C Warsztat')),
      PrinterWithStatus(printer: Printer(id: 2, name: 'A1 mini')),
    ])));

    expect(find.text('X1C Warsztat'), findsOneWidget);
    expect(find.text('A1 mini'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'mini');
    await tester.pumpAndSettle();

    expect(find.text('A1 mini'), findsOneWidget);
    expect(find.text('X1C Warsztat'), findsNothing);
  });

  testWidgets('the header shows how many are printing and the next one free',
      (tester) async {
    await tester.pumpWidget(_app(const DashboardState(printers: [
      PrinterWithStatus(
        printer: Printer(id: 1, name: 'X1C Warsztat'),
        status: PrinterStatus(
            id: 1, connected: true, progress: 80, remainingTime: 57),
      ),
      PrinterWithStatus(printer: Printer(id: 2, name: 'A1 mini')),
    ])));

    expect(find.text('1 drukuje'), findsOneWidget);
    expect(find.textContaining('Następna wolna'), findsOneWidget);
  });

  testWidgets('a service that outlived the previous launch is stopped',
      (tester) async {
    // After a swipe-away Android revives the service and it survives the next
    // launch. `onResume` does not catch it, because that fires on a transition and
    // a cold start is already "resumed" — so everything it froze at its own start
    // (notification switches, server profile) would outlive the whole session.
    final monitor = _FakeBackgroundMonitor(running: true);
    await tester.pumpWidget(_app(
      const DashboardState(
        printers: [PrinterWithStatus(printer: Printer(id: 1, name: 'X1C'))],
      ),
      extra: [backgroundMonitorProvider.overrideWithValue(monitor)],
    ));
    await tester.pumpAndSettle();

    expect(monitor.stops, 1);
  });

  testWidgets('a refused permission does not spend the one-time onboarding',
      (tester) async {
    // Writing the flag before asking burned the one automatic prompt on a run the
    // user may have dismissed by accident — and Android keeps showing its dialog
    // until it is refused twice.
    await _prefs.setBool('notif_onboarded', false);

    await tester.pumpWidget(_app(
      const DashboardState(
        printers: [PrinterWithStatus(printer: Printer(id: 1, name: 'X1C'))],
      ),
      extra: [
        notificationServiceProvider.overrideWithValue(_NoopNotifications()),
      ],
    ));
    await tester.pumpAndSettle();

    expect(_prefs.getBool('notif_onboarded'), isNot(isTrue),
        reason: 'refused → we ask again on the next launch');
  });

  testWidgets('a granted permission closes onboarding for good', (tester) async {
    await _prefs.setBool('notif_onboarded', false);

    await tester.pumpWidget(_app(
      const DashboardState(
        printers: [PrinterWithStatus(printer: Printer(id: 1, name: 'X1C'))],
      ),
      extra: [
        notificationServiceProvider
            .overrideWithValue(_NoopNotifications(permissionGranted: true)),
      ],
    ));
    await tester.pumpAndSettle();

    expect(_prefs.getBool('notif_onboarded'), isTrue);
  });

  testWidgets('the photo hunt yields to the background service and takes it back '
      'on return',
      (tester) async {
    // Both copies at once would fetch the same photo and trample each other's
    // writes to the shared alert memory — the losing entry disappears and its
    // notification stays without a photo forever.
    final spy = _SpyFinishPhoto();
    await tester.pumpWidget(_app(
      const DashboardState(
        printers: [PrinterWithStatus(printer: Printer(id: 1, name: 'X1C'))],
      ),
      extra: [
        finishPhotoNotifierProvider.overrideWithValue(spy),
        wearRelayHandlerProvider.overrideWithValue(_InertWearRelay()),
      ],
    ));
    await tester.pumpAndSettle();

    // AppLifecycleListener recognises transitions, not states — hence the full path.
    Future<void> drive(List<AppLifecycleState> states) async {
      for (final s in states) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
      await tester.pumpAndSettle();
    }

    const toBackground = [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ];

    await drive(toBackground);
    expect(spy.stops, 1, reason: 'the background service takes over the hunt');
    expect(spy.starts, 0);

    await drive(const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    expect(spy.starts, 1, reason: 'only once the service is already stopped');

    // Returning resumed polling; without this its timers outlive the widget tree.
    await drive(toBackground);
  });

  group('rejected-password warning', () {
    const state = DashboardState(
      printers: [PrinterWithStatus(printer: Printer(id: 1, name: 'X1C'))],
    );

    testWidgets('flag set → dialog after the first frame', (tester) async {
      // The flag is set from an interceptor or the background isolate, both
      // invisible; without this dialog the app just stops loading anything.
      await _prefs.setBool('sign_in_required', true);

      await tester.pumpWidget(_app(state));
      await tester.pumpAndSettle();

      expect(find.text('Zaloguj się ponownie'), findsOneWidget);
      expect(find.textContaining('odrzucił zapisane hasło'), findsOneWidget);
    });

    testWidgets('a flag written by another isolate opens the dialog too',
        (tester) async {
      // Both writers (background service, action callback) run in their own
      // isolate, so the flag reaches this one only on disk. Reading the cache
      // this handle started with would leave the app silently unable to load.
      SharedPreferences.setMockInitialValues({
        'notif_onboarded': true,
        'sign_in_required': true,
      });
      expect(_prefs.getBool('sign_in_required'), isNot(isTrue),
          reason: "this isolate's cache cannot know the other one's write");

      await tester.pumpWidget(_app(state));
      await tester.pumpAndSettle();

      expect(find.text('Zaloguj się ponownie'), findsOneWidget);
    });

    testWidgets('no flag, no dialog', (tester) async {
      await tester.pumpWidget(_app(state));
      await tester.pumpAndSettle();

      expect(find.text('Zaloguj się ponownie'), findsNothing);
    });

    testWidgets('"Sign in" leads to the setup screen', (tester) async {
      await _prefs.setBool('sign_in_required', true);

      await tester.pumpWidget(_routedApp(state));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Zaloguj'));
      await tester.pumpAndSettle();

      expect(find.text('SETUP SCREEN'), findsOneWidget);
    });

    testWidgets('"Later" closes the dialog, but the flag stays for the next launch',
        (tester) async {
      // The app cannot load anything until the user signs in, so postponing
      // must not be mistaken for resolving it.
      await _prefs.setBool('sign_in_required', true);

      await tester.pumpWidget(_app(state));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Później'));
      await tester.pumpAndSettle();

      expect(find.text('Zaloguj się ponownie'), findsNothing);
      expect(find.text('X1C'), findsOneWidget);
      expect(_prefs.getBool('sign_in_required'), isTrue);
    });
  });
}
