import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:bambuddy_mobile/core/models/firmware.dart';
import 'package:bambuddy_mobile/core/models/heater_history.dart';
import 'package:bambuddy_mobile/data/heater_history_repository.dart';
import 'package:clock/clock.dart';
import 'package:dio/dio.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/models/scheduled_drying.dart';
import 'package:bambuddy_mobile/core/models/smart_plug.dart';
import 'package:bambuddy_mobile/core/notifications/hms_catalog.dart';
import 'package:bambuddy_mobile/features/dashboard/firmware_providers.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/smart_plugs_repository.dart';
import 'package:bambuddy_mobile/core/api/action_outcome.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/data/inventory_source.dart';
import 'package:bambuddy_mobile/data/printer_commands_repository.dart';
import 'package:bambuddy_mobile/data/scheduled_drying_repository.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/camera/camera_view.dart';
import 'package:bambuddy_mobile/features/dashboard/smart_plugs_providers.dart';
import 'package:bambuddy_mobile/core/models/inventory.dart';
import 'package:bambuddy_mobile/features/inventory/inventory_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/ams_history_sheet.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/heater_history_sheet.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/ams_slot_config_sheet.dart';
import 'package:bambuddy_mobile/features/dashboard/ws_providers.dart';
import 'package:bambuddy_mobile/features/dashboard/widgets/printer_card.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Filament runout as the server reports it on the `print_error` channel — the
/// fault the panel exists for.
const _runout = HmsError(
  code: '0x8004',
  attr: 0x03008004,
  module: 3,
  severity: 3,
  fullCode: '03008004',
);

/// The same fault with the buttons Bambu's catalog lists for it.
const _runoutWithActions = HmsError(
  code: '0x8004',
  attr: 0x03008004,
  module: 3,
  severity: 3,
  fullCode: '03008004',
  jobId: '746795586',
  actions: ['RESUME_PRINTING', 'STOP_PRINTING'],
);

/// Records HMS commands instead of sending them. Only the two routes the panel
/// can reach are implemented; anything else would be a test reaching somewhere
/// it did not mean to, and says so.
class _RecordingCommands implements PrinterCommandsRepository {
  final List<String> calls = [];

  /// Thrown by [refreshAmsSlot] instead of succeeding — the tag re-read is the
  /// one route with a permission of its own, so its refusal is worth staging.
  Object? rfidError;

  /// Thrown by [clearPlate] instead of succeeding — a pre-#2864 server that
  /// refuses to release the gate on a printer it cannot reach.
  Object? clearPlateError;

  /// Holds the answer back, so a test can land it after the card is gone.
  Completer<void>? clearPlateHeld;

  @override
  Future<void> clearHmsErrors(int printerId) async =>
      calls.add('clear:$printerId');

  @override
  Future<void> clearPlate(int printerId) async {
    calls.add('clearPlate:$printerId');
    await clearPlateHeld?.future;
    if (clearPlateError != null) throw clearPlateError!;
  }

  @override
  Future<void> amsLoad(int printerId, int trayId, {int? extruderId}) async =>
      calls.add('amsLoad:$printerId:$trayId:${extruderId ?? '-'}');

  @override
  Future<void> amsUnload(int printerId, {int? trayId}) async =>
      calls.add('amsUnload:$printerId:${trayId ?? '-'}');

  @override
  Future<void> refreshAmsSlot(
    int printerId, {
    required int amsId,
    required int slotId,
  }) async {
    calls.add('rfid:$printerId:$amsId:$slotId');
    if (rfidError != null) throw rfidError!;
  }

  @override
  Future<void> executeHmsAction(
    int printerId, {
    required String printError,
    required String action,
    String? jobId,
  }) async => calls.add('action:$printerId:$printError:$action:${jobId ?? ''}');

  @override
  Future<void> startDrying(
    int printerId, {
    required int amsId,
    required int temp,
    required int duration,
    String filament = '',
  }) async =>
      calls.add('startDrying:$printerId:$amsId:$temp:$duration:$filament');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} is not part of this test',
  );
}

/// The slot sheet reads the inventory to offer spools; these tests care about
/// the printer-side actions above that list, so it stays empty and offline.
class _EmptyInventory extends InventoryNotifier {
  @override
  Future<InventoryState> build() async => const InventoryState();
}

/// A stocked shelf, for the half of the sheet that offers spools.
class _StockedInventory extends InventoryNotifier {
  @override
  Future<InventoryState> build() async => const InventoryState(
    spools: [
      Spool(id: 14, material: 'PLA', subtype: 'Basic', brand: 'Anycubic'),
      Spool(id: 13, material: 'PLA', subtype: 'Matte', brand: 'Bambu'),
      Spool(
        id: 31,
        material: 'PETG',
        subtype: 'Translucent',
        brand: 'Smart Print',
      ),
    ],
  );
}

/// A shelf with a spool pinned to the slot the sheet opens on (X1C, AMS 1,
/// first slot), so the "currently in this slot" row has something to show.
class _AssignedInventory extends InventoryNotifier {
  static const spool = Spool(
    id: 42,
    material: 'PLA',
    subtype: 'Basic',
    brand: 'Bambu Lab',
    labelWeight: 1000,
  );

  @override
  Future<InventoryState> build() async => const InventoryState(
    spools: [spool],
    assignmentBySpool: {
      42: SpoolAssignment(
        spoolId: 42,
        printerId: 1,
        amsId: 0,
        trayId: 0,
        printerName: 'X2D-3DP',
      ),
    },
  );
}

/// A shelf that already holds the spool whose tag sits in the slot, so the
/// sheet must offer to pick it rather than to create a second row for it.
class _TaggedInventory extends InventoryNotifier {
  @override
  Future<InventoryState> build() async => const InventoryState(
    spools: [
      Spool(
        id: 21,
        material: 'PLA',
        subtype: 'Basic',
        brand: 'Bambu',
        tagUid: 'a1b2c3d4e5f60708',
      ),
    ],
  );
}

/// Records the registration the sheet asks for, so a test can tell the button
/// fired the right slot triple rather than merely being tappable.
class _RecordingInventory extends InventoryNotifier {
  static final calls = <String>[];

  @override
  Future<InventoryState> build() async => const InventoryState();

  @override
  Future<int?> createSpoolFromSlot(int printerId, int amsId, int trayId) async {
    calls.add('$printerId:$amsId:$trayId');
    return 99;
  }
}

/// Refuses the registration with a staged failure, so each refusal can be
/// checked by the words it leaves in front of the user. The exception is a
/// static because the override takes a constructor, not an instance.
class _RefusingInventory extends InventoryNotifier {
  static AppApiException failure = const ApiException(
    AppErrorCode.badResponse,
    statusCode: 500,
  );

  @override
  Future<InventoryState> build() async => const InventoryState();

  @override
  Future<int?> createSpoolFromSlot(int printerId, int amsId, int trayId) async {
    throw failure;
  }
}

/// Scheduled drying without a server: the listing a card reads, the schedules
/// it writes, and the cancels it sends.
///
/// [supported] is what an older server answers by 404 and a current one by
/// listing at all — the sheet's "later" modes hang off it, so both sides are
/// staged rather than derived from a version.
class _StubScheduledDrying extends ScheduledDryingRepository {
  _StubScheduledDrying({
    List<ScheduledDrying> rows = const [],
    this.supported = true,
  }) : rows = [...rows],
       super(Dio());

  final List<ScheduledDrying> rows;
  final bool supported;

  final List<ScheduledDrying> created = [];
  final List<int> cancelled = [];
  int listCalls = 0;

  @override
  Future<bool> supportsScheduling() async => supported;

  @override
  Future<List<ScheduledDrying>> list({int? printerId}) async {
    listCalls++;
    return [...rows];
  }

  @override
  Future<ScheduledDrying> create({
    required int printerId,
    required int amsId,
    required int temp,
    required int durationHours,
    String filament = '',
    bool rotateTray = false,
    DateTime? startAfter,
  }) async {
    final row = ScheduledDrying(
      id: 100 + created.length,
      printerId: printerId,
      amsId: amsId,
      temp: temp,
      durationHours: durationHours,
      filament: filament,
      rotateTray: rotateTray,
      status: 'pending',
      startAfter: startAfter,
    );
    created.add(row);
    rows.add(row);
    return row;
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    rows.removeWhere((row) => row.id == id);
  }
}

/// The card tests run without a settings repository, and the real backend
/// notifier reads one — so the choice is staged here instead.
class _FixedBackendNotifier extends InventoryBackendNotifier {
  _FixedBackendNotifier(this._backend);

  final InventoryBackend _backend;

  @override
  InventoryBackend build() => _backend;
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
  Future<ActionOutcome> control(int plugId, SmartPlugAction action) async {
    calls.add((id: plugId, action: action));
    return ActionOutcome.ok;
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
        fakeServerProfileOverride(),
        cameraTokenProvider.overrideWith((ref) async => 'tok'),
        inertFirmwareOverride,
        inertTotalPrintHoursOverride,
        inertChamberMaxOverride,
        ...inertHistorySupportOverrides,
        smartPlugsProvider.overrideWith(() => stub),
      ],
      child: plApp(
        Scaffold(
          body: SingleChildScrollView(child: PrinterCard(item: item)),
        ),
      ),
    );

/// Historia grzałek bez sieci: karta odpowiada tylko za otwarcie arkusza, co
/// arkusz rysuje z danych sprawdza `heater_history_sheet_test.dart`.
class _EmptyHeaterHistory extends HeaterHistoryRepository {
  _EmptyHeaterHistory() : super(Dio());

  @override
  Future<HeaterHistory> fetch(
    int printerId, {
    int hours = 24,
    List<String> kinds = const [],
  }) async => const HeaterHistory(printerId: 3, series: []);
}

/// Owija drzewo w ProviderScope — karta zawiera teraz interaktywny pasek
/// sterowania (`_ControlsActions`, ConsumerWidget), więc każdy render karty
/// ze statusem potrzebuje scope'a. Profil = bez auth, token kamery zaślepiony.
Widget _scope(
  Widget child, {
  List<Override> extra = const [],
  InventoryBackend backend = InventoryBackend.native,
  bool apiKeySession = false,
}) => ProviderScope(
  overrides: [
    fakeServerProfileOverride(
      authMode: apiKeySession ? AuthMode.apiKey : AuthMode.none,
    ),
    inventoryBackendProvider.overrideWith(() => _FixedBackendNotifier(backend)),
    cameraTokenProvider.overrideWith((ref) async => 'tok'),
    inertFirmwareOverride,
    inertTotalPrintHoursOverride,
    inertChamberMaxOverride,
    ...inertHistorySupportOverrides,
    inertSmartPlugsOverride,
    ...extra,
  ],
  child: plApp(child),
);

Widget _cardWithProviders(
  PrinterWithStatus item, {
  List<Override> extra = const [],
}) => _scope(
  Scaffold(
    body: SingleChildScrollView(child: PrinterCard(item: item)),
  ),
  extra: extra,
);

/// Stabilny scope z podmienialnym itemem (ten sam klucz karty → reuse State,
/// czyli didUpdateWidget) — do testów debounce'u OFFLINE.
///
/// [inTouchSince] is what the dashboard passes from the statuses store: when
/// the line to the server last came up. `null` means the caller tracks no
/// contact at all.
Widget _cardSwap(
  ValueNotifier<PrinterWithStatus> item, {
  DateTime? inTouchSince,
}) => ProviderScope(
  overrides: [
    fakeServerProfileOverride(),
    cameraTokenProvider.overrideWith((ref) async => 'tok'),
    inertFirmwareOverride,
    inertTotalPrintHoursOverride,
    inertChamberMaxOverride,
    ...inertHistorySupportOverrides,
    inertSmartPlugsOverride,
  ],
  child: plApp(
    Scaffold(
      body: ValueListenableBuilder<PrinterWithStatus>(
        valueListenable: item,
        builder: (_, it, _) => PrinterCard(
          key: const ValueKey('card'),
          item: it,
          inTouchSince: inTouchSince,
        ),
      ),
    ),
  ),
);

/// The shared status map without the WebSocket client behind it — the banner
/// only reaches for it to lower the plate-clear gate after an acknowledgement,
/// and building the real notifier would have this test dial a server.
class _InertStatuses extends PrinterStatusesNotifier {
  @override
  Map<int, PrinterStatus> build() => const {};
}

void main() {
  testWidgets('karta renderuje nazwę, postęp i temperatury z fixture\'a', (
    tester,
  ) async {
    final item = PrinterWithStatus(
      printer: const Printer(id: 1, name: 'X1C Warsztat'),
      status: PrinterStatus.fromJson(
        readFixture('printer_status_printing.json') as Map<String, dynamic>,
      ),
    );

    await tester.pumpWidget(_cardWithProviders(item));

    expect(find.text('X1C Warsztat'), findsOneWidget);
    expect(find.text('RUNNING'), findsOneWidget);
    expect(find.text('benchy.3mf'), findsOneWidget);
    expect(find.textContaining('43%'), findsOneWidget);
    expect(find.textContaining('87/203'), findsOneWidget);
    expect(find.textContaining('pozostało 2h 17min'), findsOneWidget);
    // Gauge tile: label (uppercase) and value are separate texts.
    expect(find.text('DYSZA'), findsOneWidget);
    expect(find.text('220°'), findsOneWidget);
    expect(find.text('STÓŁ'), findsOneWidget);
    expect(find.text('60°'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('pasek kontrolek: wentylatory, prędkość i światło z fixture\'a', (
    tester,
  ) async {
    final item = PrinterWithStatus(
      printer: const Printer(id: 1, name: 'X1C Warsztat'),
      status: PrinterStatus.fromJson(
        readFixture('printer_status_printing.json') as Map<String, dynamic>,
      ),
    );

    await tester.pumpWidget(_cardWithProviders(item));

    // Zawsze widoczne: światło (wiersz-przełącznik), pauza/stop.
    expect(find.text('Światło komory'), findsOneWidget);
    // Nawiew komory (tryb 0 = chłodzenie) → ikona płatka śniegu przed wartością.
    expect(find.byIcon(Icons.ac_unit), findsOneWidget);
    expect(find.text('Pauza'), findsOneWidget);
    expect(find.text('Zatrzymaj'), findsOneWidget);

    // Wentylatory i prędkość są teraz pod „Szczegóły" — rozwiń, żeby je zobaczyć.
    await tester.ensureVisible(find.text('Szczegóły'));
    await tester.tap(find.text('Szczegóły'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('53%'), findsOneWidget); // wentylator części
    expect(find.text('73%'), findsOneWidget); // pomocniczy
    expect(find.text('60%'), findsOneWidget); // komory
    expect(find.text('Standard'), findsOneWidget); // prędkość (poziom 2)
  });

  testWidgets('pasek kontrolek nie renderuje się bez danych sterowania', (
    tester,
  ) async {
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

    // Wartość aktualna duża; cel wewnątrz pierścienia (myślnik gdy brak celu).
    expect(find.text('STÓŁ'), findsOneWidget);
    // Stół: aktualna 70 i cel 70 → dwa teksty „70°" (wartość + środek gauge).
    expect(find.text('70°'), findsNWidgets(2));
    expect(find.text('DYSZA'), findsOneWidget);
    expect(find.text('244°'), findsOneWidget); // aktualna dyszy
    expect(find.text('245°'), findsOneWidget); // cel dyszy w pierścieniu
    // Cel = 0 → w pierścieniu myślnik, wartość aktualna widoczna.
    expect(find.text('DYSZA 2'), findsOneWidget);
    expect(find.text('47°'), findsOneWidget);
    // Bez celu.
    expect(find.text('KOMORA'), findsOneWidget);
    expect(find.text('30°'), findsOneWidget);
    // Nieznany klucz zostaje surowy (wielkimi literami jako etykieta).
    expect(find.text('COŚDZIWNEGO'), findsOneWidget);
    expect(find.text('12°'), findsOneWidget);
  });

  testWidgets('ikona wykresu na kafelku otwiera historię temperatur', (
    tester,
  ) async {
    await tester.pumpWidget(
      _cardWithProviders(
        const PrinterWithStatus(
          printer: Printer(id: 3, name: 'X2D'),
          status: PrinterStatus(
            id: 3,
            connected: true,
            state: 'IDLE',
            temperatures: {'nozzle': 244, 'bed': 70},
          ),
        ),
        extra: [
          heaterHistoryRepositoryProvider.overrideWithValue(
            _EmptyHeaterHistory(),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.identifier == 'printer.temperature_history_nozzle',
      ),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.text('Historia temperatur'), findsOneWidget);
    // Arkusz przełącza się między czujnikami tej drukarki (etykiety kafelków).
    expect(find.text('Dysza'), findsOneWidget);
    expect(find.text('Stół'), findsOneWidget);
  });

  /// Sama ikonka to celownik 22 px wewnątrz InkWella kafelka: chybienie
  /// otwierało arkusz nastawy temperatury. Klikalny jest cały pasek etykiety.
  testWidgets('etykieta czujnika otwiera historię, nie arkusz nastawy', (
    tester,
  ) async {
    await tester.pumpWidget(
      _cardWithProviders(
        const PrinterWithStatus(
          printer: Printer(id: 3, name: 'X2D'),
          status: PrinterStatus(
            id: 3,
            connected: true,
            state: 'IDLE',
            temperatures: {'nozzle': 244, 'bed': 70},
          ),
        ),
        extra: [
          heaterHistoryRepositoryProvider.overrideWithValue(
            _EmptyHeaterHistory(),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('DYSZA'));
    await tester.pumpAndSettle();

    expect(find.text('Historia temperatur'), findsOneWidget);
    expect(find.text('Ustaw'), findsNothing); // arkusz nastawy się nie otwarł
  });

  testWidgets('serwer bez historii grzałek: kafelki bez ikony wykresu', (
    tester,
  ) async {
    await tester.pumpWidget(
      _cardWithProviders(
        const PrinterWithStatus(
          printer: Printer(id: 3, name: 'X2D'),
          status: PrinterStatus(
            id: 3,
            connected: true,
            state: 'IDLE',
            temperatures: {'nozzle': 244, 'bed': 70},
          ),
        ),
        extra: [
          heaterHistorySupportedProvider.overrideWith((ref) async => false),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.show_chart), findsNothing);
    expect(find.text('DYSZA'), findsOneWidget); // sam kafelek zostaje
  });

  testWidgets('karta bez statusu zwija się do nagłówka z etykietą OFFLINE', (
    tester,
  ) async {
    const item = PrinterWithStatus(printer: Printer(id: 2, name: 'A1 mini'));

    await tester.pumpWidget(_cardWithProviders(item));

    expect(find.text('A1 mini'), findsOneWidget);
    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.text('status niedostępny'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets(
    'drukarka rozłączona (connected:false) zwija sekcję i pokazuje OFFLINE',
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
    },
  );

  group('rozwijane szczegóły (AMS)', () {
    /// [tagged] writes an RFID tag onto the first slot of AMS 1. The capture
    /// this fixture comes from has none — the printer runs third-party spools
    /// — and a tag is what the "add to inventory" affordance hangs off.
    PrinterWithStatus realItem({bool tagged = false}) {
      final frame =
          readFixture('ws_printer_status.json') as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(frame['data'] as Map);
      data['id'] = frame['printer_id'];
      // Miniatura okładki (sieciowa) jest testowana osobno — usuwamy ją tu,
      // by izolować sekcję AMS i nie czekać na request HTTP w teście.
      data.remove('cover_url');
      if (tagged) {
        final units = List<dynamic>.from(data['ams'] as List);
        final unit = Map<String, dynamic>.from(units.first as Map);
        final trays = List<dynamic>.from(unit['tray'] as List);
        trays[0] = {
          ...Map<String, dynamic>.from(trays.first as Map),
          'tag_uid': 'A1B2C3D4E5F60708',
        };
        unit['tray'] = trays;
        units[0] = unit;
        data['ams'] = units;
      }
      return PrinterWithStatus(
        printer: const Printer(id: 1, name: 'X2D-3DP'),
        status: PrinterStatus.fromJson(data),
      );
    }

    testWidgets('szczegóły domyślnie zwinięte, rozwijają się po tapnięciu', (
      tester,
    ) async {
      await tester.pumpWidget(
        _scope(
          Scaffold(
            body: SingleChildScrollView(child: PrinterCard(item: realItem())),
          ),
        ),
      );

      // Zwinięte: jest przełącznik „Szczegóły", brak treści AMS.
      expect(find.text('Szczegóły'), findsOneWidget);
      expect(find.text('AMS 1'), findsNothing);

      // Karta jest wysoka — upewnij się, że przełącznik jest widoczny przed tapem.
      await tester.ensureVisible(find.text('Szczegóły'));
      await tester.tap(find.text('Szczegóły'));
      // Nie pumpAndSettle — faza przygotowania ma nieoznaczony pasek postępu,
      // który animuje się bez końca. Przewijamy tylko czas rozwinięcia (200 ms).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // Rozwinięte: AMS, szpula zewnętrzna i metadane widoczne.
      expect(find.text('Ukryj szczegóły'), findsOneWidget);
      expect(find.text('AMS 1'), findsOneWidget);
      expect(find.text('SZPULA ZEWNĘTRZNA'), findsOneWidget);
      // Wiersz filamentu: materiał i pozostała ilość jako osobne teksty.
      expect(find.text('PLA Basic'), findsWidgets);
      expect(find.text('66%'), findsOneWidget);
      // Metadane łączności.
      expect(find.textContaining('-59 dBm'), findsOneWidget);
      expect(find.text('DRZWICZKI ZAMKNIĘTE'), findsOneWidget);
    });

    testWidgets(
      'brak danych AMS, ale bezczynna drukarka → przełącznik szczegółów z ruchem',
      (tester) async {
        final item = PrinterWithStatus(
          printer: const Printer(id: 9, name: 'A1'),
          status: const PrinterStatus(id: 9, connected: true, state: 'IDLE'),
        );

        await tester.pumpWidget(_cardWithProviders(item));

        // Bezczynna drukarka udostępnia ruch osi, więc przełącznik „Szczegóły"
        // pojawia się nawet bez danych AMS/wentylatorów.
        expect(find.text('Szczegóły'), findsOneWidget);

        await tester.ensureVisible(find.text('Szczegóły'));
        await tester.tap(find.text('Szczegóły'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        // Rozwinięte: kafelek ruchu osi.
        expect(find.text('Ruch'), findsOneWidget);
      },
    );

    testWidgets('bez dostępu do historii AMS odczyty przestają być klikalne', (
      tester,
    ) async {
      /// Wilgotność i temperatura AMS to normalne odczyty — gdy serwer nie da
      /// historii (403 dla okrojonego klucza), zostają na ekranie, tracą tylko
      /// tapnięcie, które mogłoby skończyć się wyłącznie błędem.
      Future<Iterable<InkWell>> metaTaps(WidgetTester tester) async {
        await tester.ensureVisible(find.text('Szczegóły'));
        await tester.tap(find.text('Szczegóły'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        return tester.widgetList<InkWell>(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) =>
                  w is Semantics &&
                  w.properties.identifier == 'printer.ams_meta',
            ),
            matching: find.byType(InkWell),
          ),
        );
      }

      await tester.pumpWidget(
        _scope(
          Scaffold(
            body: SingleChildScrollView(child: PrinterCard(item: realItem())),
          ),
          extra: [
            amsHistorySupportedProvider.overrideWith((ref) async => false),
          ],
        ),
      );

      final taps = await metaTaps(tester);
      expect(taps, isNotEmpty);
      expect(taps.every((w) => w.onTap == null), isTrue);
      expect(find.textContaining('%'), findsWidgets); // odczyty zostają
    });

    /// Taps the first filament row of AMS 1 and waits out the sheet's own
    /// transition. Separate from [openSlotSheet] so a test can reopen the sheet
    /// on the same tree, which is the only way to see state a first tap left
    /// behind.
    Future<void> tapSlotRow(WidgetTester tester) async {
      // The row's identifier carries the material it shows (`…@PETG`), so match
      // on the control's own name and take the first slot of AMS 1.
      final slotRow = find
          .byWidgetPredicate(
            (w) =>
                w is Semantics &&
                (w.properties.identifier ?? '').startsWith('printer.ams_slot'),
          )
          .first;
      await tester.ensureVisible(slotRow);
      await tester.tap(slotRow);
      // Not pumpAndSettle: a printing card animates an indeterminate progress
      // bar forever, so only the sheet's own transition is waited out.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// Opens the sheet behind the second slot of AMS 1 and hands back the
    /// commands it sent. [state] decides whether the printer is mid-job.
    Future<_RecordingCommands> openSlotSheet(
      WidgetTester tester, {
      required String state,
      _RecordingCommands? withCommands,
      bool stocked = false,
      bool tagged = false,
      InventoryNotifier Function()? inventory,
      InventoryBackend backend = InventoryBackend.native,
      bool apiKeySession = false,
      FilaSwitch? filaSwitch,
      Map<int, ExtruderSlot>? extruderSlots,
    }) async {
      final item = realItem(tagged: tagged);
      final status = PrinterStatus(
        id: item.printer.id,
        connected: true,
        state: state,
        filaSwitch: filaSwitch,
        extruderSlots: extruderSlots,
      ).mergedWith(item.status!);
      final commands = withCommands ?? _RecordingCommands();

      await tester.pumpWidget(
        _scope(
          Scaffold(
            body: SingleChildScrollView(
              child: PrinterCard(
                item: PrinterWithStatus(printer: item.printer, status: status),
              ),
            ),
          ),
          extra: [
            printerCommandsRepositoryProvider.overrideWithValue(commands),
            inventoryProvider.overrideWith(
              inventory ??
                  (stocked ? _StockedInventory.new : _EmptyInventory.new),
            ),
          ],
          backend: backend,
          apiKeySession: apiKeySession,
        ),
      );

      await tester.ensureVisible(find.text('Szczegóły'));
      await tester.tap(find.text('Szczegóły'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      await tapSlotRow(tester);
      return commands;
    }

    testWidgets('a refused tag re-read takes only its own button away', (
      tester,
    ) async {
      // `printers:ams_rfid` is a permission of its own: being refused it says
      // nothing about whether this key may load filament, so load and unload
      // have to survive.
      final commands = _RecordingCommands()
        ..rfidError = const AuthException(AppErrorCode.forbidden);
      await openSlotSheet(tester, state: 'IDLE', withCommands: commands);

      await tester.tap(find.text('Odczytaj tag'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(commands.calls, ['rfid:1:0:0']);

      await tapSlotRow(tester);
      expect(find.text('Odczytaj tag'), findsNothing);
      expect(find.text('Załaduj'), findsOneWidget);
      expect(find.text('Wyładuj'), findsOneWidget);
    });

    testWidgets('slot sheet loads the slot by its global tray number', (
      tester,
    ) async {
      final commands = await openSlotSheet(tester, state: 'IDLE');

      expect(find.text('Załaduj'), findsOneWidget);
      expect(find.text('Odczytaj tag'), findsOneWidget);

      await tester.tap(find.text('Załaduj'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // AMS unit 0, first slot → global tray 0, not the local slot id.
      expect(commands.calls, ['amsLoad:1:0:-']);
    });

    testWidgets('slot sheet unloads the slot it names, not the printer', (
      tester,
    ) async {
      // `tray_now` is one value for a printer with two hotends, so an
      // unaddressed unload empties whichever of them that field happens to name.
      final commands = await openSlotSheet(tester, state: 'IDLE');

      await tester.tap(find.text('Wyładuj'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(commands.calls, ['amsUnload:1:0']);
    });

    testWidgets('a Filament Track Switch asks which nozzle to feed', (
      tester,
    ) async {
      // With one fitted the AMS is bound to a switch inlet rather than to a
      // hotend, so the firmware cannot derive the target and drops a load that
      // does not name one.
      final commands = await openSlotSheet(
        tester,
        state: 'IDLE',
        filaSwitch: const FilaSwitch(installed: true, ready: true),
      );

      await tester.tap(find.text('Załaduj'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(commands.calls, isEmpty, reason: 'nothing goes out unanswered');
      expect(find.text('Lewy ekstruder'), findsOneWidget);

      await tester.tap(find.text('Lewy ekstruder'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(commands.calls, ['amsLoad:1:0:1']);
    });

    testWidgets('the right nozzle is sent as 0, not dropped as falsy', (
      tester,
    ) async {
      final commands = await openSlotSheet(
        tester,
        state: 'IDLE',
        filaSwitch: const FilaSwitch(installed: true, ready: true),
      );

      await tester.tap(find.text('Załaduj'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Prawy ekstruder'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(commands.calls, ['amsLoad:1:0:0']);
    });

    testWidgets('a nozzle already fed from this slot cannot be picked again', (
      tester,
    ) async {
      final commands = await openSlotSheet(
        tester,
        state: 'IDLE',
        filaSwitch: const FilaSwitch(installed: true, ready: true),
        // Ids here are local: AMS 0, first slot — the row the sheet opened on.
        extruderSlots: const {
          0: ExtruderSlot(amsId: 0, slotId: 0, hasFilament: true),
        },
      );

      await tester.tap(find.text('Załaduj'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('Prawy ekstruder — już załadowany'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(commands.calls, isEmpty);
      expect(
        find.text('Lewy ekstruder'),
        findsOneWidget,
        reason: 'the other hotend is still a valid answer',
      );
    });

    testWidgets('a switch nobody has set up refuses the load with a reason', (
      tester,
    ) async {
      // Until every AMS is bound to an inlet the switch routes nothing, and the
      // firmware drops the command whatever hotend it names — which is silence,
      // not an error the user could act on.
      final commands = await openSlotSheet(
        tester,
        state: 'IDLE',
        filaSwitch: const FilaSwitch(installed: true),
      );

      await tester.tap(find.text('Załaduj'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(commands.calls, isEmpty);
      expect(find.textContaining('Filament Track Switch'), findsOneWidget);
      expect(find.text('Lewy ekstruder'), findsNothing);
    });

    testWidgets('each external spool is offered its own nozzle size', (
      tester,
    ) async {
      // The external holder is keyed under unit 255, which no
      // `ams_extruder_map` mentions — reading it as extruder 0 handed Ext-L
      // the right-hand nozzle's size, and that size is what the slot
      // configuration writes and queries the calibration table by.
      final frame =
          readFixture('ws_printer_status.json') as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(frame['data'] as Map);
      data['id'] = frame['printer_id'];
      data.remove('cover_url');
      data['nozzles'] = const [
        {'nozzle_diameter': '0.4'},
        {'nozzle_diameter': '0.8'},
      ];

      await tester.pumpWidget(
        _scope(
          Scaffold(
            body: SingleChildScrollView(
              child: PrinterCard(
                item: PrinterWithStatus(
                  printer: const Printer(id: 1, name: 'X2D-3DP'),
                  status: PrinterStatus.fromJson(data),
                ),
              ),
            ),
          ),
          extra: [inventoryProvider.overrideWith(_EmptyInventory.new)],
        ),
      );

      await tester.ensureVisible(find.text('Szczegóły'));
      await tester.tap(find.text('Szczegóły'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // The TPU spool is `vt_tray` 254 — Ext-L, extruder 1.
      final row = find
          .byWidgetPredicate(
            (w) =>
                w is Semantics &&
                (w.properties.identifier ?? '') == 'printer.ams_slot@TPU',
          )
          .first;
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('Skonfiguruj slot'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final sheet = tester.widget<AmsSlotConfigSheet>(
        find.byType(AmsSlotConfigSheet),
      );
      expect(sheet.target.amsId, 255);
      expect(sheet.target.trayId, 0, reason: 'Ext-L is tray 0');
      expect(sheet.target.extruderId, 1);
      expect(sheet.target.nozzleDiameter, '0.8');
    });

    testWidgets('a switch-bound AMS is configured on the nozzle it rests on', (
      tester,
    ) async {
      // With a Filament Track Switch fitted every AMS reports 0xE, so
      // `ams_extruder_map` is empty and the unit gets no left/right badge — but
      // its inlet still says which calibration table the slot belongs to.
      final frame =
          readFixture('ws_printer_status.json') as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(frame['data'] as Map);
      data['id'] = frame['printer_id'];
      data.remove('cover_url');
      data['ams_extruder_map'] = const <String, int>{};
      data['ams_switch_inlet'] = const {'0': 'A'};
      data['nozzles'] = const [
        {'nozzle_diameter': '0.4'},
        {'nozzle_diameter': '0.8'},
      ];

      await tester.pumpWidget(
        _scope(
          Scaffold(
            body: SingleChildScrollView(
              child: PrinterCard(
                item: PrinterWithStatus(
                  printer: const Printer(id: 1, name: 'H2C'),
                  status: PrinterStatus.fromJson(data),
                ),
              ),
            ),
          ),
          extra: [inventoryProvider.overrideWith(_EmptyInventory.new)],
        ),
      );

      await tester.ensureVisible(find.text('Szczegóły'));
      await tester.tap(find.text('Szczegóły'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // The AMS header names no side: the switch moves the unit between both.
      expect(find.widgetWithText(Tooltip, 'L'), findsNothing);
      expect(find.widgetWithText(Tooltip, 'P'), findsNothing);

      final row = find
          .byWidgetPredicate(
            (w) =>
                w is Semantics &&
                (w.properties.identifier ?? '') == 'printer.ams_slot@PETG',
          )
          .first;
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('Skonfiguruj slot'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final sheet = tester.widget<AmsSlotConfigSheet>(
        find.byType(AmsSlotConfigSheet),
      );
      expect(sheet.target.extruderId, 1, reason: 'inlet A rests on the left');
      expect(sheet.target.nozzleDiameter, '0.8');
    });

    testWidgets('a printing printer keeps the filament actions unreachable', (
      tester,
    ) async {
      final commands = await openSlotSheet(tester, state: 'RUNNING');

      expect(find.text('Niedostępne, gdy drukarka drukuje'), findsOneWidget);
      await tester.tap(find.text('Załaduj'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(commands.calls, isEmpty);
    });

    testWidgets('a paused job still lets the filament be changed', (
      tester,
    ) async {
      // Swapping a spool that ran out is what a pause is for.
      final commands = await openSlotSheet(tester, state: 'PAUSE');

      expect(find.text('Niedostępne, gdy drukarka drukuje'), findsNothing);
      await tester.tap(find.text('Załaduj'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(commands.calls, ['amsLoad:1:0:-']);
    });

    /// Brings a widget into view inside the assign sheet's own scroll view.
    /// The sheet builds its rows lazily, so anything past the first screenful
    /// is not in the tree at all until it is scrolled to.
    Future<void> reveal(WidgetTester tester, Finder finder) async {
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          finder,
          120,
          scrollable: find
              .descendant(
                of: find.byType(DraggableScrollableSheet),
                matching: find.byType(Scrollable),
              )
              .first,
        );
      }
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
    }

    testWidgets('the spool list can be searched', (tester) async {
      // A shelf of a hundred spools is not something to scroll through while
      // standing at the printer.
      await openSlotSheet(tester, state: 'IDLE', stocked: true);
      await reveal(tester, find.byType(TextField));

      await tester.enterText(find.byType(TextField), 'petg');
      await tester.pumpAndSettle();

      // The count is the assertion the other two are gone: a list that builds
      // its rows lazily has no element for an off-screen one either, so
      // `findsNothing` alone would pass whether they were filtered or scrolled
      // past.
      expect(find.byType(ListTile), findsOneWidget);
      expect(find.text('Smart Print PETG Translucent'), findsOneWidget);
    });

    testWidgets('a search matching nothing does not read as an empty shelf', (
      tester,
    ) async {
      // Both states show no rows, and only one of them is fixed by clearing
      // the field.
      await openSlotSheet(tester, state: 'IDLE', stocked: true);
      await reveal(tester, find.byType(TextField));

      await tester.enterText(find.byType(TextField), 'nylon');
      await tester.pumpAndSettle();

      expect(find.textContaining('Brak wyników'), findsOneWidget);
      expect(find.text('Brak szpul w magazynie'), findsNothing);
    });

    testWidgets('an empty shelf still says so', (tester) async {
      await openSlotSheet(tester, state: 'IDLE');
      await reveal(tester, find.text('Brak szpul w magazynie'));

      expect(find.text('Brak szpul w magazynie'), findsOneWidget);
      expect(find.textContaining('Brak wyników'), findsNothing);
    });

    /// The card behind a router, for the one action that leaves the dashboard.
    /// The real [rootNavigatorKey] is handed to it, because that is the key
    /// `openSpoolInInventory` reaches the root navigator through.
    Widget routedCard() {
      final item = realItem();
      // Idle, like [openSlotSheet]: a printing card animates its progress bar
      // forever and nothing in this test would ever settle.
      final idle = PrinterWithStatus(
        printer: item.printer,
        status: const PrinterStatus(
          id: 1,
          connected: true,
          state: 'IDLE',
        ).mergedWith(item.status!),
      );
      final router = GoRouter(
        navigatorKey: rootNavigatorKey,
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: SingleChildScrollView(child: PrinterCard(item: idle)),
            ),
          ),
          GoRoute(
            path: '/inventory',
            builder: (_, _) => const Scaffold(body: Text('FILAMENTY')),
          ),
        ],
      );
      return ProviderScope(
        overrides: [
          fakeServerProfileOverride(),
          cameraTokenProvider.overrideWith((ref) async => 'tok'),
          inertFirmwareOverride,
          inertTotalPrintHoursOverride,
          inertChamberMaxOverride,
          ...inertHistorySupportOverrides,
          inertSmartPlugsOverride,
          inventoryBackendProvider.overrideWith(
            () => _FixedBackendNotifier(InventoryBackend.native),
          ),
          inventoryProvider.overrideWith(_AssignedInventory.new),
          // The spool card fetches its usage on open; the repository behind it
          // has no server here and this test is about arriving, not about what
          // the card then loads.
          spoolUsageProvider(
            _AssignedInventory.spool.id,
          ).overrideWith((ref) async => const <SpoolUsageEntry>[]),
        ],
        child: MaterialApp.router(
          locale: const Locale('pl'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      );
    }

    testWidgets('the pinned spool leads to its card on Filaments', (
      tester,
    ) async {
      // The row names a spool and sits next to one that assigns; pressing it
      // has to go somewhere, and everything else about that spool is in the
      // Filaments tab.
      await tester.pumpWidget(routedCard());
      await tester.pump();

      await tester.ensureVisible(find.text('Szczegóły'));
      await tester.tap(find.text('Szczegóły'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tapSlotRow(tester);

      final row = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            (w.properties.identifier ?? '').startsWith('assign_spool.current'),
      );
      await reveal(tester, row);
      await tester.tap(row);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Landed on the tab, with the spool's own card over it.
      expect(find.text('FILAMENTY'), findsOneWidget);
      expect(find.text('#42'), findsOneWidget);
      expect(find.text('Przypisz szpulę'), findsNothing);
    });

    /// The registration button, by the name it carries in the diagnostic log.
    Finder registerButton() => find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          w.properties.identifier == 'assign_spool.add_to_inventory',
    );

    testWidgets('a tagged slot the shelf does not know offers to register it', (
      tester,
    ) async {
      await openSlotSheet(tester, state: 'IDLE', tagged: true);
      await reveal(tester, registerButton());

      expect(registerButton(), findsOneWidget);
      expect(find.text('Dodaj do magazynu'), findsOneWidget);
    });

    testWidgets('an untagged slot never offers it', (tester) async {
      // Without a tag the server refuses: the slot has no identity to re-link
      // to, so every confirm would mint another row.
      await openSlotSheet(tester, state: 'IDLE');

      expect(registerButton(), findsNothing);
    });

    testWidgets('a tag already on a spool is picked, not registered again', (
      tester,
    ) async {
      // The route creates unconditionally. The spool is in the list below —
      // that is where this tag gets back onto the slot.
      await openSlotSheet(
        tester,
        state: 'IDLE',
        tagged: true,
        inventory: _TaggedInventory.new,
      );

      expect(registerButton(), findsNothing);
    });

    testWidgets(
      'an API key against Spoolman is not offered what it cannot do',
      (tester) async {
        // Spoolman's from-slot route is gated on `filaments:update`, which sits
        // outside the API-key scope allowlist — a keyed session gets 403 there
        // whatever its scopes.
        await openSlotSheet(
          tester,
          state: 'IDLE',
          tagged: true,
          apiKeySession: true,
          backend: InventoryBackend.spoolman,
        );

        expect(registerButton(), findsNothing);
      },
    );

    testWidgets('the same key on the native inventory keeps the button', (
      tester,
    ) async {
      // Only the pair is refused: `inventory:update` maps to the
      // `can_manage_inventory` scope, so a key can register a slot natively.
      await openSlotSheet(
        tester,
        state: 'IDLE',
        tagged: true,
        apiKeySession: true,
      );
      await reveal(tester, registerButton());

      expect(registerButton(), findsOneWidget);
    });

    testWidgets('registering sends the slot the sheet was opened on', (
      tester,
    ) async {
      _RecordingInventory.calls.clear();
      await openSlotSheet(
        tester,
        state: 'IDLE',
        tagged: true,
        inventory: _RecordingInventory.new,
      );
      await reveal(tester, registerButton());

      await tester.tap(registerButton());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(_RecordingInventory.calls, ['1:0:0']);
      expect(find.text('Szpula dodana i przypisana do slotu'), findsOneWidget);
    });

    /// Registers with [failure] staged, and comes back once the sheet has
    /// closed and the snack it left behind has been drawn.
    Future<void> registerRefused(
      WidgetTester tester,
      AppApiException failure,
    ) async {
      _RefusingInventory.failure = failure;
      await openSlotSheet(
        tester,
        state: 'IDLE',
        tagged: true,
        inventory: _RefusingInventory.new,
      );
      await reveal(tester, registerButton());

      await tester.tap(registerButton());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('a bare 404 is read as a server too old for the route', (
      tester,
    ) async {
      // FastAPI's own "Not Found" for a route that is not there at all.
      await registerRefused(
        tester,
        const ApiException(
          AppErrorCode.badResponse,
          statusCode: 404,
          detail: 'Not Found',
        ),
      );

      expect(
        find.text('Ta wersja serwera nie potrafi dodać szpuli prosto ze slotu'),
        findsOneWidget,
      );
    });

    testWidgets("the route's own 404 is read as the printer being away", (
      tester,
    ) async {
      await registerRefused(
        tester,
        const ApiException(
          AppErrorCode.badResponse,
          statusCode: 404,
          detail: 'Printer not connected or no state available',
        ),
      );

      expect(
        find.text(
          'Drukarka nie jest połączona, więc nie powie, co jest w slocie',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a 400 says the slot stopped reporting a tag', (tester) async {
      // Both of the route's 400s mean the same thing to the user: what the
      // sheet was drawn from is no longer what the printer sees.
      await registerRefused(
        tester,
        const ApiException(
          AppErrorCode.badResponse,
          statusCode: 400,
          detail: 'Slot has no RFID tag',
        ),
      );

      expect(
        find.text('Drukarka nie widzi już w tym slocie szpuli z czipem'),
        findsOneWidget,
      );
    });

    testWidgets('a refusal keeps the permission the server named', (
      tester,
    ) async {
      // 403 is exactly what the shared wording exists for: which permission is
      // missing lives only in what the server wrote.
      await registerRefused(
        tester,
        const AuthException(
          AppErrorCode.forbidden,
          detail: 'Missing permission: inventory:update',
        ),
      );

      expect(
        find.text('Brak uprawnień: Missing permission: inventory:update'),
        findsOneWidget,
      );
    });

    testWidgets('the scanner sits beside the search', (tester) async {
      await openSlotSheet(tester, state: 'IDLE', stocked: true);
      await reveal(tester, find.byType(TextField));

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics && w.properties.identifier == 'assign_spool.scan',
        ),
        findsOneWidget,
      );
    });
  });

  group('podgląd kamery', () {
    testWidgets('połączona drukarka: przycisk kamery otwiera podgląd', (
      tester,
    ) async {
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

    testWidgets('niepołączona drukarka: brak przycisku kamery', (tester) async {
      const item = PrinterWithStatus(printer: Printer(id: 2, name: 'A1 mini'));

      await tester.pumpWidget(_cardWithProviders(item));

      expect(find.byIcon(Icons.videocam_outlined), findsNothing);
    });
  });

  group('smart gniazdko', () {
    testWidgets(
      'załączone gniazdko: ikona wtyczki, moc w tooltipie, bez nazwy',
      (tester) async {
        final item = PrinterWithStatus(
          printer: const Printer(id: 1, name: 'X1C'),
          status: const PrinterStatus(id: 1, connected: true, state: 'IDLE'),
        );

        await tester.pumpWidget(
          _cardWithPlugs(item, _StubSmartPlugsNotifier(_plugState())),
        );

        // Sam symbol wtyczki; moc i nazwa nie zaśmiecają nagłówka.
        expect(find.byIcon(Icons.power), findsOneWidget);
        expect(find.byTooltip('42 W'), findsOneWidget); // moc w tooltipie
        expect(find.text('42 W'), findsNothing); // nie jako widoczny tekst
        expect(find.text('Szafa'), findsNothing);
        expect(find.byType(Switch), findsNothing);
      },
    );

    testWidgets('w trakcie druku przycisk jest wyszarzony (brak akcji)', (
      tester,
    ) async {
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

      // Przycisk zasilania wyłączony (onPressed == null) — nie da się nim ruszyć.
      final btn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.power),
      );
      expect(btn.onPressed, isNull);

      await tester.ensureVisible(find.byIcon(Icons.power));
      await tester.tap(find.byIcon(Icons.power), warnIfMissed: false);
      await tester.pump();

      expect(stub.calls, isEmpty); // zasilanie NIE zmienione
    });

    testWidgets('monitor-only MQTT plug: reading stays, button is dead', (
      tester,
    ) async {
      // The server refuses to switch an MQTT plug (400), so offering the button
      // would only produce an error the app can predict.
      final stub = _StubSmartPlugsNotifier(
        SmartPlugsState(
          plugs: const [
            SmartPlug(
              id: 10,
              name: 'Licznik',
              plugType: 'mqtt',
              printerId: 1,
              enabled: true,
              mqttPowerTopic: 'tele/x1c/SENSOR',
            ),
          ],
          statuses: {
            10: SmartPlugStatus(
              state: 'ON',
              reachable: true,
              energy: const SmartPlugEnergy(power: 42),
            ),
          },
        ),
      );
      final item = PrinterWithStatus(
        printer: const Printer(id: 1, name: 'X1C'),
        status: const PrinterStatus(id: 1, connected: true, state: 'IDLE'),
      );

      await tester.pumpWidget(_cardWithPlugs(item, stub));

      expect(find.byTooltip('42 W · Tylko podgląd'), findsOneWidget);
      final btn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.power),
      );
      expect(btn.onPressed, isNull);

      await tester.ensureVisible(find.byIcon(Icons.power));
      await tester.tap(find.byIcon(Icons.power), warnIfMissed: false);
      await tester.pump();

      expect(stub.calls, isEmpty);
    });

    testWidgets(
      'poza drukiem wyłączenie wymaga potwierdzenia, potem wysyła off',
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
      },
    );

    testWidgets('gniazdko offline (rozłączona drukarka) pozostaje sterowalne', (
      tester,
    ) async {
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
      await tester.pumpAndSettle();

      // Załączenie też wymaga potwierdzenia — bez niego nic nie wysyłamy.
      expect(find.text('Załączyć zasilanie?'), findsOneWidget);
      expect(stub.calls, isEmpty);

      await tester.tap(find.text('Włącz'));
      await tester.pump();
      expect(stub.calls.single.action, SmartPlugAction.on);
    });
  });

  group('OFFLINE debounce (no flashing after the power is cut)', () {
    // `model` is carried through a disconnect, so the details toggle stays on
    // the full layout — which is how these tests tell the two layouts apart.
    const onlineStatus = PrinterStatus(
      id: 1,
      connected: true,
      state: 'IDLE',
      model: 'X1C',
    );
    final connected = PrinterWithStatus(
      printer: const Printer(id: 1, name: 'X1C'),
      status: onlineStatus,
    );
    final off = PrinterWithStatus(
      printer: const Printer(id: 1, name: 'X1C'),
      status: const PrinterStatus(id: 1, connected: false, state: 'IDLE'),
    );
    // What the card is really handed when the printer drops: the frame goes
    // through `mergedWith`, which blanks the live state of an unreachable
    // printer — so the header has no state string left and falls back to the
    // "offline" label while the body is still on screen.
    final merged = PrinterWithStatus(
      printer: const Printer(id: 1, name: 'X1C'),
      status: const PrinterStatus(
        id: 1,
        connected: false,
      ).mergedWith(onlineStatus),
    );

    /// A line that has been up long enough for a second frame to contradict
    /// the first — the steady state the debounce was written for.
    DateTime steadyContact() => clock.now().subtract(const Duration(hours: 1));

    testWidgets('a disconnect collapses the card only after the grace period', (
      tester,
    ) async {
      final item = ValueNotifier<PrinterWithStatus>(connected);
      addTearDown(item.dispose);

      await tester.pumpWidget(_cardSwap(item, inTouchSince: steadyContact()));
      expect(find.text('OFFLINE'), findsNothing);

      item.value = off;
      await tester.pump(); // didUpdateWidget → timer starts, no collapse yet
      expect(find.text('OFFLINE'), findsNothing);

      await tester.pump(const Duration(seconds: 16)); // past the grace period
      expect(find.text('OFFLINE'), findsOneWidget);
    });

    testWidgets(
      'a connected blip inside the grace window does NOT collapse it',
      (tester) async {
        final item = ValueNotifier<PrinterWithStatus>(connected);
        addTearDown(item.dispose);

        await tester.pumpWidget(_cardSwap(item, inTouchSince: steadyContact()));

        item.value = off;
        await tester.pump();
        await tester.pump(
          const Duration(seconds: 5),
        ); // inside the grace period
        item.value = connected; // bambuddy reports online again → reset
        await tester.pump();
        await tester.pump(const Duration(seconds: 16));

        expect(find.text('OFFLINE'), findsNothing); // never collapsed
      },
    );

    testWidgets('a printer with nothing to report keeps its grace period', (
      tester,
    ) async {
      // An idle printer is silent by design: bambuddy drops a WS broadcast
      // whose status_key is unchanged, and the poll lane skips an ingest that
      // carries nothing new. Silence is therefore no evidence about the
      // printer — only the line matters, and the line is up.
      final item = ValueNotifier<PrinterWithStatus>(connected);
      addTearDown(item.dispose);

      await tester.pumpWidget(_cardSwap(item, inTouchSince: steadyContact()));
      await tester.pump(const Duration(seconds: 30)); // not a frame in sight

      item.value = merged;
      await tester.pump();
      expect(
        find.text('Szczegóły'),
        findsOneWidget,
      ); // debounced, not collapsed
      await tester.pump(const Duration(seconds: 16));
      expect(find.text('Szczegóły'), findsNothing);
    });

    testWidgets('a disconnect on a line that just came up collapses at once', (
      tester,
    ) async {
      // The everyday case: the app spent the night in the background with the
      // socket closed and polling stopped, the printer was switched off in the
      // meantime, and the first frame after the resume says so. Nothing can
      // contradict a frame that arrived with the line, so there is no reason to
      // hold the layout up for another 15 seconds.
      final item = ValueNotifier<PrinterWithStatus>(connected);
      addTearDown(item.dispose);

      await tester.pumpWidget(_cardSwap(item, inTouchSince: clock.now()));
      item.value = merged;
      await tester.pump();

      expect(find.text('OFFLINE'), findsOneWidget);
      expect(find.text('Szczegóły'), findsNothing);
    });

    testWidgets('a printer the roster carries with no status at all is offline', (
      tester,
    ) async {
      // Not the same as a frame whose `connected` is missing: here there is no
      // status to read at all, so the card knows nothing about the printer and
      // says so, the way it always has.
      await tester.pumpWidget(
        _cardWithProviders(
          const PrinterWithStatus(printer: Printer(id: 1, name: 'X1C')),
        ),
      );

      expect(find.text('OFFLINE'), findsOneWidget);
      expect(find.text('Szczegóły'), findsNothing);
    });

    testWidgets('a frame that never mentions the connection leaves the card be', (
      tester,
    ) async {
      // An older server, or a payload carrying a subset of the fields. Read as
      // "offline" it would collapse a printer that may well be printing, so it
      // is read as what it is: no news.
      final item = ValueNotifier<PrinterWithStatus>(connected);
      addTearDown(item.dispose);

      await tester.pumpWidget(_cardSwap(item, inTouchSince: steadyContact()));
      item.value = const PrinterWithStatus(
        printer: Printer(id: 1, name: 'X1C'),
        status: PrinterStatus(id: 1, state: 'RUNNING', model: 'X1C'),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));

      expect(find.text('OFFLINE'), findsNothing);
      expect(find.text('Szczegóły'), findsOneWidget);
    });

    testWidgets('inside the grace window the header already reads as offline', (
      tester,
    ) async {
      final item = ValueNotifier<PrinterWithStatus>(connected);
      addTearDown(item.dispose);

      await tester.pumpWidget(_cardSwap(item, inTouchSince: steadyContact()));
      item.value = merged;
      await tester.pump();

      // The body is still up (the collapse waits out the grace period), so the
      // header is the only thing saying the printer is unreachable — it must
      // not say it in the colour that means "connected".
      final chip = tester.widget<Text>(find.text('OFFLINE'));
      final scheme = Theme.of(tester.element(find.text('OFFLINE'))).colorScheme;
      expect(chip.style?.color, scheme.error);

      // Proof that this was the full layout and not the collapsed one: the
      // details toggle is on screen here and gone once the card collapses.
      expect(find.text('Szczegóły'), findsOneWidget);
      await tester.pump(const Duration(seconds: 16));
      expect(find.text('Szczegóły'), findsNothing);
    });
  });

  group('_CoverThumbnail', () {
    testWidgets('drukarka z coverUrl: pokazuje Image gdy token dostępny', (
      tester,
    ) async {
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

      // Próbujemy załadować okładkę (obraz sieciowy), a nie placeholder.
      expect(find.byKey(const ValueKey('cover_network')), findsOneWidget);
    });

    testWidgets(
      'drukarka bez coverUrl: pokazuje placeholder, bez obrazu sieciowego',
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

        expect(find.byKey(const ValueKey('cover_placeholder')), findsOneWidget);
        expect(find.byKey(const ValueKey('cover_network')), findsNothing);
      },
    );

    testWidgets('kalibracja: placeholder zamiast (przeterminowanej) okładki', (
      tester,
    ) async {
      final item = PrinterWithStatus(
        printer: const Printer(id: 3, name: 'X2D'),
        status: const PrinterStatus(
          id: 3,
          connected: true,
          state: 'RUNNING',
          progress: 14,
          remainingTime: 39,
          gcodeFile: 'auto_cali_for_user_param.gcode',
          // okładka poprzedniego druku nie może się pokazać
          coverUrl: '/api/v1/printers/3/cover',
        ),
      );

      await tester.pumpWidget(_cardWithProviders(item));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('cover_placeholder')), findsOneWidget);
      expect(find.byKey(const ValueKey('cover_network')), findsNothing);
    });
  });

  group('firmware pod nazwą drukarki', () {
    Widget cardWithFirmware(FirmwareUpdateInfo info) => ProviderScope(
      overrides: [
        fakeServerProfileOverride(),
        cameraTokenProvider.overrideWith((ref) async => 'tok'),
        inertSmartPlugsOverride,
        printerFirmwareProvider(1).overrideWithValue(info),
      ],
      child: plApp(
        Scaffold(
          body: SingleChildScrollView(
            child: PrinterCard(
              item: const PrinterWithStatus(
                printer: Printer(id: 1, name: 'X2D'),
                status: PrinterStatus(id: 1, connected: true),
              ),
            ),
          ),
        ),
      ),
    );

    testWidgets('dostępna aktualizacja: „bieżąca → najnowsza" + ikona update', (
      tester,
    ) async {
      await tester.pumpWidget(
        cardWithFirmware(
          const FirmwareUpdateInfo(
            printerId: 1,
            currentVersion: '01.02.03',
            latestVersion: '01.02.05',
            updateAvailable: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('01.02.03 → 01.02.05'), findsOneWidget);
      expect(find.byIcon(Icons.system_update), findsOneWidget);
    });

    testWidgets('aktualne: sama wersja, bez ikony aktualizacji', (
      tester,
    ) async {
      await tester.pumpWidget(
        cardWithFirmware(
          const FirmwareUpdateInfo(
            printerId: 1,
            currentVersion: '01.02.03',
            latestVersion: '01.02.03',
            updateAvailable: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('01.02.03'), findsOneWidget);
      // Aktualna wersja: sama linia mono, bez ikony aktualizacji.
      expect(find.byIcon(Icons.system_update), findsNothing);
    });

    testWidgets('brak danych firmware: brak linii (nie wywraca karty)', (
      tester,
    ) async {
      await pumpPhone(
        tester,
        const Scaffold(
          body: PrinterCard(
            item: PrinterWithStatus(
              printer: Printer(id: 1, name: 'X2D'),
              status: PrinterStatus(id: 1, connected: true),
            ),
          ),
        ),
        overrides: [
          fakeServerProfileOverride(),
          cameraTokenProvider.overrideWith((ref) async => 'tok'),
          inertSmartPlugsOverride,
          inertFirmwareOverride, // zwraca null
          inertTotalPrintHoursOverride,
          inertChamberMaxOverride,
          ...inertHistorySupportOverrides,
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text('X2D'), findsOneWidget); // karta żyje
      expect(find.byIcon(Icons.system_update), findsNothing);
      expect(find.byIcon(Icons.memory), findsNothing);
    });
  });

  group('identyfikatory do logu zgłoszeń', () {
    /// Wspólne widżety karty (kafelek czujnika, przyciski arkusza, presety)
    /// tagowały się wcześniej **w środku**, więc każdy z nich schodził do logu
    /// jako `temperature.*`: tapnięcie „Wyłącz" w arkuszu temperatury raportowało
    /// się identycznie jak „Ustaw", a z trzech kafelków dyszy nie wynikało, który
    /// user tknął. To ta sama klasa co przesunięte id dialogów potwierdzenia —
    /// log twierdzi, że user zrobił coś innego, niż zrobił.
    Iterable<String> identifiersIn(WidgetTester tester) => tester
        .widgetList<Semantics>(find.byType(Semantics))
        .map((s) => s.properties.identifier)
        .whereType<String>();

    testWidgets('każdy czujnik ma własny identyfikator kafelka', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardWithProviders(
          const PrinterWithStatus(
            printer: Printer(id: 1, name: 'X2D'),
            status: PrinterStatus(
              id: 1,
              connected: true,
              temperatures: {'nozzle': 220, 'nozzle_2': 39, 'bed': 55},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ids = identifiersIn(tester).toSet();
      expect(
        ids,
        containsAll(<String>{
          'printer.temperature_nozzle',
          'printer.temperature_nozzle_2',
          'printer.temperature_bed',
        }),
      );
    });

    testWidgets('skrót do historii ma własny identyfikator per czujnik', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardWithProviders(
          const PrinterWithStatus(
            printer: Printer(id: 1, name: 'X2D'),
            status: PrinterStatus(
              id: 1,
              connected: true,
              temperatures: {'nozzle': 220, 'bed': 55, 'cośdziwnego': 12},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ids = identifiersIn(tester).toSet();
      expect(
        ids,
        containsAll(<String>{
          'printer.temperature_history_nozzle',
          'printer.temperature_history_bed',
        }),
      );
      // Czujnik, którego serwer nie zapisuje, nie dostaje ikony wykresu —
      // wykres byłby pusty.
      expect(
        ids.where((i) => i.startsWith('printer.temperature_history')),
        hasLength(2),
      );
    });

    testWidgets('„wyłącz" i „ustaw" w arkuszu to dwie różne nazwy', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardWithProviders(
          const PrinterWithStatus(
            printer: Printer(id: 1, name: 'X2D'),
            status: PrinterStatus(
              id: 1,
              connected: true,
              state: 'IDLE',
              temperatures: {'nozzle': 220, 'nozzle_target': 220},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tapnięcie w kafelek po jego własnym identyfikatorze — czyli po tym, co
      // sonda zapisze do logu.
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.identifier == 'printer.temperature_nozzle',
        ),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      final ids = identifiersIn(tester).toSet();
      expect(ids, containsAll(<String>{'temperature.off', 'temperature.set'}));
      expect(ids, isNot(contains('temperature.apply')));
    });
  });

  group('HMS error panel', () {
    // The panel resolves codes through the real catalog asset, in the same
    // language the card is rendered in — a stub resolver would test nothing
    // about what a user sees.
    setUpAll(() => HmsCatalog.instance.load(const Locale('pl')));

    PrinterWithStatus itemWith(List<HmsError> errors) => PrinterWithStatus(
      printer: const Printer(id: 9, name: 'X2D Warsztat'),
      status: PrinterStatus(
        id: 9,
        connected: true,
        state: 'RUNNING',
        progress: 40,
        hmsErrors: errors,
      ),
    );

    testWidgets('an uncataloged code renders nothing, not a fatal fault', (
      tester,
    ) async {
      // The 2026-07-29 report: healthy X2D, red card. Module 5 and the severity
      // the server derives from part_id used to compose "Krytyczny · płyta
      // główna" for a code the catalog does not have.
      await tester.pumpWidget(
        _cardWithProviders(
          itemWith(const [
            HmsError(code: '0x20070', attr: 83887616, module: 5, severity: 1),
          ]),
        ),
      );

      expect(find.text('Aktywne błędy'), findsNothing);
      expect(find.textContaining('0500-0600'), findsNothing);
      expect(find.textContaining('Krytyczny'), findsNothing);
      expect(find.textContaining('płyta główna'), findsNothing);
      // The rest of the card is untouched — hiding the code is not a blackout.
      expect(find.text('X2D Warsztat'), findsOneWidget);
      expect(find.text('RUNNING'), findsOneWidget);
    });

    testWidgets('a print error is announced by count and opens on a tap', (
      tester,
    ) async {
      await tester.pumpWidget(_cardWithProviders(itemWith(const [_runout])));

      // Collapsed: the count, and nothing that would push the print progress
      // off a phone screen.
      expect(find.text('1 błąd'), findsOneWidget);
      expect(find.textContaining('Skończył się filament'), findsNothing);

      await tester.tap(find.text('1 błąd'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Skończył się filament'), findsOneWidget);
      expect(find.text('0300-8004'), findsOneWidget);
      expect(find.text('Odrzuć wszystkie'), findsOneWidget);
    });

    testWidgets('a mixed list counts and shows only the codes it can name', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardWithProviders(
          itemWith(const [
            HmsError(code: '0x20070', attr: 83887616, module: 5, severity: 1),
            _runout,
          ]),
        ),
      );

      expect(find.text('1 błąd'), findsOneWidget);
      await tester.tap(find.text('1 błąd'));
      await tester.pumpAndSettle();

      expect(find.text('0300-8004'), findsOneWidget);
      expect(find.textContaining('0500-0600'), findsNothing);
    });

    testWidgets('only the actions the server can send get a button', (
      tester,
    ) async {
      await tester.pumpWidget(
        _cardWithProviders(
          itemWith(const [
            HmsError(
              code: '0x8004',
              attr: 0x03008004,
              module: 3,
              severity: 3,
              fullCode: '03008004',
              // CHECK_ASSISTANT reaches the server's no-op branch: the printer's
              // own screen owns it, so a button here would publish nothing.
              actions: ['RESUME_PRINTING', 'CHECK_ASSISTANT', 'STOP_PRINTING'],
            ),
          ]),
        ),
      );
      await tester.tap(find.text('1 błąd'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Wznów'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Zatrzymaj'), findsOneWidget);
      expect(find.textContaining('Asystent'), findsNothing);
    });

    testWidgets('an action sends the full code verbatim, with its job id', (
      tester,
    ) async {
      final commands = _RecordingCommands();
      await tester.pumpWidget(
        _cardWithProviders(
          itemWith(const [_runoutWithActions]),
          extra: [
            printerCommandsRepositoryProvider.overrideWithValue(commands),
          ],
        ),
      );
      await tester.tap(find.text('1 błąd'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Wznów'));
      await tester.pumpAndSettle();

      expect(commands.calls, ['action:9:03008004:RESUME_PRINTING:746795586']);
    });

    testWidgets('stopping the print is confirmed before anything is sent', (
      tester,
    ) async {
      final commands = _RecordingCommands();
      await tester.pumpWidget(
        _cardWithProviders(
          itemWith(const [_runoutWithActions]),
          extra: [
            printerCommandsRepositoryProvider.overrideWithValue(commands),
          ],
        ),
      );
      await tester.tap(find.text('1 błąd'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Zatrzymaj'));
      await tester.pumpAndSettle();

      // The dialog names the printer, and nothing has been sent yet.
      expect(find.textContaining('X2D Warsztat'), findsWidgets);
      expect(commands.calls, isEmpty);

      await tester.tap(find.text('Anuluj'));
      await tester.pumpAndSettle();
      expect(commands.calls, isEmpty);
    });

    testWidgets('dismiss-all clears the printer, not one error', (
      tester,
    ) async {
      final commands = _RecordingCommands();
      await tester.pumpWidget(
        _cardWithProviders(
          itemWith(const [_runoutWithActions]),
          extra: [
            printerCommandsRepositoryProvider.overrideWithValue(commands),
          ],
        ),
      );
      await tester.tap(find.text('1 błąd'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Odrzuć wszystkie'));
      await tester.pumpAndSettle();

      expect(commands.calls, ['clear:9']);
    });

    testWidgets('a long description is cut to two lines until tapped', (
      tester,
    ) async {
      // 0300_8016 is one of the wordy ones. Three faults each spending five
      // lines on prose is how the card ran off the screen.
      final clog = HmsError.fromJson(const {
        'code': '0x8016',
        'attr': 0x03008016,
        'full_code': '03008016',
      });
      await tester.pumpWidget(_cardWithProviders(itemWith([clog])));
      await tester.tap(find.text('1 błąd'));
      await tester.pumpAndSettle();

      final description = find.textContaining('Dysza jest zatkana');
      expect(tester.widget<Text>(description).maxLines, 2);

      await tester.tap(description);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(description).maxLines, isNull);
    });

    testWidgets('the description no longer names the button below it', (
      tester,
    ) async {
      // Bambu writes for its own dialog: "…or select 'Resume' to resume the
      // print job", with a Resume button right there. The app draws that button
      // from the fault's actions, so the sentence was the button said twice.
      await tester.pumpWidget(_cardWithProviders(itemWith(const [_runout])));
      await tester.tap(find.text('1 błąd'));
      await tester.pumpAndSettle();

      expect(find.textContaining("wybierz 'Wznów'"), findsNothing);
      expect(find.textContaining('Wznów”'), findsNothing);
    });

    testWidgets('a blank full code offers no buttons either', (tester) async {
      // The server's own default for the field is `""`, which would otherwise
      // pass the null check and post an empty code the route rejects with 422.
      final blank = HmsError.fromJson(const {
        'code': '0x8004',
        'attr': 0x03008004,
        'full_code': '',
        'actions': ['RESUME_PRINTING'],
      });
      await tester.pumpWidget(_cardWithProviders(itemWith([blank])));
      await tester.tap(find.text('1 błąd'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Skończył się filament'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Wznów'), findsNothing);
    });

    testWidgets('feedback survives the fault clearing under the card', (
      tester,
    ) async {
      // The command succeeds, the next status frame drops the fault, and the
      // card that would have shown the snackbar is gone by then — the user
      // still has to be told it went through.
      final commands = _RecordingCommands();
      final item = ValueNotifier<PrinterWithStatus>(
        itemWith(const [_runoutWithActions]),
      );
      addTearDown(item.dispose);
      await tester.pumpWidget(
        _scope(
          Scaffold(
            body: ValueListenableBuilder<PrinterWithStatus>(
              valueListenable: item,
              builder: (_, it, _) =>
                  SingleChildScrollView(child: PrinterCard(item: it)),
            ),
          ),
          extra: [
            printerCommandsRepositoryProvider.overrideWithValue(commands),
          ],
        ),
      );
      await tester.tap(find.text('1 błąd'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Wznów'));
      item.value = itemWith(const []); // the fault clears mid-command
      await tester.pumpAndSettle();

      expect(commands.calls, hasLength(1));
      expect(find.text('Wysłano do drukarki'), findsOneWidget);
    });

    testWidgets('a server too old to send full_code offers no buttons', (
      tester,
    ) async {
      // Pre-0.2.4.8: the fault is named (short-code lookup) but there is no
      // identifier the firmware would match a command against, and a guessed
      // one is dropped without a word.
      await tester.pumpWidget(
        _cardWithProviders(
          itemWith(const [
            HmsError(
              code: '0x8004',
              attr: 0x03008004,
              module: 3,
              severity: 3,
              actions: ['RESUME_PRINTING'],
            ),
          ]),
        ),
      );
      await tester.tap(find.text('1 błąd'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Skończył się filament'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Wznów'), findsNothing);
    });
  });

  group('plate-clear gate on an unreachable printer', () {
    // How every print ends with Auto Power Off: the job finished, bambuddy cut
    // the power at the plug, and the plate is still flagged dirty. The gate is
    // bambuddy's own flag, so acknowledging it needs nothing from the machine.
    const awaitingOffline = PrinterWithStatus(
      printer: Printer(id: 4, name: 'X2D-3DP'),
      status: PrinterStatus(id: 4, connected: false, awaitingPlateClear: true),
    );
    const awaitingOnline = PrinterWithStatus(
      printer: Printer(id: 5, name: 'A1 mini'),
      status: PrinterStatus(
        id: 5,
        connected: true,
        state: 'FINISH',
        awaitingPlateClear: true,
      ),
    );

    Widget cards(
      _RecordingCommands commands, {
      List<PrinterWithStatus> items = const [awaitingOffline],
    }) => _scope(
      Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [for (final item in items) PrinterCard(item: item)],
          ),
        ),
      ),
      extra: [
        requirePlateClearProvider.overrideWith((ref) async => true),
        printerCommandsRepositoryProvider.overrideWithValue(commands),
        printerStatusesProvider.overrideWith(_InertStatuses.new),
      ],
    );

    testWidgets('the collapsed OFFLINE card still offers the acknowledgement', (
      tester,
    ) async {
      final commands = _RecordingCommands();
      await tester.pumpWidget(cards(commands));
      await tester.pumpAndSettle();

      expect(find.text('OFFLINE'), findsOneWidget);
      expect(find.text('Płyta niewyczyszczona'), findsOneWidget);

      await tester.tap(find.byTooltip('Oznacz płytę jako pustą'));
      await tester.pumpAndSettle();

      expect(commands.calls, ['clearPlate:4']);
      expect(find.text('Oznaczono płytę jako pustą'), findsOneWidget);
    });

    testWidgets(
      'an old server\'s refusal is explained, then the button stands down',
      (tester) async {
        // Pre-#2864 the route answered 400 "Printer not connected". Nothing in a
        // response says which contract the server serves and the version cannot
        // tell (every 1.2.6 daily build reports 1.2.6b1), so the refusal itself
        // is the answer: the offline button withdraws, the online one does not.
        final commands = _RecordingCommands()
          ..clearPlateError = const ApiException(
            AppErrorCode.badResponse,
            statusCode: 400,
            detail: 'Printer not connected',
          );
        await tester.pumpWidget(
          cards(commands, items: const [awaitingOffline, awaitingOnline]),
        );
        await tester.pumpAndSettle();

        expect(find.byTooltip('Oznacz płytę jako pustą'), findsNWidgets(2));

        await tester.tap(find.byTooltip('Oznacz płytę jako pustą').first);
        await tester.pumpAndSettle();

        expect(commands.calls, ['clearPlate:4']);
        expect(find.textContaining('Zaktualizuj bambuddy'), findsOneWidget);
        // The reachable printer keeps it: that half worked on every server.
        expect(find.text('Płyta niewyczyszczona'), findsOneWidget);
        expect(find.byTooltip('Oznacz płytę jako pustą'), findsOneWidget);
      },
    );

    testWidgets('a refusal that lands after the card is gone still counts', (
      tester,
    ) async {
      // The window this closes: the answer comes back when the banner is no
      // longer in the tree — the printer reconnected and the card swapped
      // layout, or the dashboard was left. Reaching for `ref` there throws
      // ("Cannot use ref after the widget was disposed"), so the latch is read
      // out before the request, and the observation outlives the widget.
      final held = Completer<void>();
      final commands = _RecordingCommands()
        ..clearPlateHeld = held
        ..clearPlateError = const ApiException(
          AppErrorCode.badResponse,
          statusCode: 400,
          detail: 'Printer not connected',
        );
      final onScreen = ValueNotifier<bool>(true);
      addTearDown(onScreen.dispose);

      // One stable scope — the container is the app's and never goes away; what
      // goes away is the card.
      await tester.pumpWidget(
        _scope(
          Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: onScreen,
              builder: (_, visible, _) => visible
                  ? const PrinterCard(item: awaitingOffline)
                  : const SizedBox.shrink(),
            ),
          ),
          extra: [
            requirePlateClearProvider.overrideWith((ref) async => true),
            printerCommandsRepositoryProvider.overrideWithValue(commands),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Oznacz płytę jako pustą'));
      await tester.pump();

      onScreen.value = false;
      await tester.pump();
      held.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // The latch still flipped: the card comes back without the button.
      onScreen.value = true;
      await tester.pumpAndSettle();
      expect(find.text('OFFLINE'), findsOneWidget);
      expect(find.byTooltip('Oznacz płytę jako pustą'), findsNothing);
    });

    testWidgets(
      'nothing is offered while the scheduler does not gate on the plate',
      (tester) async {
        final commands = _RecordingCommands();
        await tester.pumpWidget(
          _cardWithProviders(
            awaitingOffline,
            extra: [
              requirePlateClearProvider.overrideWith((ref) async => false),
              printerCommandsRepositoryProvider.overrideWithValue(commands),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('OFFLINE'), findsOneWidget);
        expect(find.text('Płyta niewyczyszczona'), findsNothing);
      },
    );
  });

  group('scheduled drying', () {
    /// A printer whose AMS 1 is an AMS 2 Pro — the module type is what decides
    /// whether the dry chip, and with it the schedule, is offered at all.
    PrinterWithStatus dryable({int dryTime = 0}) => PrinterWithStatus(
      printer: const Printer(id: 3, name: 'X2D'),
      status: PrinterStatus(
        id: 3,
        connected: true,
        state: 'IDLE',
        supportsDrying: true,
        ams: [
          AmsUnit(
            id: 1,
            humidity: 28,
            temp: 24,
            moduleType: 'n3f',
            dryTime: dryTime,
            trays: const [AmsTray(id: 0, trayType: 'PLA')],
          ),
        ],
      ),
    );

    ScheduledDrying pending({
      int id = 7,
      int amsId = 1,
      String status = 'pending',
      DateTime? startAfter,
      DryingWaitReason? waitingReason,
      String? errorMessage,
    }) => ScheduledDrying(
      id: id,
      printerId: 3,
      amsId: amsId,
      temp: 65,
      durationHours: 8,
      filament: 'PETG',
      rotateTray: false,
      status: status,
      startAfter: startAfter,
      waitingReason: waitingReason,
      errorMessage: errorMessage,
    );

    Future<void> openDetails(WidgetTester tester) async {
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.identifier == 'printer.details_toggle',
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> pumpCard(
      WidgetTester tester,
      _StubScheduledDrying repo, {
      int dryTime = 0,
    }) async {
      await tester.pumpWidget(
        _cardWithProviders(
          dryable(dryTime: dryTime),
          extra: [scheduledDryingRepositoryProvider.overrideWithValue(repo)],
        ),
      );
      await tester.pumpAndSettle();
      await openDetails(tester);
    }

    testWidgets('a pending run says when it starts, under its AMS', (
      tester,
    ) async {
      final repo = _StubScheduledDrying(
        rows: [pending(startAfter: DateTime(2026, 9, 4, 21, 30))],
      );

      await pumpCard(tester, repo);

      // The instant itself is formatted by the shared date/time helper, whose
      // 12/24-hour choice follows the device — so the assertion is on the
      // sentence that says a time was named at all, not on its spelling.
      expect(find.textContaining('Suszenie:'), findsOneWidget);
      expect(
        find.text('Suszenie zaplanowane, czeka na drukarkę'),
        findsNothing,
      );
    });

    testWidgets('a run with no time says it is waiting for the printer', (
      tester,
    ) async {
      final repo = _StubScheduledDrying(rows: [pending()]);

      await pumpCard(tester, repo);

      expect(
        find.text('Suszenie zaplanowane, czeka na drukarkę'),
        findsOneWidget,
      );
    });

    testWidgets('a due run explains what it is waiting for', (tester) async {
      final repo = _StubScheduledDrying(
        rows: [pending(waitingReason: DryingWaitReason.powerRequired)],
      );

      await pumpCard(tester, repo);

      expect(find.text('Podłącz zasilacz AMS'), findsOneWidget);
    });

    /// A reason added by a server newer than this build must not be printed at
    /// the user as its wire identifier.
    testWidgets('a reason this build cannot word is left unsaid', (
      tester,
    ) async {
      final repo = _StubScheduledDrying(
        rows: [pending(waitingReason: DryingWaitReason.unknown)],
      );

      await pumpCard(tester, repo);

      expect(
        find.text('Suszenie zaplanowane, czeka na drukarkę'),
        findsOneWidget,
      );
      expect(find.textContaining('unknown'), findsNothing);
    });

    testWidgets('a failed run says why, and offers to be dismissed', (
      tester,
    ) async {
      final repo = _StubScheduledDrying(
        rows: [pending(status: 'failed', errorMessage: 'Firmware too old')],
      );

      await pumpCard(tester, repo);

      expect(
        find.text('Zaplanowane suszenie nie ruszyło: Firmware too old'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Odrzuć'));
      await tester.pumpAndSettle();

      expect(repo.cancelled, [7]);
    });

    testWidgets('a run for another AMS is not shown on this one', (
      tester,
    ) async {
      final repo = _StubScheduledDrying(rows: [pending(amsId: 0)]);

      await pumpCard(tester, repo);

      expect(find.textContaining('Suszenie zaplanowane'), findsNothing);
    });

    testWidgets('cancelling a pending run drops it and re-reads the listing', (
      tester,
    ) async {
      final repo = _StubScheduledDrying(rows: [pending()]);

      await pumpCard(tester, repo);
      expect(repo.listCalls, 1);

      await tester.tap(find.byTooltip('Anuluj zaplanowane suszenie'));
      await tester.pumpAndSettle();

      expect(repo.cancelled, [7]);
      expect(repo.listCalls, 2);
      expect(find.textContaining('Suszenie zaplanowane'), findsNothing);
    });

    /// The live AMS reports a dispatched run long before anything else would
    /// ask the server again; without the re-read the banner would go on
    /// promising a run that is already going.
    testWidgets('the AMS starting to dry re-reads the listing', (tester) async {
      final repo = _StubScheduledDrying(rows: [pending()]);
      final item = ValueNotifier(dryable());
      addTearDown(item.dispose);

      await tester.pumpWidget(
        _scope(
          Scaffold(
            body: SingleChildScrollView(
              child: ValueListenableBuilder<PrinterWithStatus>(
                valueListenable: item,
                builder: (_, it, _) =>
                    PrinterCard(key: const ValueKey('card'), item: it),
              ),
            ),
          ),
          extra: [scheduledDryingRepositoryProvider.overrideWithValue(repo)],
        ),
      );
      await tester.pumpAndSettle();
      await openDetails(tester);
      expect(repo.listCalls, 1);

      repo.rows.clear(); // the scheduler picked it up
      item.value = dryable(dryTime: 120);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(repo.listCalls, 2);
      expect(find.textContaining('Suszenie zaplanowane'), findsNothing);
    });

    testWidgets('an older server offers the sheet without the later modes', (
      tester,
    ) async {
      final repo = _StubScheduledDrying(supported: false);

      await pumpCard(tester, repo);
      await tester.tap(find.text('Suszenie'));
      await tester.pumpAndSettle();

      expect(find.text('Start'), findsOneWidget); // the immediate button
      expect(find.text('Teraz'), findsNothing);
      expect(find.text('Zaplanuj'), findsNothing);
    });

    testWidgets('a delay is measured from the moment the button is pressed', (
      tester,
    ) async {
      final repo = _StubScheduledDrying();
      final at = DateTime(2026, 9, 3, 20);

      await withClock(Clock.fixed(at), () async {
        await pumpCard(tester, repo);
        await tester.tap(find.text('Suszenie'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Później'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('2h'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Zaplanuj'));
        await tester.pumpAndSettle();
      });

      expect(repo.created, hasLength(1));
      expect(repo.created.single.startAfter, at.add(const Duration(hours: 2)));
      expect(repo.created.single.amsId, 1);
      // The sheet's own filament/temperature pickers travel with it.
      expect(repo.created.single.filament, 'PLA');
      expect(repo.created.single.temp, 45);
      expect(find.text('Suszenie zaplanowane'), findsOneWidget);
    });

    testWidgets('"at time" with nothing picked schedules nothing', (
      tester,
    ) async {
      final repo = _StubScheduledDrying();

      await pumpCard(tester, repo);
      await tester.tap(find.text('Suszenie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('O godzinie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zaplanuj'));
      await tester.pumpAndSettle();

      expect(repo.created, isEmpty);
      // The prompt, not a dryer that started immediately.
      expect(find.text('Wybierz termin'), findsWidgets);
    });

    /// Opens the drying sheet on a card whose server answers [settings].
    Future<void> pumpWithSettings(
      WidgetTester tester,
      Map<String, dynamic> settings,
    ) async {
      await tester.pumpWidget(
        _cardWithProviders(
          dryable(),
          extra: [
            scheduledDryingRepositoryProvider.overrideWithValue(
              _StubScheduledDrying(),
            ),
            serverSettingsProvider.overrideWith((ref) async => settings),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await openDetails(tester);
      await tester.tap(find.text('Suszenie'));
      await tester.pumpAndSettle();
    }

    /// The drying temperatures and durations are the server's, not a table
    /// bundled with the app: a user who set PETG to 70 °C on the web must not
    /// have the phone start — or schedule — a run at 65.
    group('presets come from the server', () {
      testWidgets('a configured table is what the sheet seeds from', (
        tester,
      ) async {
        await pumpWithSettings(tester, const {
          'drying_presets':
              '{"PETG":{"n3f":60,"n3s":72,"n3f_hours":8,'
              '"n3s_hours":6}}',
        });

        // The only filament the server knows is the one the sheet opens on.
        expect(find.text('60°'), findsWidgets);
        expect(find.text('8 godz'), findsWidgets);
      });

      /// The web's own drying popover caps the same way (`maxTemp` there is
      /// 85 for an `n3s` and 65 otherwise), so a table configured for an AMS-HT
      /// does not send an AMS 2 Pro a temperature it cannot hold.
      testWidgets('a preset above what the module can hold is capped', (
        tester,
      ) async {
        await pumpWithSettings(tester, const {
          'drying_presets':
              '{"PETG":{"n3f":70,"n3s":85,"n3f_hours":8,'
              '"n3s_hours":6}}',
        });

        expect(find.text('65°'), findsWidgets);
        expect(find.text('70°'), findsNothing);
      });

      testWidgets('a filament the server dropped is not offered', (
        tester,
      ) async {
        await pumpWithSettings(tester, const {
          'drying_presets':
              '{"PETG":{"n3f":70,"n3s":72,"n3f_hours":8,'
              '"n3s_hours":6}}',
        });

        await tester.tap(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics && w.properties.identifier == 'drying.filament',
          ),
        );
        await tester.pumpAndSettle();

        // Counted through the option tag rather than by text: the AMS row on
        // the card behind the sheet shows its loaded spool's material too.
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                (w.properties.identifier ?? '').startsWith(
                  'drying.filament_option',
                ),
          ),
          findsOneWidget,
        );
      });

      testWidgets('nothing configured falls back to the bundled table', (
        tester,
      ) async {
        await pumpWithSettings(tester, const {'drying_presets': ''});

        // PLA on an AMS 2 Pro: 45 °C for 12 h, the server's own default.
        expect(find.text('45°'), findsWidgets);
        expect(find.text('12 godz'), findsWidgets);
      });

      testWidgets('settings that could not be read fall back too', (
        tester,
      ) async {
        await pumpWithSettings(tester, const {});

        expect(find.text('45°'), findsWidgets);
        expect(find.text('12 godz'), findsWidgets);
      });

      /// The scheduler dries with the same numbers, so a schedule built from a
      /// stale table would be wrong in exactly the way this reads settings to
      /// avoid.
      testWidgets('a scheduled run carries the server\'s numbers', (
        tester,
      ) async {
        final repo = _StubScheduledDrying();
        await tester.pumpWidget(
          _cardWithProviders(
            dryable(),
            extra: [
              scheduledDryingRepositoryProvider.overrideWithValue(repo),
              serverSettingsProvider.overrideWith(
                (ref) async => const {
                  'drying_presets':
                      '{"PETG":{"n3f":60,"n3s":72,'
                      '"n3f_hours":8,"n3s_hours":6}}',
                },
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await openDetails(tester);
        await tester.tap(find.text('Suszenie'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Później'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Zaplanuj'));
        await tester.pumpAndSettle();

        expect(repo.created.single.temp, 60);
        expect(repo.created.single.durationHours, 8);
        expect(repo.created.single.filament, 'PETG');
      });
    });

    /// The server can start a cycle nobody asked for. Saying so is all the app
    /// does about it — the three settings behind it are `settings:update`,
    /// which an API key can never hold.
    group('the server dries by itself', () {
      testWidgets('ambient drying is named', (tester) async {
        await pumpWithSettings(tester, const {'ambient_drying_enabled': true});

        expect(
          find.text('Auto-suszenie przy wysokiej wilgotności.'),
          findsOneWidget,
        );
      });

      testWidgets('queue drying is named when ambient is off', (tester) async {
        await pumpWithSettings(tester, const {'queue_drying_enabled': true});

        expect(find.text('Auto-suszenie między wydrukami.'), findsOneWidget);
      });

      /// Ambient covers the queue case, so naming both would say it twice.
      testWidgets('both on says the wider of the two', (tester) async {
        await pumpWithSettings(tester, const {
          'ambient_drying_enabled': true,
          'queue_drying_enabled': true,
        });

        expect(find.text('Auto-suszenie między wydrukami.'), findsNothing);
        expect(
          find.text('Auto-suszenie przy wysokiej wilgotności.'),
          findsOneWidget,
        );
      });

      testWidgets('drying during a print is added to the sentence', (
        tester,
      ) async {
        await pumpWithSettings(tester, const {
          'ambient_drying_enabled': true,
          'print_drying_enabled': true,
        });

        expect(
          find.text(
            'Auto-suszenie przy wysokiej wilgotności. '
            'Także w druku.',
          ),
          findsOneWidget,
        );
      });

      /// On its own it only widens the two automations above it, so with both
      /// off there is nothing happening to report.
      testWidgets('drying during a print alone says nothing', (tester) async {
        await pumpWithSettings(tester, const {'print_drying_enabled': true});

        expect(find.textContaining('Auto-suszenie'), findsNothing);
      });

      testWidgets('a server that dries nothing by itself stays quiet', (
        tester,
      ) async {
        await pumpWithSettings(tester, const {});

        expect(find.textContaining('Auto-suszenie'), findsNothing);
      });
    });

    /// What a screen reader is told about the sheet, and what the diagnostic log
    /// is told about the same widgets. They travel on one semantics tree, so a
    /// change made for one is checked against the other here.
    group('semantics', () {
      Future<void> openSheet(WidgetTester tester) async {
        await pumpCard(tester, _StubScheduledDrying());
        await tester.tap(find.text('Suszenie'));
        await tester.pumpAndSettle();
      }

      SemanticsNode node(WidgetTester tester, String id) => tester.getSemantics(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.identifier == id,
        ),
      );

      /// A `Semantics(identifier:)` forms a node *around* the control rather
      /// than on it — the same shape `InteractionProbe` carries an id down
      /// through — so a slider's spoken value sits one level below the tag.
      String valueUnder(WidgetTester tester, String id) {
        var found = '';
        node(tester, id).visitChildren((child) {
          if (child.value.isNotEmpty) found = child.value;
          return found.isEmpty;
        });
        return found;
      }

      testWidgets('the temperature slider reads in degrees, not in percent', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await openSheet(tester);

        expect(valueUnder(tester, 'drying.temp_slider'), '45°');
        handle.dispose();
      });

      testWidgets('the duration slider reads in hours', (tester) async {
        final handle = tester.ensureSemantics();
        await openSheet(tester);

        expect(valueUnder(tester, 'drying.hours_slider'), '12 godz');
        handle.dispose();
      });

      /// The chips say which option is current by their fill alone, so the flag
      /// is the only thing a reader has to go on.
      testWidgets('the chosen start mode is announced as selected', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await openSheet(tester);

        expect(
          node(tester, 'drying.start_mode.now').flagsCollection.isSelected,
          Tristate.isTrue,
        );
        expect(
          node(tester, 'drying.start_mode.delay').flagsCollection.isSelected,
          Tristate.isFalse,
        );

        await tester.tap(find.text('Później'));
        await tester.pumpAndSettle();

        expect(
          node(tester, 'drying.start_mode.now').flagsCollection.isSelected,
          Tristate.isFalse,
        );
        expect(
          node(tester, 'drying.start_mode.delay').flagsCollection.isSelected,
          Tristate.isTrue,
        );
        handle.dispose();
      });

      /// The flag rides on the node that takes the tap, so the identifier the
      /// log resolves a press against has to still be on it.
      testWidgets(
        'a chip that announces its state is still named for the log',
        (tester) async {
          final handle = tester.ensureSemantics();
          await openSheet(tester);

          final chip = node(tester, 'drying.start_mode.now');

          expect(chip.identifier, 'drying.start_mode.now');
          expect(
            chip.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          handle.dispose();
        },
      );
    });

    testWidgets('Now still starts the dryer rather than scheduling it', (
      tester,
    ) async {
      final repo = _StubScheduledDrying();
      final commands = _RecordingCommands();

      await tester.pumpWidget(
        _cardWithProviders(
          dryable(),
          extra: [
            scheduledDryingRepositoryProvider.overrideWithValue(repo),
            printerCommandsRepositoryProvider.overrideWithValue(commands),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await openDetails(tester);
      await tester.tap(find.text('Suszenie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(repo.created, isEmpty);
      expect(commands.calls, contains('startDrying:3:1:45:12:PLA'));
    });
  });
}
