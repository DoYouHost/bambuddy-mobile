import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart' show Locale;

import '../../core/models/printer_status.dart';
import '../../core/notifications/hms_catalog.dart';
import '../../core/notifications/notification_prefs.dart';
import '../../core/notifications/notification_service.dart';
import '../../l10n/app_localizations.dart';

/// Bazy id alertów per typ zdarzenia; do każdej dodajemy `printer_id`, by alerty
/// różnych drukarek (i różnych typów) się nie nadpisywały. Id ongoing = 1 jest
/// zarezerwowane.
const int _finishedAlertBase = 1000;
const int _failedAlertBase = 2000;
const int _startedAlertBase = 3000;
const int _firstLayerAlertBase = 4000;
const int _milestoneAlertBase = 5000;
const int _plateAlertBase = 6000;
const int _offlineAlertBase = 7000;
const int _errorAlertBase = 8000;
const int _lowFilamentAlertBase = 9000;
const int _humidityAlertBase = 10000;
const int _bedCooledAlertBase = 11000;

/// Progi „kamieni milowych" postępu (%).
const List<int> _milestones = [25, 50, 75];

/// Ile czekać, zanim ogłosimy drukarkę offline — `connected` potrafi mrugnąć
/// (analogicznie do kolapsu karty OFFLINE w printer_card.dart).
const Duration _offlineGrace = Duration(seconds: 15);

/// Fabryka timera — wstrzykiwalna, by testy mogły sterować upływem czasu zamiast
/// czekać 15 s realnego zegara.
typedef TimerFactory = Timer Function(Duration, void Function());

/// Pamięć monitora dla jednej drukarki — śledzi zbocza zdarzeń między ramkami.
class _PrinterMemo {
  bool printing = false;
  bool firstLayerSent = false;
  final Set<int> milestonesSent = {};
  bool? connected;
  bool offlineNotified = false;
  Timer? offlineTimer;
  final Set<String> knownHmsCodes = {};
  final Set<int> lowFilamentTrays = {}; // zatrzaśnięte id slotów poniżej progu
  final Set<int> humidUnits = {}; // zatrzaśnięte id jednostek AMS powyżej progu
  bool awaitingBedCool = false;
  bool plateAwaiting = false; // ostatni awaiting_plate_clear

  /// Reset stanu związanego z pojedynczym wydrukiem (na starcie nowego).
  void resetForNewPrint() {
    firstLayerSent = false;
    milestonesSent.clear();
    awaitingBedCool = false;
  }
}

/// Klucz throttlingu wiszącego powiadomienia: aktualizujemy je tylko, gdy
/// zmieni się drukarka, całkowity %, minuta ETA albo liczba aktywnych wydruków
/// — inaczej każda ramka WS przerysowywałaby notyfikację bez potrzeby.
class _OngoingKey {
  const _OngoingKey(this.printerId, this.percent, this.etaMinutes, this.count);
  final int printerId;
  final int percent;
  final int? etaMinutes;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is _OngoingKey &&
      other.printerId == printerId &&
      other.percent == percent &&
      other.etaMinutes == etaMinutes &&
      other.count == count;

  @override
  int get hashCode => Object.hash(printerId, percent, etaMinutes, count);
}

/// Mózg powiadomień: obserwuje najnowsze statusy drukarek i steruje
/// [NotificationService] — wiszące powiadomienie podczas wydruku oraz alerty
/// zdarzeń (start/koniec/błąd/offline/płyta/wilgotność/…). Które zdarzenia
/// faktycznie puszczamy, decyduje [NotificationPrefs]. Czysta logika ([update])
/// jest testowalna z fake serwisem; brak zależności od pluginu/`BuildContext`.
class PrintMonitor {
  PrintMonitor(
    this._notifications, {
    this._prefs = NotificationPrefs.defaults,
    AppLocalizations Function()? l10n,
    DateTime Function()? clock,
    TimerFactory? timerFactory,
    String? Function(HmsError)? hmsDescribe,
    this._onPrintEnded,
  })  : _l10n = l10n ?? systemAppLocalizations,
        _now = clock ?? DateTime.now,
        _timer = timerFactory ?? Timer.new,
        // ignore: prefer_initializing_formals — pole prywatne z nazwanym paramem
        _hmsDescribe = hmsDescribe;

  final NotificationService _notifications;
  final NotificationPrefs _prefs;
  final AppLocalizations Function() _l10n;
  final DateTime Function() _now;
  final TimerFactory _timer;

  /// Callback wołany po zakończeniu wydruku (sukces/błąd) — wpina przypomnienie
  /// o przeterminowanej konserwacji ([MaintenanceMonitor.remindOnPrintEnd]).
  final void Function(int printerId)? _onPrintEnded;

  /// Opcjonalny resolver opisu kodu HMS (katalog Bambu). null → fallback do
  /// formatu „poziom · moduł (kod)".
  final String? Function(HmsError)? _hmsDescribe;

  final Map<int, _PrinterMemo> _memo = {};
  _OngoingKey? _lastOngoing;

  bool _on(NotifEvent e) => _prefs.isOn(e);

  /// Wywoływane na każdą zmianę mapy statusów (z `printerStatusesProvider`).
  void update(Map<int, PrinterStatus> statuses) {
    for (final entry in statuses.entries) {
      // Pierwszą ramkę danej drukarki tylko ZAPAMIĘTUJEMY (priming), nie
      // alarmujemy z niej — inaczej świeży monitor (isolate tła startuje na nowo
      // przy każdym wejściu w tło) potraktowałby bieżący stan jak właśnie
      // zaszłe zbocza i wystrzelił „pierwsza warstwa/25%/błąd HMS" dla rzeczy,
      // które minęły dawno temu.
      final isNew = !_memo.containsKey(entry.key);
      final memo = _memo.putIfAbsent(entry.key, _PrinterMemo.new);
      if (isNew) {
        _prime(memo, entry.value);
      } else {
        _processPrinter(entry.key, entry.value, memo);
      }
    }
    // Drukarki, które zniknęły z mapy — porzucamy ich timery i pamięć.
    final gone = _memo.keys.where((id) => !statuses.containsKey(id)).toList();
    for (final id in gone) {
      _memo.remove(id)?.offlineTimer?.cancel();
    }

    _updateOngoing(statuses);
  }

  /// Stan bazowy z pierwszej obserwowanej ramki — zapisujemy „co już jest", by
  /// kolejne ramki wykrywały tylko PRAWDZIWE zbocza. Świadomie NIE odpalamy
  /// niczego: wydruk w toku, gotowa pierwsza warstwa, istniejący błąd HMS czy
  /// niski filament to nie są zdarzenia, które właśnie zaszły z naszej
  /// perspektywy. `awaitingBedCool` zostaje false (stół zimny na starcie nie
  /// oznacza świeżo zakończonego druku).
  void _prime(_PrinterMemo memo, PrinterStatus status) {
    memo.printing = status.isPrinting;
    if ((status.layerNum ?? 0) >= 1) memo.firstLayerSent = true;
    if (status.progress != null) {
      final pct = status.progress!.round();
      for (final m in _milestones) {
        if (pct >= m) memo.milestonesSent.add(m);
      }
    }
    memo.plateAwaiting = status.awaitingPlateClear ?? false;
    if (status.connected != null) memo.connected = status.connected;
    final errors = status.hmsErrors;
    if (errors != null) {
      memo.knownHmsCodes.addAll({
        for (final e in errors)
          if (e.code != null) e.code!,
      });
    }
    _trayRemains(status).forEach((key, remain) {
      if (remain < _prefs.lowFilamentThreshold) memo.lowFilamentTrays.add(key);
    });
    final units = status.ams;
    if (units != null) {
      for (var i = 0; i < units.length; i++) {
        final humidity = units[i].humidity;
        if (humidity != null && humidity > _prefs.amsHumidityThreshold) {
          memo.humidUnits.add(units[i].id ?? i);
        }
      }
    }
  }

  void _processPrinter(int id, PrinterStatus status, _PrinterMemo memo) {
    final wasPrinting = memo.printing;
    final isPrinting = status.isPrinting;

    // 1) Start wydruku (zbocze nie-druk → druk).
    if (!wasPrinting && isPrinting) {
      memo.resetForNewPrint();
      if (_on(NotifEvent.printStarted)) _alertStarted(id, status);
    }

    // 2) Koniec wydruku (zbocze druk → nie-druk): sukces / błąd.
    if (wasPrinting && !isPrinting) {
      switch (status.state?.toUpperCase()) {
        case 'FINISH':
        case 'FINISHED':
          memo.awaitingBedCool = true;
          if (_on(NotifEvent.printFinished)) _alertFinished(id, status);
          // Przypomnienie o konserwacji NIEZALEŻNE od prefs zakończenia wydruku.
          _onPrintEnded?.call(id);
        case 'FAILED':
          memo.awaitingBedCool = true;
          if (_on(NotifEvent.printFailed)) _alertFailed(id, status);
          _onPrintEnded?.call(id);
        // Inny/nieznany stan końcowy → bez fałszywego alertu.
      }
    }
    memo.printing = isPrinting;

    // 3) Pierwsza warstwa (raz na wydruk).
    if (isPrinting &&
        !memo.firstLayerSent &&
        (status.layerNum ?? 0) >= 1 &&
        _on(NotifEvent.firstLayer)) {
      memo.firstLayerSent = true;
      _alertFirstLayer(id, status);
    }

    // 4) Kamienie milowe postępu (każdy raz na wydruk).
    if (isPrinting && status.progress != null && _on(NotifEvent.milestones)) {
      final pct = status.progress!.round();
      for (final m in _milestones) {
        if (pct >= m && !memo.milestonesSent.contains(m)) {
          memo.milestonesSent.add(m);
          _alertMilestone(id, status, m);
        }
      }
    }

    // 5) Płyta niepusta (zbocze false/null → true).
    final awaiting = status.awaitingPlateClear ?? false;
    if (awaiting && !memo.plateAwaiting && _on(NotifEvent.plateNotEmpty)) {
      _alertPlate(id, status);
    }
    memo.plateAwaiting = awaiting;

    // 6) Offline z opóźnieniem (connected true → false).
    _processOffline(id, status, memo);

    // 7) Błędy HMS (nowy kod = alert; dedup po zbiorze znanych kodów).
    _processHms(id, status, memo);

    // 8) Niski filament (histereza per slot).
    _processLowFilament(id, status, memo);

    // 9) Wysoka wilgotność AMS (histereza per jednostka).
    _processHumidity(id, status, memo);

    // 10) Stół wystygł (tylko po zakończonym wydruku).
    _processBedCooled(id, status, memo);
  }

  void _processOffline(int id, PrinterStatus status, _PrinterMemo memo) {
    final connected = status.connected;
    if (connected == null) return; // częściowa ramka — brak informacji
    if (connected) {
      memo.offlineTimer?.cancel();
      memo.offlineTimer = null;
      memo.offlineNotified = false;
    } else if (memo.connected != false && !memo.offlineNotified) {
      // Dopiero co zniknęła — odpalamy alert po okresie łaski, jeśli nadal cisza.
      memo.offlineTimer?.cancel();
      memo.offlineTimer = _timer(_offlineGrace, () {
        memo.offlineTimer = null;
        memo.offlineNotified = true;
        if (_on(NotifEvent.printerOffline)) _alertOffline(id, status);
      });
    }
    memo.connected = connected;
  }

  void _processHms(int id, PrinterStatus status, _PrinterMemo memo) {
    final errors = status.hmsErrors;
    if (errors == null) return; // brak pola w ramce — bez zmian
    final current = {
      for (final e in errors)
        if (e.code != null) e.code!,
    };
    final fresh = current.difference(memo.knownHmsCodes);
    memo.knownHmsCodes
      ..clear()
      ..addAll(current);
    if (fresh.isEmpty || !_on(NotifEvent.printerError)) return;
    // Alarmujemy o KAŻDYM nowym błędzie wartym pokazania (parytet z bambuddy —
    // wewnętrzne/nieprzetłumaczalne wpisy pomijamy). Drukarka może zgłosić kilka
    // kodów naraz; każdy ma własne id powiadomienia, więc się nie nadpisują.
    // Dedup po `knownHmsCodes` wyżej gwarantuje jeden alert na kod.
    for (final e in errors) {
      if (e.code != null &&
          fresh.contains(e.code) &&
          hmsIsDisplayable(e, description: _hmsDescribe?.call(e))) {
        _alertError(id, status, e);
      }
    }
  }

  void _processLowFilament(int id, PrinterStatus status, _PrinterMemo memo) {
    final threshold = _prefs.lowFilamentThreshold;
    final remains = _trayRemains(status);
    var triggered = false;
    int? triggeredRemain;
    for (final entry in remains.entries) {
      final remain = entry.value;
      if (remain < threshold) {
        if (memo.lowFilamentTrays.add(entry.key)) {
          triggered = true;
          triggeredRemain = remain;
        }
      } else {
        memo.lowFilamentTrays.remove(entry.key);
      }
    }
    if (triggered && _on(NotifEvent.lowFilament)) {
      _alertLowFilament(id, status, triggeredRemain ?? threshold);
    }
  }

  void _processHumidity(int id, PrinterStatus status, _PrinterMemo memo) {
    final threshold = _prefs.amsHumidityThreshold;
    final units = status.ams;
    if (units == null) return;
    var triggered = false;
    int? value;
    bool? isHt;
    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      final humidity = unit.humidity;
      if (humidity == null) continue;
      final key = unit.id ?? i;
      if (humidity > threshold) {
        if (memo.humidUnits.add(key)) {
          triggered = true;
          value = humidity;
          isHt = unit.isAmsHt;
        }
      } else {
        memo.humidUnits.remove(key);
      }
    }
    if (triggered && _on(NotifEvent.amsHumidity)) {
      _alertHumidity(id, status, value ?? threshold, isHt ?? false);
    }
  }

  void _processBedCooled(int id, PrinterStatus status, _PrinterMemo memo) {
    if (!memo.awaitingBedCool) return;
    final bed = status.temperatures?['bed'];
    if (bed == null) return;
    if (bed < _prefs.bedCooledTemp) {
      memo.awaitingBedCool = false;
      if (_on(NotifEvent.bedCooled)) _alertBedCooled(id, status, bed.round());
    }
  }

  /// Wiszące powiadomienie dla aktualnie drukujących (jedno, dla najbliższego ETA).
  void _updateOngoing(Map<int, PrinterStatus> statuses) {
    final printing = statuses.values.where((s) => s.isPrinting).toList()
      ..sort((a, b) => (a.remainingTime ?? 1 << 30)
          .compareTo(b.remainingTime ?? 1 << 30));

    if (printing.isEmpty) {
      if (_lastOngoing != null) {
        _lastOngoing = null;
        _notifications.clearOngoing();
      }
      return;
    }

    final lead = printing.first; // kończy się najwcześniej
    final percent = (lead.progress ?? 0).round().clamp(0, 100);
    final key = _OngoingKey(lead.id, percent, lead.remainingTime, printing.length);
    if (key == _lastOngoing) return; // nic istotnego się nie zmieniło
    _lastOngoing = key;

    final l = _l10n();
    final title = _jobName(lead) ?? lead.name ?? l.printersTitle;
    final eta = _etaClock(lead.remainingTime);
    var body = eta == null ? '$percent%' : l.notifOngoingBody(percent, eta);
    if (printing.length > 1) {
      body = '$body · ${l.notifMorePrints(printing.length - 1)}';
    }
    _notifications.showOngoing(title: title, body: body, progress: percent);
  }

  void _alertStarted(int id, PrinterStatus status) {
    final l = _l10n();
    _notifications.showAlert(
      id: _startedAlertBase + id,
      title: l.notifStartedTitle,
      body: l.notifStartedBody(_jobLabel(status, l)),
      payload: 'printer:$id',
    );
  }

  void _alertFinished(int id, PrinterStatus status) {
    final l = _l10n();
    _notifications.showAlert(
      id: _finishedAlertBase + id,
      title: l.printFinishedTitle,
      body: l.printFinishedBody(_jobLabel(status, l)),
      payload: 'printer:$id',
    );
  }

  void _alertFailed(int id, PrinterStatus status) {
    final l = _l10n();
    _notifications.showAlert(
      id: _failedAlertBase + id,
      title: l.printFailedTitle,
      body: l.printFailedBody(_jobLabel(status, l)),
      payload: 'printer:$id',
    );
  }

  void _alertFirstLayer(int id, PrinterStatus status) {
    final l = _l10n();
    _notifications.showAlert(
      id: _firstLayerAlertBase + id,
      title: l.notifFirstLayerTitle,
      body: l.notifFirstLayerBody(_jobLabel(status, l)),
      payload: 'printer:$id',
    );
  }

  void _alertMilestone(int id, PrinterStatus status, int percent) {
    final l = _l10n();
    _notifications.showAlert(
      id: _milestoneAlertBase + id,
      title: l.notifMilestoneTitle(percent),
      body: l.notifMilestoneBody(_jobLabel(status, l), percent),
      payload: 'printer:$id',
    );
  }

  void _alertPlate(int id, PrinterStatus status) {
    final l = _l10n();
    _notifications.showAlert(
      id: _plateAlertBase + id,
      title: l.notifPlateTitle,
      body: l.notifPlateBody(_printerLabel(status, l)),
      payload: 'printer:$id',
    );
  }

  void _alertOffline(int id, PrinterStatus status) {
    final l = _l10n();
    _notifications.showAlert(
      id: _offlineAlertBase + id,
      title: l.notifOfflineTitle,
      body: l.notifOfflineBody(_printerLabel(status, l)),
      payload: 'printer:$id',
    );
  }

  void _alertError(int id, PrinterStatus status, HmsError err) {
    final l = _l10n();
    final detail = hmsHumanText(err, description: _hmsDescribe?.call(err), l10n: l);
    _notifications.showAlert(
      id: _errorAlertId(id, err),
      title: l.notifErrorTitle,
      body: l.notifErrorBody(_printerLabel(status, l), detail),
      payload: 'printer:$id',
    );
  }

  /// Id alertu błędu HMS — unikalne per (drukarka, kod), by równoczesne błędy
  /// jednej drukarki się nie nadpisywały (a ten sam kod ponownie trafił w to
  /// samo powiadomienie). Osobne, wysokie pasmo — nie koliduje z bazami 1k–13k.
  int _errorAlertId(int id, HmsError err) {
    final code = err.ecode ?? err.code ?? err.displayCode;
    return _errorAlertBase * 1000 + (Object.hash(id, code) & 0xfffff);
  }

  void _alertLowFilament(int id, PrinterStatus status, int remain) {
    final l = _l10n();
    _notifications.showAlert(
      id: _lowFilamentAlertBase + id,
      title: l.notifLowFilamentTitle,
      body: l.notifLowFilamentBody(_printerLabel(status, l), remain),
      payload: 'printer:$id',
    );
  }

  void _alertHumidity(int id, PrinterStatus status, int humidity, bool isHt) {
    final l = _l10n();
    _notifications.showAlert(
      id: _humidityAlertBase + id,
      title: isHt ? l.notifHumidityHtTitle : l.notifHumidityTitle,
      body: l.notifHumidityBody(_printerLabel(status, l), humidity),
      payload: 'printer:$id',
    );
  }

  void _alertBedCooled(int id, PrinterStatus status, int temp) {
    final l = _l10n();
    _notifications.showAlert(
      id: _bedCooledAlertBase + id,
      title: l.notifBedCooledTitle,
      body: l.notifBedCooledBody(_printerLabel(status, l), temp),
      payload: 'printer:$id',
    );
  }

  /// Etykieta wydruku (nazwa pliku) z fallbackiem na nazwę drukarki.
  String _jobLabel(PrinterStatus s, AppLocalizations l) =>
      _jobName(s) ?? s.name ?? l.printersTitle;

  /// Etykieta drukarki (nazwa) z fallbackiem na tytuł listy.
  String _printerLabel(PrinterStatus s, AppLocalizations l) =>
      (s.name?.trim().isNotEmpty ?? false) ? s.name! : l.printersTitle;

  String? _jobName(PrinterStatus s) {
    for (final candidate in [s.currentPrint, s.gcodeFile]) {
      final v = candidate?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  /// Mapuje sloty filamentu (AMS + szpule zewnętrzne) na ich pozostałą ilość (%).
  /// Pomijamy `remain == -1` (nieznana — brak tagu RFID) i puste sloty.
  /// Klucz to globalny numer slotu (AMS: jednostka*4 + slot; szpula: id 254/255).
  Map<int, int> _trayRemains(PrinterStatus status) {
    final out = <int, int>{};
    final List<AmsUnit> units = status.ams ?? const [];
    for (var u = 0; u < units.length; u++) {
      final int unitId = units[u].id ?? u;
      for (final AmsTray t in units[u].trays ?? const []) {
        final int? remain = t.remain;
        if (remain != null && remain >= 0 && !t.isEmpty) {
          out[unitId * 4 + (t.id ?? 0)] = remain;
        }
      }
    }
    for (final t in status.externalSpools) {
      final remain = t.remain;
      if (remain != null && remain >= 0 && !t.isEmpty) {
        out[t.id ?? 254] = remain;
      }
    }
    return out;
  }

  /// ETA jako konkretna godzina zakończenia (np. „21:20"), nie „za X".
  /// Gdy wydruk skończy się innego dnia, dokładamy datę „dd.MM 21:20".
  /// Format ręczny (24 h) — bez inicjalizacji intl, działa poza drzewem widgetów.
  String? _etaClock(int? minutes) {
    if (minutes == null) return null;
    final now = _now();
    final finish = now.add(Duration(minutes: minutes));
    final hh = finish.hour.toString().padLeft(2, '0');
    final mm = finish.minute.toString().padLeft(2, '0');
    final time = '$hh:$mm';
    final sameDay = finish.year == now.year &&
        finish.month == now.month &&
        finish.day == now.day;
    if (sameDay) return time;
    final dd = finish.day.toString().padLeft(2, '0');
    final mo = finish.month.toString().padLeft(2, '0');
    return '$dd.$mo $time';
  }
}

/// Locale systemu zawężone do wspieranych (en/pl) — `lookupAppLocalizations`
/// rzuca na nieobsługiwanym języku, a monitor (oraz isolate tła) działa poza
/// drzewem widgetów, więc nie ma `BuildContext` do zwykłego `AppLocalizations.of`.
AppLocalizations systemAppLocalizations() => lookupAppLocalizations(systemLocale());

/// Locale systemu zawężone do wspieranych (en/pl) — używane też przez katalog HMS.
Locale systemLocale() {
  final lang = PlatformDispatcher.instance.locale.languageCode;
  return lang == 'pl' ? const Locale('pl') : const Locale('en');
}
