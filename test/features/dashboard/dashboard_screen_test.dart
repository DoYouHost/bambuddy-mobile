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

/// Onboarding powiadomień w initState czyta te providery; w teście są nieaktywne.
class _NoopNotifications implements NotificationService {
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => false;
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

/// Inert WS: testy dashboardu sprawdzają render z pollingu, nie żywy socket.
class _InertStatusesNotifier extends PrinterStatusesNotifier {
  @override
  Map<int, PrinterStatus> build() => const {};
}

/// Inert gniazdka: bez pollingu serwera (nagłówek liczy sumę mocy z tego
/// providera, ale testy nie sprawdzają gniazdek).
class _InertSmartPlugsNotifier extends SmartPlugsNotifier {
  @override
  SmartPlugsState build() => const SmartPlugsState();
}

/// Usługa w tle bez Androida pod spodem — testy cyklu życia sprawdzają, komu
/// dashboard oddaje i odbiera pracę, nie samą usługę.
class _FakeBackgroundMonitor implements BackgroundMonitor {
  @override
  Future<bool> start() async => true;
  @override
  Future<void> stop() async {}
  @override
  Future<bool> isRunning() async => false;
  @override
  void syncDiagnostics() {}
}

/// Relay zegarka tknięty tylko po to, żeby nie sięgał po kanał platformy.
class _InertWearRelay extends WearRelayHandler {
  _InertWearRelay() : super(watch: WatchConnectivity(), dio: () => null);
  @override
  void start() {}
  @override
  void stop() {}
}

/// Liczy samo przekazanie pałeczki; co notifier robi w środku, sprawdza jego
/// własny test.
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
        builder: (_, _) => const Scaffold(body: Text('EKRAN SETUP')),
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

  testWidgets('pad pierwszego ładowania pokazuje błąd i przycisk ponowienia',
      (tester) async {
    await tester
        .pumpWidget(_app(const DashboardState(
            error: NetworkException(AppErrorCode.serverUnreachable))));

    expect(find.textContaining('Serwer nieosiągalny'), findsOneWidget);
    expect(find.text('Spróbuj ponownie'), findsOneWidget);
    expect(find.byType(ConnectionBanner), findsNothing);
  });

  testWidgets('wyszukiwarka filtruje listę po nazwie', (tester) async {
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

  testWidgets('nagłówek pokazuje liczbę drukujących i następną wolną',
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

  testWidgets('szukanie zdjęcia oddaje pole usłudze w tle i odbiera po powrocie',
      (tester) async {
    // Obie kopie naraz pobierałyby to samo zdjęcie i deptały sobie zapisy do
    // wspólnej pamięci alertów — przegrany wpis znika, a powiadomienie zostaje
    // bez zdjęcia na zawsze.
    final spy = _SpyFinishPhoto();
    await tester.pumpWidget(_app(
      const DashboardState(
        printers: [PrinterWithStatus(printer: Printer(id: 1, name: 'X1C'))],
      ),
      extra: [
        finishPhotoNotifierProvider.overrideWithValue(spy),
        backgroundMonitorProvider.overrideWithValue(_FakeBackgroundMonitor()),
        wearRelayHandlerProvider.overrideWithValue(_InertWearRelay()),
      ],
    ));
    await tester.pumpAndSettle();

    // AppLifecycleListener rozpoznaje przejścia, nie stany — stąd pełna droga.
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
    expect(spy.stops, 1, reason: 'usługa w tle przejmuje szukanie');
    expect(spy.starts, 0);

    await drive(const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    expect(spy.starts, 1, reason: 'dopiero gdy usługa jest już zatrzymana');

    // Powrót wznowił polling; bez tego jego timery przeżyją drzewo widgetów.
    await drive(toBackground);
  });

  group('ostrzeżenie o odrzuconym haśle', () {
    const state = DashboardState(
      printers: [PrinterWithStatus(printer: Printer(id: 1, name: 'X1C'))],
    );

    testWidgets('flaga ustawiona → dialog po pierwszej klatce', (tester) async {
      // The flag is set from an interceptor or the background isolate, both
      // invisible; without this dialog the app just stops loading anything.
      await _prefs.setBool('sign_in_required', true);

      await tester.pumpWidget(_app(state));
      await tester.pumpAndSettle();

      expect(find.text('Zaloguj się ponownie'), findsOneWidget);
      expect(find.textContaining('odrzucił zapisane hasło'), findsOneWidget);
    });

    testWidgets('flaga zapisana przez obcy izolat też otwiera dialog',
        (tester) async {
      // Both writers (background service, action callback) run in their own
      // isolate, so the flag reaches this one only on disk. Reading the cache
      // this handle started with would leave the app silently unable to load.
      SharedPreferences.setMockInitialValues({
        'notif_onboarded': true,
        'sign_in_required': true,
      });
      expect(_prefs.getBool('sign_in_required'), isNot(isTrue),
          reason: 'cache tego izolatu nie może znać obcego zapisu');

      await tester.pumpWidget(_app(state));
      await tester.pumpAndSettle();

      expect(find.text('Zaloguj się ponownie'), findsOneWidget);
    });

    testWidgets('bez flagi nie ma dialogu', (tester) async {
      await tester.pumpWidget(_app(state));
      await tester.pumpAndSettle();

      expect(find.text('Zaloguj się ponownie'), findsNothing);
    });

    testWidgets('„Zaloguj" prowadzi na ekran konfiguracji', (tester) async {
      await _prefs.setBool('sign_in_required', true);

      await tester.pumpWidget(_routedApp(state));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Zaloguj'));
      await tester.pumpAndSettle();

      expect(find.text('EKRAN SETUP'), findsOneWidget);
    });

    testWidgets('„Później" zamyka dialog, ale flaga zostaje na kolejny start',
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
