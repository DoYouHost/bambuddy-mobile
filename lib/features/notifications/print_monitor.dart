import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart' show Locale;

import '../../core/models/printer_status.dart';
import '../../core/notifications/hms_catalog.dart';
import '../../core/notifications/notification_prefs.dart';
import '../../core/notifications/notification_service.dart';
import '../../l10n/app_localizations.dart';

/// Alert ID base per event type; add `printer_id` so alerts from different printers
/// (and types) don't overwrite each other. ID 1 is reserved for ongoing.
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

/// Progress milestone thresholds (%).
const List<int> _milestones = [25, 50, 75];

/// Grace period before declaring printer offline — `connected` can flicker
/// (similar to OFFLINE card collapse in printer_card.dart).
const Duration _offlineGrace = Duration(seconds: 15);

/// Timer factory — injectable so tests can control time instead of waiting 15s.
typedef TimerFactory = Timer Function(Duration, void Function());

/// Monitor state for one printer — tracks event edges between frames.
class _PrinterMemo {
  bool printing = false;
  bool firstLayerSent = false;
  final Set<int> milestonesSent = {};
  bool? connected;
  bool offlineNotified = false;
  Timer? offlineTimer;
  final Set<String> knownHmsCodes = {};
  final Set<int> lowFilamentTrays = {}; // Latched tray IDs below threshold
  final Set<int> humidUnits = {}; // Latched AMS unit IDs above threshold
  bool awaitingBedCool = false;

  /// Reset print-specific state on starting a new print.
  void resetForNewPrint() {
    firstLayerSent = false;
    milestonesSent.clear();
    awaitingBedCool = false;
  }
}

/// Throttling key for ongoing notification: update only when printer, total %,
/// ETA minute, or active print count changes — else every WS frame would redraw it.
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

/// Notification brain: observes latest printer statuses and controls
/// [NotificationService] — ongoing notification during printing and event alerts
/// (start/finish/error/offline/plate/humidity/…). Which events fire is decided by
/// [NotificationPrefs]. Pure logic ([update]) is testable with fake service; no
/// plugin/`BuildContext` dependencies.
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

  /// Callback invoked after print ends (success/error) — hooks up overdue
  /// maintenance reminder ([MaintenanceMonitor.remindOnPrintEnd]).
  final void Function(int printerId)? _onPrintEnded;

  /// Optional HMS code description resolver (Bambu catalog). null → fallback to
  /// "level · module (code)" format.
  final String? Function(HmsError)? _hmsDescribe;

  final Map<int, _PrinterMemo> _memo = {};
  _OngoingKey? _lastOngoing;

  bool _on(NotifEvent e) => _prefs.isOn(e);

  /// Called on each status map change (from `printerStatusesProvider`).
  void update(Map<int, PrinterStatus> statuses) {
    for (final entry in statuses.entries) {
      // First frame of each printer is only primed, no alerts from it —
      // else fresh monitor (background isolate restarts on every background entry)
      // would treat current state as just-happened edges and fire "first layer/25%/HMS error"
      // for events that happened long ago.
      final isNew = !_memo.containsKey(entry.key);
      final memo = _memo.putIfAbsent(entry.key, _PrinterMemo.new);
      if (isNew) {
        _prime(memo, entry.value);
      } else {
        _processPrinter(entry.key, entry.value, memo);
      }
    }
    // Printers gone from map — drop their timers and state.
    final gone = _memo.keys.where((id) => !statuses.containsKey(id)).toList();
    for (final id in gone) {
      _memo.remove(id)?.offlineTimer?.cancel();
    }

    _updateOngoing(statuses);
  }

  /// "Plate not empty" event from separate WS frame `plate_not_empty` (camera
  /// detected objects on bed at print start → bambuddy held the print).
  /// Only correct source for this alert — see comment at step 5) in [_processPrinter].
  /// Printer name from frame (status may not be known), with fallback to list title.
  void onPlateNotEmpty(int printerId, String? printerName) {
    if (!_on(NotifEvent.plateNotEmpty)) return;
    _alertPlate(printerId, printerName);
  }

  /// Baseline state from first observed frame — record "what's already here" so
  /// later frames detect only TRUE edges. Intentionally fire nothing: print in
  /// progress, first layer complete, existing HMS error, or low filament are not
  /// events that just happened from our perspective. `awaitingBedCool` stays false
  /// (cold bed at startup doesn't mean print just finished).
  void _prime(_PrinterMemo memo, PrinterStatus status) {
    memo.printing = status.isPrinting;
    // "First layer DONE" = printer is already on layer ≥ 2 (parity with bambuddy:
    // `on_first_layer_complete` fires at layer_num ≥ 2). If we prime after completion,
    // just record it — no alert.
    if ((status.layerNum ?? 0) >= 2) memo.firstLayerSent = true;
    if (status.progress != null) {
      final pct = status.progress!.round();
      for (final m in _milestones) {
        if (pct >= m) memo.milestonesSent.add(m);
      }
    }
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

    // 1) Print start (edge not-printing → printing).
    if (!wasPrinting && isPrinting) {
      memo.resetForNewPrint();
      if (_on(NotifEvent.printStarted)) _alertStarted(id, status);
    }

    // 2) Print end (edge printing → not-printing): success / error.
    if (wasPrinting && !isPrinting) {
      switch (status.state?.toUpperCase()) {
        case 'FINISH':
        case 'FINISHED':
          memo.awaitingBedCool = true;
          if (_on(NotifEvent.printFinished)) _alertFinished(id, status);
          // Maintenance reminder independent of print finish prefs.
          _onPrintEnded?.call(id);
        case 'FAILED':
          memo.awaitingBedCool = true;
          if (_on(NotifEvent.printFailed)) _alertFailed(id, status);
          _onPrintEnded?.call(id);
        // Other/unknown final state → no false alert.
      }
    }
    memo.printing = isPrinting;

    // 3) First layer DONE (once per print). Bambuddy announces completion only
    // when printer enters layer 2 (layer_num ≥ 2). Firing at layer_num ≥ 1 was
    // premature — that's only START of first layer.
    if (isPrinting &&
        !memo.firstLayerSent &&
        (status.layerNum ?? 0) >= 2 &&
        _on(NotifEvent.firstLayer)) {
      memo.firstLayerSent = true;
      _alertFirstLayer(id, status);
    }

    // 4) Progress milestones (once per print).
    if (isPrinting && status.progress != null && _on(NotifEvent.milestones)) {
      final pct = status.progress!.round();
      for (final m in _milestones) {
        if (pct >= m && !memo.milestonesSent.contains(m)) {
          memo.milestonesSent.add(m);
          _alertMilestone(id, status, m);
        }
      }
    }

    // 5) "Plate not empty" is NOT detected from status here — field
    // `awaiting_plate_clear` is a queue gate that bambuddy raises at EVERY print end,
    // so it would fire alongside "print finished". True event comes on separate WS
    // frame `plate_not_empty` → [onPlateNotEmpty].

    // 6) Offline with grace period (connected true → false).
    _processOffline(id, status, memo);

    // 7) HMS errors (new code = alert; dedup by known code set).
    _processHms(id, status, memo);

    // 8) Low filament (hysteresis per tray).
    _processLowFilament(id, status, memo);

    // 9) High AMS humidity (hysteresis per unit).
    _processHumidity(id, status, memo);

    // 10) Bed cooled (only after print ends).
    _processBedCooled(id, status, memo);
  }

  void _processOffline(int id, PrinterStatus status, _PrinterMemo memo) {
    final connected = status.connected;
    if (connected == null) return; // Partial frame — no info
    if (connected) {
      memo.offlineTimer?.cancel();
      memo.offlineTimer = null;
      memo.offlineNotified = false;
    } else if (memo.connected != false && !memo.offlineNotified) {
      // Just disconnected — fire alert after grace period if still quiet.
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
    if (errors == null) return; // Field missing in frame — no change
    final current = {
      for (final e in errors)
        if (e.code != null) e.code!,
    };
    final fresh = current.difference(memo.knownHmsCodes);
    memo.knownHmsCodes
      ..clear()
      ..addAll(current);
    if (fresh.isEmpty || !_on(NotifEvent.printerError)) return;
    // Alert on EACH new error worth showing (parity with bambuddy — skip
    // internal/untranslatable entries). Printer may report multiple codes at once;
    // each has own notification ID so they don't overwrite. Dedup by `knownHmsCodes`
    // above guarantees one alert per code.
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

  /// Ongoing notification for currently printing (one, for earliest ETA).
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

    final lead = printing.first; // Finishes earliest
    final percent = (lead.progress ?? 0).round().clamp(0, 100);
    final key = _OngoingKey(lead.id, percent, lead.remainingTime, printing.length);
    if (key == _lastOngoing) return; // Nothing material changed
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

  void _alertPlate(int id, String? printerName) {
    final l = _l10n();
    final name =
        (printerName?.trim().isNotEmpty ?? false) ? printerName!.trim() : null;
    _notifications.showAlert(
      id: _plateAlertBase + id,
      title: l.notifPlateTitle,
      body: l.notifPlateBody(name ?? l.printersTitle),
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

  /// HMS error alert ID — unique per (printer, code) so concurrent errors on same
  /// printer don't overwrite (same code re-hits same notification). Separate high
  /// band — doesn't collide with bases 1k–13k.
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

  /// Print label (filename) with fallback to printer name.
  String _jobLabel(PrinterStatus s, AppLocalizations l) =>
      _jobName(s) ?? s.name ?? l.printersTitle;

  /// Printer label (name) with fallback to list title.
  String _printerLabel(PrinterStatus s, AppLocalizations l) =>
      (s.name?.trim().isNotEmpty ?? false) ? s.name! : l.printersTitle;

  String? _jobName(PrinterStatus s) {
    for (final candidate in [s.currentPrint, s.gcodeFile]) {
      final v = candidate?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  /// Maps filament trays (AMS + external spools) to remaining amount (%).
  /// Skip `remain == -1` (unknown — no RFID tag) and empty trays.
  /// Key is global tray number (AMS: unit*4 + slot; spool: ID 254/255).
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

  /// ETA as concrete finish time (e.g. "21:20"), not "in X".
  /// If print finishes different day, add date "dd.MM 21:20".
  /// Manual format (24h) — no intl init, works outside widget tree.
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

/// System locale narrowed to supported ones (en/pl) — `lookupAppLocalizations`
/// throws on unsupported language, and monitor (and background isolate) runs outside
/// widget tree, so no `BuildContext` for normal `AppLocalizations.of`.
AppLocalizations systemAppLocalizations() => lookupAppLocalizations(systemLocale());

/// System locale narrowed to supported ones (en/pl) — also used by HMS catalog.
Locale systemLocale() {
  final lang = PlatformDispatcher.instance.locale.languageCode;
  return lang == 'pl' ? const Locale('pl') : const Locale('en');
}
