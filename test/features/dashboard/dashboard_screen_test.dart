import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/notifications/notification_service.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/core/api/ws_client.dart';
import 'package:bambuddy_mobile/features/dashboard/dashboard_screen.dart';
import 'package:bambuddy_mobile/features/dashboard/providers.dart';
import 'package:bambuddy_mobile/features/dashboard/smart_plugs_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/connection_banner.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {}
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

Widget _app(DashboardState state) => ProviderScope(
      overrides: [
        dashboardProvider.overrideWith(() => _FakeDashboardNotifier(state)),
        serverProfileProvider.overrideWith(_FakeProfileNotifier.new),
        printerStatusesProvider.overrideWith(_InertStatusesNotifier.new),
        smartPlugsProvider.overrideWith(_InertSmartPlugsNotifier.new),
        sharedPreferencesProvider.overrideWithValue(_prefs),
        notificationServiceProvider.overrideWithValue(_NoopNotifications()),
        wsConnectionStateProvider.overrideWith(
          (ref) => Stream.value(WsConnectionState.connected),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('pl'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DashboardScreen(),
      ),
    );

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
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
}
