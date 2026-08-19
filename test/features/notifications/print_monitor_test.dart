import 'dart:async';
import 'dart:convert';

import 'package:bambuddy_mobile/core/diagnostics/diagnostic_recorder.dart';
import 'package:bambuddy_mobile/core/diagnostics/notif_probe.dart';
import 'package:bambuddy_mobile/core/diagnostics/session_facts.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/notifications/notification_prefs.dart';
import 'package:bambuddy_mobile/core/notifications/notification_service.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/features/notifications/print_monitor.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Nagrywa wywołania zamiast dotykać pluginu — sprawdzamy same przejścia.
class _FakeNotifications implements NotificationService {
  int ongoingCount = 0;
  int clearCount = 0;
  String? lastTitle;
  String? lastBody;
  int? lastProgress;
  final List<Map<String, Object?>> alerts = [];

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> showOngoing({
    required String title,
    required String body,
    required int progress,
  }) async {
    ongoingCount++;
    lastTitle = title;
    lastBody = body;
    lastProgress = progress;
  }

  @override
  Future<void> clearOngoing() async => clearCount++;

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
  }) async {
    alerts.add({
      'event': event,
      'printerId': printerId,
      'id': id,
      'title': title,
      'body': body,
      'payload': payload,
      'actions': actions,
    });
  }

  @override
  Future<bool> isAlertActive(int id) async => true;
}

PrinterStatus _status({
  int id = 1,
  String? state,
  double? progress,
  int? remaining,
  String? job,
  String? name,
  bool? connected,
  int? layerNum,
  bool? awaitingPlateClear,
  List<HmsError>? hms,
  List<AmsUnit>? ams,
  List<AmsTray>? vtTray,
  Map<String, double>? temps,
}) =>
    PrinterStatus(
      id: id,
      name: name,
      state: state,
      progress: progress,
      remainingTime: remaining,
      currentPrint: job,
      connected: connected,
      layerNum: layerNum,
      awaitingPlateClear: awaitingPlateClear,
      hmsErrors: hms,
      ams: ams,
      vtTray: vtTray,
      temperatures: temps,
    );

/// Slot AMS z pozostałą ilością i typem (niepusty), do testów niskiego filamentu.
AmsTray _tray({int id = 0, int? remain, String type = 'PLA'}) =>
    AmsTray(id: id, remain: remain, trayType: type, trayColor: 'FFFFFFFF');

/// Timer, którym steruje test — [fire] symuluje upływ łaski offline.
class _FakeTimer implements Timer {
  _FakeTimer(this._callback);
  final void Function() _callback;
  bool _cancelled = false;

  @override
  void cancel() => _cancelled = true;

  @override
  bool get isActive => !_cancelled;

  @override
  int get tick => 0;

  void fire() {
    if (!_cancelled) _callback();
  }
}

/// Wszystkie zdarzenia włączone — do testów pojedynczych detekcji.
const _allOn = NotificationPrefs(enabled: {
  NotifEvent.printStarted,
  NotifEvent.printFinished,
  NotifEvent.printFailed,
  NotifEvent.firstLayer,
  NotifEvent.milestones,
  NotifEvent.plateNotEmpty,
  NotifEvent.printerOffline,
  NotifEvent.printerError,
  NotifEvent.lowFilament,
  NotifEvent.amsHumidity,
  NotifEvent.bedCooled,
});

void main() {
  // lookupAppLocalizations w monitorze wymaga zainicjowanego bindingu.
  TestWidgetsFlutterBinding.ensureInitialized();

  // Stały zegar → deterministyczna godzina ETA w asercjach.
  PrintMonitor monitor(_FakeNotifications fake) => PrintMonitor(
        fake,
        l10n: () => lookupAppLocalizations(const Locale('en')),
        clock: () => DateTime(2026, 6, 12, 20, 0),
      );

  test('wejście w druk pokazuje wiszące powiadomienie raz; powtórka throttluje',
      () {
    final fake = _FakeNotifications();
    final m = monitor(fake);

    final frame = {
      1: _status(state: 'RUNNING', progress: 42, remaining: 80, job: 'cube.3mf'),
    };
    m.update(frame);
    expect(fake.ongoingCount, 1);
    expect(fake.lastTitle, 'cube.3mf');
    expect(fake.lastProgress, 42);
    // 20:00 + 80 min → godzina zakończenia 21:20 (nie „za X").
    expect(fake.lastBody, contains('ETA 21:20'));

    // Ta sama ramka (bez zmiany %/ETA) → bez dodatkowej aktualizacji.
    m.update(Map.of(frame));
    expect(fake.ongoingCount, 1);
  });

  test('zmiana postępu aktualizuje powiadomienie', () {
    final fake = _FakeNotifications();
    final m = monitor(fake);
    m.update({1: _status(state: 'RUNNING', progress: 42, remaining: 80)});
    m.update({1: _status(state: 'RUNNING', progress: 43, remaining: 79)});
    expect(fake.ongoingCount, 2);
    expect(fake.lastProgress, 43);
  });

  test('RUNNING → FINISH: jeden alert „skończone" i sprzątnięcie', () {
    final fake = _FakeNotifications();
    final m = monitor(fake);
    m.update({1: _status(state: 'RUNNING', progress: 99, remaining: 1, job: 'x')});
    m.update({1: _status(state: 'FINISH', progress: 100, remaining: 0, job: 'x')});

    expect(fake.alerts.length, 1);
    expect(fake.alerts.single['title'], 'Print finished');
    expect(fake.alerts.single['body'], 'x is done');
    expect(fake.clearCount, greaterThanOrEqualTo(1));

    // Kolejne ramki FINISH nie odpalają alertu ponownie.
    m.update({1: _status(state: 'FINISH', progress: 100, remaining: 0, job: 'x')});
    expect(fake.alerts.length, 1);
  });

  test('RUNNING → FAILED: alert „nieudane"', () {
    final fake = _FakeNotifications();
    final m = monitor(fake);
    m.update({1: _status(state: 'RUNNING', progress: 30, remaining: 50, job: 'y')});
    m.update({1: _status(state: 'FAILED', progress: 30, remaining: 0, job: 'y')});
    expect(fake.alerts.single['title'], 'Print failed');
    expect(fake.alerts.single['body'], 'y failed');
  });

  test('dwie drukarki: wiszące dla najbliższego ETA, z dopiskiem +1', () {
    final fake = _FakeNotifications();
    final m = monitor(fake);
    m.update({
      1: _status(id: 1, state: 'RUNNING', progress: 10, remaining: 200, job: 'long'),
      2: _status(id: 2, state: 'RUNNING', progress: 80, remaining: 15, job: 'soon'),
    });
    expect(fake.lastTitle, 'soon'); // kończy się najwcześniej
    expect(fake.lastProgress, 80);
    expect(fake.lastBody, contains('+1'));
  });

  test('koniec wszystkich wydruków sprząta wiszące powiadomienie', () {
    final fake = _FakeNotifications();
    final m = monitor(fake);
    m.update({1: _status(state: 'RUNNING', progress: 50, remaining: 30)});
    expect(fake.clearCount, 0);
    m.update({1: _status(state: 'IDLE', progress: 0, remaining: 0)});
    expect(fake.clearCount, 1);
  });

  // --- Nowe zdarzenia (wszystkie włączone) ---

  PrintMonitor monitorAll(
    _FakeNotifications fake, {
    TimerFactory? timer,
    DateTime Function()? clock,
    String? Function(HmsError)? hmsDescribe,
  }) =>
      PrintMonitor(
        fake,
        prefs: _allOn,
        l10n: () => lookupAppLocalizations(const Locale('en')),
        clock: clock ?? () => DateTime(2026, 6, 12, 20, 0),
        timerFactory: timer,
        hmsDescribe: hmsDescribe,
      );

  // HMS notifications now require a known description (parity with bambuddy) —
  // treat every code as documented unless a test says otherwise.
  String? describeAll(HmsError e) => 'desc';

  // Alerty jednego typu dzielą id per drukarka; pasmo liczymy tak jak produkcja,
  // żeby test nie przypinał się do jego szerokości.
  int bandId(int band, [int printerId = 1]) =>
      band * alertBandWidth + printerId;

  // Ostatni alert o danym id (alerty tego samego typu współdzielą id per drukarka
  // — na urządzeniu nowy zastępuje stary; tu fake zapisuje wszystkie).
  Map<String, Object?>? alertById(_FakeNotifications fake, int id) {
    Map<String, Object?>? found;
    for (final a in fake.alerts) {
      if (a['id'] == id) found = a;
    }
    return found;
  }

  // Alerty błędów HMS: id jest teraz unikalne per (drukarka, kod), więc szukamy
  // ich po tytule, nie po stałym id. Każdy ma własne id, więc kilka równoczesnych
  // błędów daje kilka osobnych powiadomień (różne id).
  final errorTitle = lookupAppLocalizations(const Locale('en')).notifErrorTitle;
  List<Map<String, Object?>> errorAlerts(_FakeNotifications fake) =>
      [for (final a in fake.alerts) if (a['title'] == errorTitle) a];

  test('start wydruku odpala alert „rozpoczęto" (gdy włączony)', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake);
    m.update({1: _status(state: 'IDLE')});
    expect(alertById(fake, bandId(3)), isNull);
    m.update({1: _status(state: 'RUNNING', job: 'cube.3mf')});
    expect(alertById(fake, bandId(3))?['title'], 'Print started');
  });

  test('pierwsza warstwa GOTOWA: alert raz, dopiero gdy layer_num osiąga 2', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake);
    m.update({1: _status(state: 'RUNNING', job: 'x', layerNum: 0)});
    expect(alertById(fake, bandId(4)), isNull);
    // Warstwa 1 dopiero ROZPOCZĘTA — jeszcze nie ukończona, brak alertu.
    m.update({1: _status(state: 'RUNNING', job: 'x', layerNum: 1)});
    expect(alertById(fake, bandId(4)), isNull);
    // Warstwa 2 → warstwa 1 ukończona (parytet z bambuddy layer_num ≥ 2).
    m.update({1: _status(state: 'RUNNING', job: 'x', layerNum: 2)});
    expect(alertById(fake, bandId(4)), isNotNull);
    fake.alerts.clear();
    m.update({1: _status(state: 'RUNNING', job: 'x', layerNum: 3)});
    expect(alertById(fake, bandId(4)), isNull); // bez powtórki
  });

  test('kamienie milowe: 25/50/75 raz każdy', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake);
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 10)});
    expect(fake.alerts.where((a) => a['id'] == 5001), isEmpty);
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 30)});
    expect(alertById(fake, bandId(5))?['title'], '25% printed');
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 55)});
    expect(alertById(fake, bandId(5))?['title'], '50% printed');
    fake.alerts.clear();
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 60)});
    expect(fake.alerts, isEmpty); // nic nowego nie przekroczono
  });

  test('kamienie milowe: procent z fazy przygotowania nie odpala progów', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake);
    // Kalibracja raportuje własny procent przy layer_num == 0 — obserwowany skok
    // 6 → 60 w 300 ms przekraczał 25 i 50 przed pierwszą warstwą.
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 6, layerNum: 0)});
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 60, layerNum: 0)});
    expect(fake.alerts.where((a) => a['id'] == 5001), isEmpty);
    // Wydruk rusza naprawdę: procent liczy się od zera i progi działają normalnie.
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 5, layerNum: 1)});
    expect(fake.alerts.where((a) => a['id'] == 5001), isEmpty);
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 30, layerNum: 8)});
    expect(alertById(fake, bandId(5))?['title'], '25% printed');
  });

  test('kamienie milowe: primowanie na ramce kalibracyjnej nie zjada progów', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake);
    // Pierwsza ramka to kalibracja przy 60% — gdyby posłużyła za bazę, zatrzasnęłaby
    // 25 i 50 jako wysłane i wyciszyła je na cały prawdziwy wydruk.
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 60, layerNum: 0)});
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 30, layerNum: 8)});
    expect(alertById(fake, bandId(5))?['title'], '25% printed');
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 55, layerNum: 15)});
    expect(alertById(fake, bandId(5))?['title'], '50% printed');
  });

  test('kamienie milowe: primowanie w trakcie druku nadal zatrzaskuje progi', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake);
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 60, layerNum: 40)});
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 62, layerNum: 41)});
    expect(fake.alerts.where((a) => a['id'] == 5001), isEmpty);
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 80, layerNum: 55)});
    expect(alertById(fake, bandId(5))?['title'], '75% printed');
  });

  test('płyta niepusta: alert z ramki WS plate_not_empty, nie ze statusu', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake);
    // Koniec druku podnosi awaiting_plate_clear w statusie — to NIE może
    // odpalić alertu (to bramka kolejki, nie detekcja obiektów na stole).
    m.update({1: _status(state: 'RUNNING', job: 'x')});
    m.update({1: _status(state: 'FINISH', awaitingPlateClear: true)});
    expect(alertById(fake, bandId(6)), isNull);
    // Dopiero osobna ramka WS odpala alert (z nazwą drukarki z ramki).
    m.onPlateNotEmpty(1, 'X1C');
    final alert = alertById(fake, bandId(6));
    expect(alert, isNotNull);
    expect(alert!['body'], contains('X1C'));
  });

  test('płyta niepusta: respektuje wyłączone zdarzenie w prefs', () {
    final fake = _FakeNotifications();
    final m = monitor(fake); // domyślne prefs: plateNotEmpty wł., ale…
    final off = PrintMonitor(
      fake,
      prefs: const NotificationPrefs(enabled: {}),
      l10n: () => lookupAppLocalizations(const Locale('en')),
      clock: () => DateTime(2026, 6, 12, 20, 0),
    );
    off.onPlateNotEmpty(1, 'X1C');
    expect(alertById(fake, bandId(6)), isNull);
    // sanity: domyślny monitor (plate wł.) odpala
    m.onPlateNotEmpty(1, 'X1C');
    expect(alertById(fake, bandId(6)), isNotNull);
  });

  test('offline: alert dopiero po upływie łaski; powrót online ją kasuje', () {
    final fake = _FakeNotifications();
    final timers = <_FakeTimer>[];
    final m = monitorAll(fake, timer: (d, cb) {
      final t = _FakeTimer(cb);
      timers.add(t);
      return t;
    });

    m.update({1: _status(state: 'IDLE', connected: true)});
    m.update({1: _status(state: 'IDLE', connected: false)});
    expect(alertById(fake, bandId(7)), isNull); // jeszcze nie — czeka na grace
    expect(timers, hasLength(1));
    timers.single.fire();
    expect(alertById(fake, bandId(7))?['title'], 'Printer offline');

    // Drugi epizod: offline, ale powrót online przed upływem łaski → brak alertu.
    final fake2 = _FakeNotifications();
    final timers2 = <_FakeTimer>[];
    final m2 = monitorAll(fake2, timer: (d, cb) {
      final t = _FakeTimer(cb);
      timers2.add(t);
      return t;
    });
    m2.update({1: _status(state: 'IDLE', connected: true)});
    m2.update({1: _status(state: 'IDLE', connected: false)});
    m2.update({1: _status(state: 'IDLE', connected: true)});
    timers2.single.fire(); // anulowany — bez efektu
    expect(alertById(fake2, 7001), isNull);
  });

  test('błąd HMS: nowy kod alarmuje, powtórka nie; po łasce pojawia się ponownie',
      () {
    final fake = _FakeNotifications();
    var t = DateTime(2026, 6, 12, 20, 0);
    final m = monitorAll(fake, clock: () => t, hmsDescribe: describeAll);
    const err = HmsError(code: 'A', severity: 2);
    m.update({1: _status(state: 'RUNNING')}); // priming — bez błędów
    m.update({1: _status(state: 'RUNNING', hms: [err])});
    expect(errorAlerts(fake), hasLength(1));
    fake.alerts.clear();
    m.update({1: _status(state: 'RUNNING', hms: [err])});
    expect(errorAlerts(fake), isEmpty); // ten sam kod
    // Krótka przerwa (< łaska) i powrót → wciąż ten sam błąd, bez ponownego alertu.
    m.update({1: _status(state: 'RUNNING', hms: const [])});
    t = t.add(const Duration(seconds: 5));
    m.update({1: _status(state: 'RUNNING', hms: [err])});
    expect(errorAlerts(fake), isEmpty);
    // Dłuższa nieobecność (> łaska) → kod zapomniany, nowe wystąpienie alarmuje.
    // Ramki lecą przez ten czas normalnie — cisza w całym kanale to inna
    // sytuacja i ma własny test niżej.
    for (var i = 0; i < 4; i++) {
      t = t.add(const Duration(seconds: 10));
      m.update({1: _status(state: 'RUNNING', hms: const [])});
    }
    m.update({1: _status(state: 'RUNNING', hms: [err])});
    expect(errorAlerts(fake), hasLength(1));
  });

  test('błąd HMS: cisza w kanale nie kasuje pamięci — rekonekt nie alarmuje '
      'ponownie', () {
    final fake = _FakeNotifications();
    var t = DateTime(2026, 6, 12, 20, 0);
    final m = monitorAll(fake, clock: () => t, hmsDescribe: describeAll);
    const err = HmsError(code: 'A', severity: 2);

    m.update({1: _status(state: 'RUNNING')}); // priming
    m.update({1: _status(state: 'RUNNING', hms: [err])});
    expect(errorAlerts(fake), hasLength(1));
    fake.alerts.clear();

    // Socket pada i przez dwie minuty nie przychodzi nic. Watchdog gniazda jest
    // dłuższy niż łaska, więc każde wykryte zerwanie wygląda dokładnie tak — a
    // usterka stoi nadal, bo pierwsza ramka po powrocie wciąż ją niesie.
    t = t.add(const Duration(minutes: 2));
    m.update({1: _status(state: 'RUNNING', hms: [err])});

    expect(errorAlerts(fake), isEmpty);
  });

  test('błąd HMS: drukarka offline nie alarmuje; kod znany sprzed rozłączenia '
      'nie alarmuje po powrocie, świeży kod tak', () {
    final fake = _FakeNotifications();
    var t = DateTime(2026, 6, 12, 20, 0);
    final m = monitorAll(fake, clock: () => t, hmsDescribe: describeAll);
    const err = HmsError(code: 'A', severity: 2);
    const other = HmsError(code: 'B', severity: 3);
    // Online z błędem A → jeden alert (edge). Potem zapamiętany.
    m.update({1: _status(state: 'IDLE', connected: true)}); // priming
    m.update({1: _status(state: 'IDLE', connected: true, hms: [err])});
    expect(errorAlerts(fake), hasLength(1));
    fake.alerts.clear();
    // Offline: mergedWith niesie stary hms_errors dalej — brak alertu mimo że
    // kod „zniknął i wrócił", i mimo upływu łaski (pamięć jest zamrożona).
    m.update({1: _status(state: 'IDLE', connected: false, hms: const [])});
    t = t.add(const Duration(seconds: 60));
    m.update({1: _status(state: 'IDLE', connected: false, hms: [err])});
    expect(errorAlerts(fake), isEmpty);
    // Powrót online: ten sam kod A sprzed rozłączenia NIE alarmuje ponownie…
    m.update({1: _status(state: 'IDLE', connected: true, hms: [err])});
    expect(errorAlerts(fake), isEmpty);
    // …ale genuinie nowy kod B po powrocie już tak.
    m.update({1: _status(state: 'IDLE', connected: true, hms: [err, other])});
    expect(errorAlerts(fake), hasLength(1));
  });

  test('błąd HMS zauważony dopiero po rozłączeniu alarmuje po powrocie', () {
    final fake = _FakeNotifications();
    var t = DateTime(2026, 6, 12, 20, 0);
    final m = monitorAll(fake, clock: () => t, hmsDescribe: describeAll);
    const err = HmsError(code: 'A', severity: 2);

    m.update({1: _status(state: 'RUNNING', connected: true)}); // priming
    // Usterka pojawia się w tej samej ramce, w której drukarka znika — nikt jej
    // jeszcze nie zgłosił, więc zapamiętanie jej wyciszyłoby ją na zawsze.
    m.update({1: _status(state: 'RUNNING', connected: false, hms: [err])});
    expect(errorAlerts(fake), isEmpty);

    // Druga drukarka sypie ramkami: każda z nich przemiela też stan pierwszej,
    // więc łaska nigdy by nie upłynęła, gdyby kod został zatrzaśnięty.
    for (var i = 0; i < 3; i++) {
      t = t.add(const Duration(seconds: 45));
      m.update({1: _status(state: 'RUNNING', connected: false, hms: [err])});
    }
    expect(errorAlerts(fake), isEmpty);

    // Drukarka wraca wciąż z tą usterką — teraz użytkownik musi się dowiedzieć.
    t = t.add(const Duration(seconds: 45));
    m.update({1: _status(state: 'RUNNING', connected: true, hms: [err])});

    expect(errorAlerts(fake), hasLength(1));
  });

  test('an HMS alert carries the fault it is about, and its buttons', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake, hmsDescribe: describeAll);
    const err = HmsError(
      code: '0x8004',
      attr: 0x03008004,
      severity: 3,
      fullCode: '03008004',
      jobId: '746795586',
      actions: ['RESUME_PRINTING', 'STOP_PRINTING'],
    );
    m.update({1: _status(state: 'RUNNING')}); // priming
    m.update({1: _status(state: 'RUNNING', hms: [err])});

    final alert = errorAlerts(fake).single;
    // The payload is what the background handler rebuilds the command from.
    expect(alert['payload'], 'hms:1:03008004:746795586');
    final actions = alert['actions']! as List<NotificationAction>;
    expect(actions.map((a) => a.id),
        ['hms:RESUME_PRINTING', 'hms:STOP_PRINTING']);
    // Resuming runs on the tap; stopping a print opens the app to ask first.
    expect(actions.map((a) => a.opensApp), [false, true]);
  });

  test('an HMS alert lands on the same id in every isolate', () {
    // Pinned to literals on purpose: this isolate restarts on every trip to the
    // background, and an id derived from a per-run seed handed the same standing
    // fault a second notification each time instead of replacing the first. A
    // seeded id would not survive the constants below twice.
    final fake = _FakeNotifications();
    final m = monitorAll(fake, hmsDescribe: describeAll);
    const err = HmsError(code: '0x8004', severity: 3, fullCode: '03008004');
    const other = HmsError(code: 'A', severity: 2);

    m.update({1: _status(state: 'RUNNING')}); // priming
    m.update({
      1: _status(state: 'RUNNING', hms: [err, other]),
    });

    expect(errorAlerts(fake).map((a) => a['id']), [8544723, 8921897]);
  });

  test('an HMS alert offers no buttons the app could not send', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake, hmsDescribe: describeAll);
    // No full_code (server pre-0.2.4.8): nothing identifies the fault to the
    // firmware, so the alert stays a plain message.
    const legacy = HmsError(code: 'A', severity: 2, actions: ['RESUME_PRINTING']);
    // A code whose only offer is handled by the printer's own screen.
    const screenOnly = HmsError(
      code: '0x8011',
      attr: 0x03008011,
      severity: 3,
      fullCode: '03008011',
      actions: ['CHECK_ASSISTANT'],
    );
    m.update({1: _status(state: 'RUNNING')}); // priming
    m.update({1: _status(state: 'RUNNING', hms: [legacy, screenOnly])});

    final alerts = errorAlerts(fake);
    expect(alerts, hasLength(2));
    expect(alerts.map((a) => a['actions']), everyElement(isNull));
    expect(alerts.first['payload'], 'printer:1');
  });

  test('an alert never grows more buttons than Android draws', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake, hmsDescribe: describeAll);
    const err = HmsError(
      code: '0x801a',
      attr: 0x0300801A,
      severity: 3,
      fullCode: '0300801A',
      actions: [
        'RESUME_PRINTING',
        'IGNORE_RESUME',
        'NO_REMINDER_NEXT_TIME',
        'STOP_PRINTING',
      ],
    );
    m.update({1: _status(state: 'RUNNING')}); // priming
    m.update({1: _status(state: 'RUNNING', hms: [err])});

    final actions =
        errorAlerts(fake).single['actions']! as List<NotificationAction>;
    expect(actions, hasLength(3));
  });

  test('błąd HMS: kilka nowych kodów w jednej ramce → osobne alerty (różne id)',
      () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake, hmsDescribe: describeAll);
    const a = HmsError(code: 'A', severity: 2);
    const b = HmsError(code: 'B', severity: 3);
    m.update({1: _status(state: 'RUNNING')}); // priming
    m.update({1: _status(state: 'RUNNING', hms: [a, b])});
    final alerts = errorAlerts(fake);
    expect(alerts, hasLength(2)); // oba kody, żaden się nie zgubił
    expect(alerts.map((e) => e['id']).toSet(), hasLength(2)); // różne id
  });

  test('błąd HMS: kod bez znanego opisu jest pomijany (parytet z bambuddy)', () {
    final fake = _FakeNotifications();
    // Brak resolvera opisu → kod nieudokumentowany; tak samo X2D szum sev 6.
    final m = monitorAll(fake);
    m.update({1: _status(state: 'RUNNING')});
    m.update({
      1: _status(state: 'RUNNING', hms: [
        const HmsError(code: 'A', severity: 2), // udokumentowany severity, brak opisu
        const HmsError(code: '0x20070', attr: 83887616, module: 5, severity: 6),
      ]),
    });
    expect(errorAlerts(fake), isEmpty); // nic bez opisu nie alarmuje
  });

  test('błąd HMS: opis serwerowy wystarcza nawet bez katalogu', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake); // bez resolvera katalogu
    m.update({1: _status(state: 'RUNNING')});
    m.update({
      1: _status(state: 'RUNNING', hms: [
        const HmsError(code: 'A', severity: 2, message: 'Filament runout'),
      ]),
    });
    expect(errorAlerts(fake), hasLength(1));
  });

  test('błąd HMS: echo anulowania (0500_400E) nie alarmuje', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake, hmsDescribe: describeAll);
    m.update({1: _status(state: 'RUNNING')});
    // ecode = attr(0x05000000) + code(0x400E) → short 0500_400E.
    m.update({
      1: _status(state: 'RUNNING', hms: [
        const HmsError(code: '0x400E', attr: 0x05000000, module: 5, severity: 2),
      ]),
    });
    expect(errorAlerts(fake), isEmpty);
  });

  test('niski filament: histereza per slot', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake);
    final unitFull = [AmsUnit(id: 0, trays: [_tray(remain: 50)])];
    final unitLow = [AmsUnit(id: 0, trays: [_tray(remain: 5)])];
    m.update({1: _status(state: 'RUNNING', ams: unitFull)});
    expect(alertById(fake, bandId(9)), isNull);
    m.update({1: _status(state: 'RUNNING', ams: unitLow)});
    expect(alertById(fake, bandId(9)), isNotNull);
    fake.alerts.clear();
    m.update({1: _status(state: 'RUNNING', ams: unitLow)});
    expect(alertById(fake, bandId(9)), isNull); // nadal nisko — bez spamu
    m.update({1: _status(state: 'RUNNING', ams: unitFull)}); // reset
    m.update({1: _status(state: 'RUNNING', ams: unitLow)});
    expect(alertById(fake, bandId(9)), isNotNull); // ponownie spadło
  });

  test('wysoka wilgotność AMS: zbocze powyżej progu', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake);
    m.update({1: _status(state: 'IDLE', ams: [const AmsUnit(id: 0, humidity: 40)])});
    expect(alertById(fake, bandId(10)), isNull);
    m.update({1: _status(state: 'IDLE', ams: [const AmsUnit(id: 0, humidity: 70)])});
    expect(alertById(fake, bandId(10)), isNotNull);
  });

  test('stół wystygł: tylko po zakończonym wydruku i poniżej progu', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake);
    // Stół zimny bez wcześniejszego druku → bez alertu.
    m.update({1: _status(state: 'IDLE', temps: {'bed': 25})});
    expect(alertById(fake, bandId(11)), isNull);
    // Wydruk i jego koniec uzbrajają oczekiwanie na wystygnięcie.
    m.update({1: _status(state: 'RUNNING', job: 'x', temps: {'bed': 60})});
    m.update({1: _status(state: 'FINISH', job: 'x', temps: {'bed': 60})});
    expect(alertById(fake, bandId(11)), isNull); // jeszcze gorący
    m.update({1: _status(state: 'FINISH', job: 'x', temps: {'bed': 30})});
    expect(alertById(fake, bandId(11))?['title'], 'Bed cooled');
  });

  test('priming: pierwsza ramka w toku NIE odpala zaszłych zdarzeń', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake);
    // Świeży monitor (jak po restarcie isolate'u tła) dostaje drukarkę już w
    // 38% druku, po pierwszej warstwie, z istniejącym błędem HMS i niskim
    // filamentem — żadne z tych zdarzeń nie powinno wystrzelić.
    m.update({
      1: _status(
        state: 'RUNNING',
        progress: 38,
        layerNum: 20,
        hms: [const HmsError(code: '0x20070')],
        ams: [
          AmsUnit(id: 0, humidity: 80, trays: [_tray(remain: 3)]),
        ],
      ),
    });
    expect(fake.alerts, isEmpty); // tylko wiszący postęp, zero alertów
    expect(fake.ongoingCount, 1);

    // Ale prawdziwe zbocze po primingu już działa: 50% przekroczone.
    m.update({1: _status(state: 'RUNNING', progress: 55, layerNum: 30)});
    expect(alertById(fake, bandId(5))?['title'], '50% printed');
  });

  test('gating: domyślne prefs nie puszczają „rozpoczęto" ani milestones', () {
    final fake = _FakeNotifications();
    final m = monitor(fake); // domyślne prefs
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 30)});
    expect(alertById(fake, bandId(3)), isNull); // started OFF
    expect(alertById(fake, bandId(5)), isNull); // milestones OFF
  });

  // --- Tor diagnostyczny (src:notif) ---

  group('diagnostyka', () {
    late DiagnosticRecorder recorder;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      recorder = DiagnosticRecorder(
        settings: SettingsRepository(await SharedPreferences.getInstance()),
        loadFacts: () async =>
            const SessionFacts(app: '0.11.3+1103', flavor: 'mobile'),
        // Pamięć zamiast dysku: sprawdzamy rekordy, nie lustro na pliku.
        resolveDirectory: () async => null,
      );
    });

    // Zeruje statyk `DiagnosticRecorder.active` między testami.
    tearDown(() => recorder.discard());

    /// Uruchamia nagrywanie, wykonuje [body] i zwraca surowy JSONL sesji.
    Future<String> raw(FutureOr<void> Function() body) async {
      await recorder.start();
      await body();
      return recorder.stop();
    }

    /// Same rekordy toru powiadomień, w kolejności zapisu.
    Future<List<Map<String, Object?>>> rows(
      FutureOr<void> Function() body,
    ) async {
      final jsonl = await raw(body);
      return [
        for (final line in const LineSplitter().convert(jsonl))
          if (jsonDecode(line) case final Map<String, Object?> row
              when row['src'] == 'notif')
            row,
      ];
    }

    List<Map<String, Object?>> only(
      List<Map<String, Object?>> all,
      String evt,
    ) =>
        [for (final r in all) if (r['evt'] == evt) r];

    /// Monitor piszący do logu: dekorator na atrapie serwisu.
    PrintMonitor logged(
      _FakeNotifications fake, {
      NotificationPrefs prefs = _allOn,
      TimerFactory? timer,
      String? Function(HmsError)? hmsDescribe,
      void Function(int)? onPrintEnded,
    }) =>
        PrintMonitor(
          LoggingNotifications(fake),
          prefs: prefs,
          l10n: () => lookupAppLocalizations(const Locale('en')),
          clock: () => DateTime(2026, 6, 12, 20, 0),
          timerFactory: timer,
          hmsDescribe: hmsDescribe,
          onPrintEnded: onPrintEnded,
        );

    const firstLayerOff = NotificationPrefs(enabled: {NotifEvent.printStarted});

    test('wyłączona pierwsza warstwa: jeden rekord, nie jeden na ramkę', () async {
      // Gate `_on` był liczony co ramkę, więc rekord w środku warunku dałby
      // jeden wpis na każdą ramkę do końca druku.
      final fake = _FakeNotifications();
      final m = logged(fake, prefs: firstLayerOff);
      final all = await rows(() {
        m.update({1: _status(state: 'RUNNING', progress: 5)}); // priming
        for (var i = 0; i < 20; i++) {
          m.update({1: _status(state: 'RUNNING', progress: 10, layerNum: 3)});
        }
      });

      final skips = [
        for (final r in only(all, 'suppressed'))
          if (r['event'] == 'firstLayer') r,
      ];
      expect(skips, hasLength(1));
      expect(skips.single['reason'], 'typeOff');
      expect(skips.single['printer_id'], 1);
    });

    test('wyłączone milestones: po jednym rekordzie na próg', () async {
      final fake = _FakeNotifications();
      final m = logged(fake, prefs: firstLayerOff);
      final all = await rows(() {
        m.update({1: _status(state: 'RUNNING', progress: 5)}); // priming
        for (final pct in [30.0, 55.0, 80.0, 80.0, 80.0]) {
          m.update({1: _status(state: 'RUNNING', progress: pct)});
        }
      });

      final skips = [
        for (final r in only(all, 'suppressed'))
          if (r['event'] == 'milestones') r,
      ];
      expect([for (final r in skips) r['pct']], [25, 50, 75]);
    });

    test('faza przygotowania: jeden rekord na wydruk, nie jeden na ramkę', () async {
      final fake = _FakeNotifications();
      final m = logged(fake, prefs: firstLayerOff);
      final all = await rows(() {
        m.update({1: _status(state: 'IDLE')}); // priming
        for (final pct in [6.0, 60.0, 66.0, 66.0]) {
          m.update({1: _status(state: 'RUNNING', progress: pct, layerNum: 0)});
        }
      });

      final skips = [
        for (final r in only(all, 'suppressed'))
          if (r['reason'] == 'prepPhase') r,
      ];
      expect(skips, hasLength(1));
      expect(skips.single['event'], 'milestones');
      expect(skips.single['pct'], 6);
    });

    test('nowy wydruk uzbraja zatrzaski ponownie', () async {
      final fake = _FakeNotifications();
      final m = logged(fake, prefs: firstLayerOff);
      final all = await rows(() {
        m.update({1: _status(state: 'RUNNING', progress: 5)}); // priming
        m.update({1: _status(state: 'RUNNING', progress: 10, layerNum: 3)});
        m.update({1: _status(state: 'FINISH', progress: 100)});
        m.update({1: _status(state: 'RUNNING', progress: 1)});
        m.update({1: _status(state: 'RUNNING', progress: 10, layerNum: 3)});
      });

      final skips = [
        for (final r in only(all, 'suppressed'))
          if (r['event'] == 'firstLayer') r,
      ];
      expect(skips, hasLength(2));
    });

    test('nazwa pliku ani drukarki nie trafia do logu', () async {
      final fake = _FakeNotifications();
      final m = logged(fake, hmsDescribe: describeAll);
      final jsonl = await raw(() {
        m.update({
          1: _status(
            state: 'IDLE',
            name: 'Kitchen X1C',
            connected: true,
          ),
        });
        m.update({
          1: _status(
            state: 'RUNNING',
            job: 'secret-model.3mf',
            name: 'Kitchen X1C',
            progress: 30,
            layerNum: 3,
            connected: true,
            hms: [const HmsError(code: '0300_400C', severity: 2)],
          ),
        });
        m.update({
          1: _status(
            state: 'FINISH',
            job: 'secret-model.3mf',
            name: 'Kitchen X1C',
            progress: 100,
            connected: true,
          ),
        });
      });

      // Asercja na surowym tekście, nie na sparsowanych polach: nowe zagnieżdżone
      // pole nie może przemknąć obok testu.
      expect(jsonl, isNot(contains('secret-model')));
      expect(jsonl, isNot(contains('Kitchen')));
      expect(only(await rows(() {}), 'posted'), isEmpty); // sanity
    });

    test('wystawiony alert niesie typ, drukarkę i nasze id', () async {
      final fake = _FakeNotifications();
      final m = logged(fake);
      final all = await rows(() {
        m.update({1: _status(state: 'IDLE')});
        m.update({1: _status(state: 'RUNNING', job: 'x', progress: 1)});
      });

      final posted = only(all, 'posted').single;
      expect(posted['event'], 'printStarted');
      expect(posted['printer_id'], 1);
      expect(posted['nid'], bandId(3));
      expect(posted.containsKey('title'), isFalse);
      expect(posted.containsKey('body'), isFalse);
    });

    test('alert HMS niesie drukarkę, choć jego id jest hashem', () async {
      final fake = _FakeNotifications();
      final m = logged(fake, hmsDescribe: describeAll);
      final all = await rows(() {
        m.update({7: _status(id: 7, connected: true)});
        m.update({
          7: _status(
            id: 7,
            connected: true,
            hms: [const HmsError(code: '0300_400C', severity: 2)],
          ),
        });
      });

      final posted = only(all, 'posted').single;
      expect(posted['event'], 'printerError');
      expect(posted['printer_id'], 7);
    });

    test('odrzucenie przez platformę daje klasę wyjątku, nie komunikat',
        () async {
      // Dekorator sprawdzany wprost: wyjątek jest **przepuszczany dalej**, żeby
      // nie zniknął z izolatu, więc przez monitor (który nie czeka na future)
      // wyszedłby jako nieobsłużony błąd i wywrócił test.
      final decorated = LoggingNotifications(_ThrowingNotifications());
      final all = await rows(() async {
        await expectLater(
          decorated.showAlert(
            event: NotifEvent.printFinished,
            printerId: 4,
            id: 1004,
            title: 'secret-model.3mf',
            body: 'secret-model.3mf is done',
          ),
          throwsStateError,
        );
      });

      final error = only(all, 'post_error').single;
      expect(error['event'], 'printFinished');
      expect(error['printer_id'], 4);
      expect(error['cause'], 'StateError');
      expect(error['lvl'], 'error');
      // Komunikat wyjątku platformy nie jest pod naszą kontrolą, a jedyne
      // stringi w zasięgu tej metody to tytuł i treść.
      expect(error.containsKey('msg'), isFalse);
      expect(jsonEncode(error), isNot(contains('secret-model')));
    });

    test('notyfikacja postępu: rekord na zmianę treści, nie na ramkę', () async {
      final fake = _FakeNotifications();
      final m = logged(fake);
      final all = await rows(() {
        m.update({1: _status(state: 'RUNNING', progress: 40, remaining: 30)});
        m.update({1: _status(state: 'RUNNING', progress: 40, remaining: 30)});
        m.update({1: _status(state: 'RUNNING', progress: 41, remaining: 29)});
        m.update({1: _status(state: 'IDLE', progress: 0, remaining: 0)});
      });

      final ongoing = only(all, 'ongoing');
      expect(ongoing, hasLength(2));
      expect(ongoing.first['pct'], 40);
      expect(ongoing.first['eta_min'], 30);
      expect(ongoing.first['active'], 1);
      expect(only(all, 'ongoing_reset'), hasLength(1));
    });

    test('koniec druku w nieznanym stanie: rekord ostrzegawczy bez alertu',
        () async {
      final fake = _FakeNotifications();
      final ended = <int>[];
      final m = logged(fake, onPrintEnded: ended.add);
      final all = await rows(() {
        m.update({1: _status(state: 'RUNNING', progress: 50)});
        m.update({1: _status(state: 'IDLE', progress: 50)});
      });

      final end = only(all, 'print_end').single;
      expect(end['state'], 'IDLE');
      expect(end['lvl'], 'warn');
      expect(only(all, 'posted'), isEmpty);
      // Ta sama gałąź zjada przypomnienie o konserwacji — o tym mówi rekord.
      expect(ended, isEmpty);
    });

    test('koniec druku w FINISH: rekord informacyjny obok alertu', () async {
      final fake = _FakeNotifications();
      final ended = <int>[];
      final m = logged(fake, onPrintEnded: ended.add);
      final all = await rows(() {
        m.update({1: _status(state: 'RUNNING', progress: 50)});
        m.update({1: _status(state: 'FINISH', progress: 100)});
      });

      final end = only(all, 'print_end').single;
      expect(end['state'], 'FINISH');
      expect(end.containsKey('lvl'), isFalse); // info nie jest wypisywane
      expect(ended, [1]);
    });

    test('primowanie zapisuje bazę, z której nic nie wynika', () async {
      final fake = _FakeNotifications();
      final m = logged(fake);
      final all = await rows(() {
        m.update({
          1: _status(state: 'RUNNING', progress: 43, layerNum: 57, job: 'x'),
        });
      });

      final primed = only(all, 'primed').single;
      expect(primed['printer_id'], 1);
      expect(primed['layer'], 57);
      expect(primed['progress'], 43);
      expect(primed['printing'], true);
      // Pierwsza ramka nie odpala niczego — to jest cała treść tego rekordu.
      expect(only(all, 'posted'), isEmpty);
      expect(only(all, 'suppressed'), isEmpty);
    });

    test('HMS: powody są rozdzielone, a znany kod milczy', () async {
      final fake = _FakeNotifications();
      // Bez opisu w katalogu i z severity 1 → kod niedokumentowany.
      final m = logged(fake, hmsDescribe: (_) => null);
      final all = await rows(() {
        m.update({1: _status(connected: true)});
        for (var i = 0; i < 5; i++) {
          m.update({
            1: _status(
              connected: true,
              hms: [const HmsError(code: '0500_400E', severity: 1)],
            ),
          });
        }
      });

      final skips = only(all, 'suppressed');
      expect(skips, hasLength(1));
      expect(skips.single['reason'], 'undocumented');
      expect(skips.single['sev'], 1);
    });

    test('HMS przy rozłączonej drukarce: powód offline, nie typeOff', () async {
      final fake = _FakeNotifications();
      final m = logged(fake, hmsDescribe: describeAll);
      final all = await rows(() {
        m.update({1: _status(connected: true)});
        m.update({
          1: _status(
            connected: false,
            hms: [const HmsError(code: '0300_400C', severity: 2)],
          ),
        });
      });

      final skips = [
        for (final r in only(all, 'suppressed'))
          if (r['event'] == 'printerError') r,
      ];
      expect(skips.single['reason'], 'offline');
    });

    test('powrót drukarki przed upływem łaski zostawia ślad', () async {
      final fake = _FakeNotifications();
      final timers = <_FakeTimer>[];
      final m = logged(fake, timer: (d, cb) {
        final t = _FakeTimer(cb);
        timers.add(t);
        return t;
      });
      final all = await rows(() {
        m.update({1: _status(connected: true)});
        m.update({1: _status(connected: false)});
        m.update({1: _status(connected: true)}); // wraca przed strzałem
        m.update({1: _status(connected: true)}); // bez timera → bez rekordu
      });

      final skips = only(all, 'suppressed');
      expect(skips, hasLength(1));
      expect(skips.single['reason'], 'reconnected');
      expect(timers.single.isActive, isFalse);
    });

    test('migawka preferencji wymienia wyłączone typy i stan systemu', () async {
      final all = await rows(() async {
        await NotifProbe.openSession(
          const NotificationPrefs(
            enabled: {NotifEvent.printFinished},
            alertsEnabled: false,
          ),
          permission: () async => false,
          channelImportance: () async => 0,
        );
      });

      final prefs = only(all, 'prefs').single;
      expect(prefs['alerts'], false);
      expect(prefs['perm'], false);
      expect(prefs['chan_imp'], 0);
      expect(prefs['off'], isNot(contains('printFinished')));
      expect(prefs['off'], contains('milestones'));
    });

    test('nieodpowiadająca platforma nie psuje migawki', () async {
      final all = await rows(() async {
        await NotifProbe.openSession(
          NotificationPrefs.defaults,
          permission: () async => throw StateError('no channel'),
          channelImportance: () async => null,
        );
      });

      final prefs = only(all, 'prefs').single;
      // Brak pola znaczy „nie odpowiedziano", nie „zabronione".
      expect(prefs.containsKey('perm'), isFalse);
      expect(prefs.containsKey('chan_imp'), isFalse);
    });
  });
}

/// Atrapa, w której platforma odrzuca każdy alert.
class _ThrowingNotifications extends _FakeNotifications {
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
  }) async =>
      throw StateError('plugin not initialised');
}
