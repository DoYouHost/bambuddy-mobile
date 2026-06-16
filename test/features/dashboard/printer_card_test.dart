import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/models/smart_plug.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/smart_plugs_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/controls_providers.dart'
    show ControlResult;
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/camera/camera_view.dart';
import 'package:bambuddy_mobile/features/dashboard/smart_plugs_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/printer_card.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

class _FakeProfileNotifier extends ServerProfileNotifier {
  @override
  ServerProfile? build() => const ServerProfile(
        baseUrl: 'http://s.local:8000',
        authMode: AuthMode.none,
      );
}

/// Inert gniazdka: testy karty nie sprawdzają smart gniazdek, więc nie pollujemy
/// serwera ani nie zbrojnimy timera (analogicznie do inertnego WS w testach).
class _InertSmartPlugsNotifier extends SmartPlugsNotifier {
  @override
  SmartPlugsState build() => const SmartPlugsState();
}

/// Gniazdka ze stałym stanem; rejestruje wywołania [control] (bez sieci/timera),
/// by testy mogły sprawdzić blokadę „odciąć zasilanie w druku" i potwierdzenie.
class _StubSmartPlugsNotifier extends SmartPlugsNotifier {
  _StubSmartPlugsNotifier(this._fixed);

  final SmartPlugsState _fixed;
  final List<({int id, SmartPlugAction action})> calls = [];

  @override
  SmartPlugsState build() => _fixed;

  @override
  Future<ControlResult> control(int plugId, SmartPlugAction action) async {
    calls.add((id: plugId, action: action));
    return ControlResult.ok;
  }
}

/// Drukarka 1 z przypisanym, załączonym gniazdkiem „Szafa" (42 W).
SmartPlugsState _plugState() => SmartPlugsState(
      plugs: const [
        SmartPlug(
          id: 10,
          name: 'Szafa',
          printerId: 1,
          enabled: true,
          showOnPrinterCard: true,
        ),
      ],
      statuses: {
        10: SmartPlugStatus(
          state: 'ON',
          reachable: true,
          energy: const SmartPlugEnergy(power: 42),
        ),
      },
    );

Widget _cardWithPlugs(PrinterWithStatus item, SmartPlugsNotifier stub) =>
    ProviderScope(
      overrides: [
        serverProfileProvider.overrideWith(_FakeProfileNotifier.new),
        cameraTokenProvider.overrideWith((ref) async => 'tok'),
        smartPlugsProvider.overrideWith(() => stub),
      ],
      child: plApp(
        Scaffold(body: SingleChildScrollView(child: PrinterCard(item: item))),
      ),
    );

/// Owija drzewo w ProviderScope — karta zawiera teraz interaktywny pasek
/// sterowania (`_ControlsActions`, ConsumerWidget), więc każdy render karty
/// ze statusem potrzebuje scope'a. Profil = bez auth, token kamery zaślepiony.
Widget _scope(Widget child) => ProviderScope(
      overrides: [
        serverProfileProvider.overrideWith(_FakeProfileNotifier.new),
        cameraTokenProvider.overrideWith((ref) async => 'tok'),
        smartPlugsProvider.overrideWith(_InertSmartPlugsNotifier.new),
      ],
      child: plApp(child),
    );

Widget _cardWithProviders(PrinterWithStatus item) =>
    _scope(Scaffold(body: PrinterCard(item: item)));

void main() {
  testWidgets('karta renderuje nazwę, postęp i temperatury z fixture\'a',
      (tester) async {
    final item = PrinterWithStatus(
      printer: const Printer(id: 1, name: 'X1C Warsztat'),
      status: PrinterStatus.fromJson(
          readFixture('printer_status_printing.json') as Map<String, dynamic>),
    );

    await tester.pumpWidget(_cardWithProviders(item));

    expect(find.text('X1C Warsztat'), findsOneWidget);
    expect(find.text('RUNNING'), findsOneWidget);
    expect(find.text('benchy.3mf'), findsOneWidget);
    expect(find.textContaining('43%'), findsOneWidget);
    expect(find.textContaining('87/203'), findsOneWidget);
    expect(find.textContaining('pozostało 2 h 17 min'), findsOneWidget);
    // Kafelek temperatury: etykieta i wartość to osobne teksty.
    expect(find.text('Dysza'), findsOneWidget);
    expect(find.text('220°'), findsOneWidget);
    expect(find.text('Stół'), findsOneWidget);
    expect(find.text('60°'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('pasek kontrolek: wentylatory, prędkość i światło z fixture\'a',
      (tester) async {
    final item = PrinterWithStatus(
      printer: const Printer(id: 1, name: 'X1C Warsztat'),
      status: PrinterStatus.fromJson(
          readFixture('printer_status_printing.json') as Map<String, dynamic>),
    );

    await tester.pumpWidget(_cardWithProviders(item));

    expect(find.text('53%'), findsOneWidget); // wentylator części
    expect(find.text('73%'), findsOneWidget); // pomocniczy
    expect(find.text('60%'), findsOneWidget); // komory
    // Prędkość i światło są teraz interaktywne: poziom 2 → „Standard",
    // światło włączone → „Wł." na przełączniku.
    expect(find.text('Standard'), findsOneWidget); // prędkość (poziom 2)
    expect(find.text('Wł.'), findsOneWidget); // światło komory włączone
    expect(find.text('Chłodzenie'), findsOneWidget); // nawiew (tryb 0)
    // Wydruk trwa (RUNNING) → dostępne pauza i stop.
    expect(find.text('Pauza'), findsOneWidget);
    expect(find.text('Zatrzymaj'), findsOneWidget);
  });

  testWidgets('pasek kontrolek nie renderuje się bez danych sterowania',
      (tester) async {
    final item = PrinterWithStatus(
      printer: const Printer(id: 9, name: 'A1'),
      status: const PrinterStatus(id: 9, connected: true, state: 'IDLE'),
    );

    await tester.pumpWidget(_cardWithProviders(item));

    // Brak pól wentylatorów/prędkości/światła → żadnych chipów „%".
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('kafelki temperatur: parowanie aktualna/cel, cel 0 ukryty, '
      'numerowana dysza, nieznany klucz', (tester) async {
    final item = PrinterWithStatus(
      printer: const Printer(id: 3, name: 'X2D'),
      status: const PrinterStatus(
        id: 3,
        connected: true,
        state: 'RUNNING',
        temperatures: {
          'bed': 70,
          'bed_target': 70,
          'nozzle': 244,
          'nozzle_target': 245,
          'nozzle_2': 47,
          'nozzle_2_target': 0,
          'chamber': 30,
          'cośdziwnego': 12,
        },
      ),
    );

    await tester.pumpWidget(_cardWithProviders(item));

    // Aktualna i cel jako osobne teksty (aktualna duża, cel mniejszy).
    expect(find.text('Stół'), findsOneWidget);
    expect(find.text('70°'), findsNWidgets(2)); // stół: aktualna + cel
    expect(find.text('Dysza'), findsOneWidget);
    expect(find.text('244°'), findsOneWidget); // aktualna dyszy
    expect(find.text('245°'), findsOneWidget); // cel dyszy
    // Cel = 0 → pokazujemy tylko wartość aktualną.
    expect(find.text('Dysza 2'), findsOneWidget);
    expect(find.text('47°'), findsOneWidget);
    // Bez celu.
    expect(find.text('Komora'), findsOneWidget);
    expect(find.text('30°'), findsOneWidget);
    // Nieznany klucz zostaje surowy.
    expect(find.text('cośdziwnego'), findsOneWidget);
    expect(find.text('12°'), findsOneWidget);
  });

  testWidgets('karta bez statusu zwija się do nagłówka z etykietą OFFLINE',
      (tester) async {
    const item = PrinterWithStatus(
      printer: Printer(id: 2, name: 'A1 mini'),
    );

    await tester.pumpWidget(_cardWithProviders(item));

    expect(find.text('A1 mini'), findsOneWidget);
    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.text('status niedostępny'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('drukarka rozłączona (connected:false) zwija sekcję i pokazuje OFFLINE',
      (tester) async {
    // Mimo nieaktualnych temperatur i stanu RUNNING z ostatniej znanej ramki
    // (sticky merge), rozłączona drukarka nie pokazuje już kafelków ani sterowania.
    const item = PrinterWithStatus(
      printer: Printer(id: 3, name: 'X1C Hala'),
      status: PrinterStatus(
        id: 3,
        connected: false,
        state: 'RUNNING',
        temperatures: {'nozzle': 210.0, 'bed': 60.0},
      ),
    );

    await tester.pumpWidget(_cardWithProviders(item));

    expect(find.text('X1C Hala'), findsOneWidget);
    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.text('RUNNING'), findsNothing);
    expect(find.text('210°'), findsNothing);
    expect(find.textContaining('Szczegóły'), findsNothing);
  });

  group('rozwijane szczegóły (AMS)', () {
    PrinterWithStatus realItem() {
      final frame =
          readFixture('ws_printer_status.json') as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(frame['data'] as Map);
      data['id'] = frame['printer_id'];
      // Miniatura okładki (sieciowa) jest testowana osobno — usuwamy ją tu,
      // by izolować sekcję AMS i nie czekać na request HTTP w teście.
      data.remove('cover_url');
      return PrinterWithStatus(
        printer: const Printer(id: 1, name: 'X2D-3DP'),
        status: PrinterStatus.fromJson(data),
      );
    }

    testWidgets('szczegóły domyślnie zwinięte, rozwijają się po tapnięciu',
        (tester) async {
      await tester.pumpWidget(_scope(Scaffold(
        body: SingleChildScrollView(child: PrinterCard(item: realItem())),
      )));

      // Zwinięte: jest przełącznik „Szczegóły", brak treści AMS.
      expect(find.text('Szczegóły'), findsOneWidget);
      expect(find.text('AMS 1'), findsNothing);

      await tester.tap(find.text('Szczegóły'));
      // Nie pumpAndSettle — faza przygotowania ma nieoznaczony pasek postępu,
      // który animuje się bez końca. Przewijamy tylko czas rozwinięcia (200 ms).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // Rozwinięte: AMS, szpula zewnętrzna i metadane widoczne.
      expect(find.text('Ukryj szczegóły'), findsOneWidget);
      expect(find.text('AMS 1'), findsOneWidget);
      expect(find.text('Szpula zewnętrzna'), findsOneWidget);
      // Materiał slotu z wariantem marki + pozostała ilość.
      expect(find.text('PLA Basic · 66%'), findsOneWidget);
      // Metadane łączności.
      expect(find.textContaining('-59 dBm'), findsOneWidget);
      expect(find.text('Drzwiczki zamknięte'), findsOneWidget);
    });

    testWidgets('brak danych AMS → brak przełącznika szczegółów',
        (tester) async {
      final item = PrinterWithStatus(
        printer: const Printer(id: 9, name: 'A1'),
        status: const PrinterStatus(id: 9, connected: true, state: 'IDLE'),
      );

      await tester.pumpWidget(_cardWithProviders(item));

      expect(find.text('Szczegóły'), findsNothing);
    });
  });

  group('podgląd kamery', () {
    testWidgets('połączona drukarka: przycisk kamery otwiera podgląd',
        (tester) async {
      final item = PrinterWithStatus(
        printer: const Printer(id: 1, name: 'X1C Warsztat'),
        status: const PrinterStatus(id: 1, connected: true, state: 'IDLE'),
      );

      await tester.pumpWidget(_cardWithProviders(item));

      final camBtn = find.byIcon(Icons.videocam_outlined);
      expect(camBtn, findsOneWidget);

      await tester.tap(camBtn);
      // Przewijamy tylko przejście trasy (~300 ms) — nie settle'ujemy, bo
      // strumień MJPEG robi request sieciowy i spinner kręci się bez końca.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(CameraView), findsOneWidget);
    });

    testWidgets('niepołączona drukarka: brak przycisku kamery',
        (tester) async {
      const item = PrinterWithStatus(printer: Printer(id: 2, name: 'A1 mini'));

      await tester.pumpWidget(_cardWithProviders(item));

      expect(find.byIcon(Icons.videocam_outlined), findsNothing);
    });
  });

  group('smart gniazdko', () {
    testWidgets('załączone gniazdko: ikona wtyczki, moc w tooltipie, bez nazwy',
        (tester) async {
      final item = PrinterWithStatus(
        printer: const Printer(id: 1, name: 'X1C'),
        status: const PrinterStatus(id: 1, connected: true, state: 'IDLE'),
      );

      await tester
          .pumpWidget(_cardWithPlugs(item, _StubSmartPlugsNotifier(_plugState())));

      // Sam symbol wtyczki; moc i nazwa nie zaśmiecają nagłówka.
      expect(find.byIcon(Icons.power), findsOneWidget);
      expect(find.byTooltip('42 W'), findsOneWidget); // moc w tooltipie
      expect(find.text('42 W'), findsNothing); // nie jako widoczny tekst
      expect(find.text('Szafa'), findsNothing);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('w trakcie druku nie można odciąć zasilania (SnackBar, brak akcji)',
        (tester) async {
      final stub = _StubSmartPlugsNotifier(_plugState());
      final item = PrinterWithStatus(
        printer: const Printer(id: 1, name: 'X1C'),
        status: const PrinterStatus(
          id: 1,
          connected: true,
          state: 'RUNNING',
          progress: 50,
          remainingTime: 60,
        ),
      );

      await tester.pumpWidget(_cardWithPlugs(item, stub));
      await tester.ensureVisible(find.byIcon(Icons.power));
      await tester.tap(find.byIcon(Icons.power));
      await tester.pump();

      expect(find.text('Nie można odciąć zasilania w trakcie druku'),
          findsOneWidget);
      expect(stub.calls, isEmpty); // zasilanie NIE odcięte
    });

    testWidgets('poza drukiem wyłączenie wymaga potwierdzenia, potem wysyła off',
        (tester) async {
      final stub = _StubSmartPlugsNotifier(_plugState());
      final item = PrinterWithStatus(
        printer: const Printer(id: 1, name: 'X1C'),
        status: const PrinterStatus(id: 1, connected: true, state: 'IDLE'),
      );

      await tester.pumpWidget(_cardWithPlugs(item, stub));
      await tester.ensureVisible(find.byIcon(Icons.power));
      await tester.tap(find.byIcon(Icons.power));
      await tester.pumpAndSettle();

      // Dialog potwierdzenia — bez niego nic nie wysyłamy.
      expect(find.text('Odciąć zasilanie?'), findsOneWidget);
      expect(stub.calls, isEmpty);

      await tester.tap(find.text('Wyłącz'));
      await tester.pump();

      expect(stub.calls, hasLength(1));
      expect(stub.calls.single.id, 10);
      expect(stub.calls.single.action, SmartPlugAction.off);
    });

    testWidgets('gniazdko offline (rozłączona drukarka) pozostaje sterowalne',
        (tester) async {
      // Karta zwija się do OFFLINE, ale chip gniazdka zostaje — to jedyny
      // sposób, by ZAŁĄCZYĆ zasilanie i obudzić maszynę.
      final stub = _StubSmartPlugsNotifier(
        SmartPlugsState(
          plugs: const [
            SmartPlug(id: 10, name: 'Szafa', printerId: 2, enabled: true),
          ],
          statuses: {10: SmartPlugStatus(state: 'OFF', reachable: true)},
        ),
      );
      final item = PrinterWithStatus(
        printer: const Printer(id: 2, name: 'A1 mini'),
        status: const PrinterStatus(id: 2, connected: false),
      );

      await tester.pumpWidget(_cardWithPlugs(item, stub));

      expect(find.text('OFFLINE'), findsOneWidget);
      // Gniazdko wyłączone → przekreślona wtyczka, przycisk aktywny (sterowalny).
      final btn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.power_off),
      );
      expect(btn.onPressed, isNotNull);

      await tester.tap(find.byIcon(Icons.power_off));
      await tester.pump();
      // Włączenie nie wymaga potwierdzenia → akcja on od razu.
      expect(stub.calls.single.action, SmartPlugAction.on);
    });
  });

  group('_CoverThumbnail', () {
    testWidgets(
        'drukarka z coverUrl: pokazuje Image gdy token dostępny',
        (tester) async {
      final item = PrinterWithStatus(
        printer: const Printer(id: 1, name: 'X1C Warsztat'),
        status: const PrinterStatus(
          id: 1,
          connected: true,
          progress: 43,
          remainingTime: 137,
          coverUrl: '/api/v1/printers/1/cover',
        ),
      );

      await tester.pumpWidget(_cardWithProviders(item));
      // Czekamy aż FutureProvider się rozwiąże.
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets(
        'drukarka z coverUrl: null — brak Image w drzewie',
        (tester) async {
      final item = PrinterWithStatus(
        printer: const Printer(id: 2, name: 'A1 mini'),
        status: const PrinterStatus(
          id: 2,
          connected: true,
          progress: 60,
          remainingTime: 90,
          // coverUrl pominięty → null
        ),
      );

      await tester.pumpWidget(_cardWithProviders(item));
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsNothing);
    });
  });
}
