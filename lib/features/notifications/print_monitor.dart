import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart' show Locale;

import '../../core/diagnostics/notif_probe.dart';
import '../../core/models/printer_status.dart';
import '../../core/notifications/background_api.dart';
import '../../core/notifications/hms_actions.dart';
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

/// Buttons an alert may carry. Android's notification shade lays out three and
/// drops whatever follows without a word.
const int _maxAlertActions = 3;

/// Grace period before declaring printer offline — `connected` can flicker
/// (similar to OFFLINE card collapse in printer_card.dart).
const Duration _offlineGrace = Duration(seconds: 15);

/// How long an HMS code is remembered after it last appeared. A code that drops
/// out of `hms_errors` for less than this is treated as the SAME ongoing fault
/// and won't re-alert when it flickers back — some codes (e.g. chamber-temp
/// regulation) toggle on/off every few seconds around a threshold. Parity with
/// bambuddy's `_HMS_CLEAR_GRACE_SECONDS = 30`.
const Duration _hmsClearGrace = Duration(seconds: 30);

/// Short HMS codes (`MMMM_EEEE`) the firmware echoes during normal user-cancel
/// sequences — not faults. bambuddy drops these so they don't surface as alerts
/// or "X problem" badges. Kept here as a safety net (older servers / the
/// print_error path may still forward them).
const Set<String> _hmsUserActionCodes = {
  '0300_400C', // "The task was canceled."
  '0500_400E', // "Printing was cancelled."
};

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

  /// HMS code → last time it was seen in a frame. A code is forgotten once it
  /// has been absent for [_hmsClearGrace], so a genuinely new occurrence can
  /// re-alert while brief flaps/gaps stay silent.
  final Map<String, DateTime> hmsLastSeen = {};
  final Set<int> lowFilamentTrays = {}; // Latched tray IDs below threshold
  final Set<int> humidUnits = {}; // Latched AMS unit IDs above threshold
  bool awaitingBedCool = false;

  /// Whether the prep-phase progress was already recorded as ignored for this
  /// print — calibration reports a percentage on every frame, so without this
  /// the record would repeat for the whole phase instead of once.
  bool prepProgressLogged = false;

  /// Reset print-specific state on starting a new print.
  void resetForNewPrint() {
    firstLayerSent = false;
    milestonesSent.clear();
    awaitingBedCool = false;
    prepProgressLogged = false;
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

  /// Which switch silenced an alert. `isOn` collapses the per-type checkbox and
  /// the master toggle into one boolean, and a record naming the wrong control
  /// would send the user to the wrong screen.
  NotifSkip get _offReason =>
      _prefs.alertsEnabled ? NotifSkip.typeOff : NotifSkip.alertsOff;

  /// The code as the WebSocket lane spells it, so a suppression record and the
  /// frame that carried the fault can be matched on sight.
  static String _hmsCode(HmsError e) => e.code ?? e.displayCode;

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
        _prime(entry.key, memo, entry.value);
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

  /// Cancels all pending per-printer offline-grace timers. Call when this
  /// monitor is being torn down (e.g. `onDestroy` of the background isolate) —
  /// without it, a timer scheduled just before teardown could still fire and
  /// touch a notification service that's no longer valid.
  void dispose() {
    for (final memo in _memo.values) {
      memo.offlineTimer?.cancel();
    }
  }

  /// "Plate not empty" event from separate WS frame `plate_not_empty` (camera
  /// detected objects on bed at print start → bambuddy held the print).
  /// Only correct source for this alert — see comment at step 5) in [_processPrinter].
  /// Printer name from frame (status may not be known), with fallback to list title.
  void onPlateNotEmpty(int printerId, String? printerName) {
    if (!_on(NotifEvent.plateNotEmpty)) {
      NotifProbe.suppressed(_offReason,
          printerId: printerId, event: NotifEvent.plateNotEmpty);
      return;
    }
    _alertPlate(printerId, printerName);
  }

  /// Baseline state from first observed frame — record "what's already here" so
  /// later frames detect only TRUE edges. Intentionally fire nothing: print in
  /// progress, first layer complete, existing HMS error, or low filament are not
  /// events that just happened from our perspective. `awaitingBedCool` stays false
  /// (cold bed at startup doesn't mean print just finished).
  /// [id] is the map key, the same identity every alert is keyed by — not
  /// `status.id`, so a frame filed under a different key can never make the
  /// priming record disagree with the records that follow it.
  void _prime(int id, _PrinterMemo memo, PrinterStatus status) {
    memo.printing = status.isPrinting;
    // "First layer DONE" = printer is already on layer ≥ 2 (parity with bambuddy:
    // `on_first_layer_complete` fires at layer_num ≥ 2). If we prime after completion,
    // just record it — no alert.
    if ((status.layerNum ?? 0) >= 2) memo.firstLayerSent = true;
    // Only a percentage that describes the job is a usable baseline. Priming off
    // a calibration frame ("60%" at layer 0) would latch 25 and 50 as already
    // sent, and then swallow both when the real print reaches them — the mirror
    // image of the burst the gate in step 4) prevents.
    if (status.progress != null && _jobUnderway(status)) {
      final pct = status.progress!.round();
      for (final m in _milestones) {
        if (pct >= m) memo.milestonesSent.add(m);
      }
    }
    if (status.connected != null) memo.connected = status.connected;
    final errors = status.hmsErrors;
    if (errors != null) {
      final now = _now();
      for (final e in errors) {
        final key = _hmsKey(e);
        if (key != null) memo.hmsLastSeen[key] = now;
      }
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
    // What this monitor decided to treat as already-happened. The silence above
    // is correct and completely invisible, and a fresh monitor is built on every
    // entry into the background — so "the app swallowed my notification" is
    // answered by this one record per printer rather than by guesswork.
    NotifProbe.primed(
      id,
      fields: {
        'printing': memo.printing,
        'layer': status.layerNum,
        'progress': status.progress?.round(),
        'hms': memo.hmsLastSeen.length,
        'low_trays': memo.lowFilamentTrays.length,
        'humid': memo.humidUnits.length,
      },
    );
  }

  void _processPrinter(int id, PrinterStatus status, _PrinterMemo memo) {
    final wasPrinting = memo.printing;
    final isPrinting = status.isPrinting;

    // 1) Print start (edge not-printing → printing).
    if (!wasPrinting && isPrinting) {
      memo.resetForNewPrint();
      if (_on(NotifEvent.printStarted)) {
        _alertStarted(id, status);
      } else {
        NotifProbe.suppressed(_offReason,
            printerId: id, event: NotifEvent.printStarted);
      }
    }

    // 2) Print end (edge printing → not-printing): success / error.
    if (wasPrinting && !isPrinting) {
      final state = status.state?.toUpperCase();
      switch (state) {
        case 'FINISH':
        case 'FINISHED':
          memo.awaitingBedCool = true;
          if (_on(NotifEvent.printFinished)) {
            _alertFinished(id, status);
          } else {
            NotifProbe.suppressed(_offReason,
                printerId: id, event: NotifEvent.printFinished);
          }
          // Maintenance reminder independent of print finish prefs.
          _onPrintEnded?.call(id);
        case 'FAILED':
          memo.awaitingBedCool = true;
          if (_on(NotifEvent.printFailed)) {
            _alertFailed(id, status);
          } else {
            NotifProbe.suppressed(_offReason,
                printerId: id, event: NotifEvent.printFailed);
          }
          _onPrintEnded?.call(id);
        // Other/unknown final state → no false alert.
      }
      // Recorded for every end, including the states above that alert. A user
      // cancel lands as neither FINISH nor FAILED, and that branch silently drops
      // the maintenance reminder as well as the alert — so this one line covers
      // "my print ended and nothing happened" whatever the reason, and shows a
      // partial frame faking an end.
      NotifProbe.printEnd(
        id,
        state: state,
        handled: state == 'FINISH' || state == 'FINISHED' || state == 'FAILED',
      );
    }
    memo.printing = isPrinting;

    // 3) First layer DONE (once per print). Bambuddy announces completion only
    // when printer enters layer 2 (layer_num ≥ 2). Firing at layer_num ≥ 1 was
    // premature — that's only START of first layer.
    //
    // The latch is set regardless of the preference, so the decision — an alert
    // or one suppression record — happens once per edge. With the check inside
    // the condition it was retaken on every frame for the rest of the print,
    // which a record would have turned into hundreds of lines. Sound because
    // `_prefs` is immutable for this monitor's whole life (the service is rebuilt
    // from scratch on the next background entry); if live preferences ever land,
    // this silently becomes "enable mid-print, stay quiet until the next one".
    // `_prime` already latches both of these unconditionally.
    if (isPrinting && !memo.firstLayerSent && (status.layerNum ?? 0) >= 2) {
      memo.firstLayerSent = true;
      if (_on(NotifEvent.firstLayer)) {
        _alertFirstLayer(id, status);
      } else {
        NotifProbe.suppressed(_offReason,
            printerId: id, event: NotifEvent.firstLayer);
      }
    }

    // 4) Progress milestones (once per print). Same latch-on-the-edge shape as
    // the first layer above, plus the prep-phase gate — see [_jobUnderway].
    if (isPrinting && status.progress != null) {
      if (!_jobUnderway(status)) {
        _recordPrepProgress(id, status, memo);
      } else {
        final pct = status.progress!.round();
        final on = _on(NotifEvent.milestones);
        for (final m in _milestones) {
          // `add` is false when the threshold was already crossed — the same guard
          // as the old `!contains(m)`, with the latch now on the edge.
          if (pct >= m && memo.milestonesSent.add(m)) {
            if (on) {
              _alertMilestone(id, status, m);
            } else {
              NotifProbe.suppressed(_offReason,
                  printerId: id,
                  event: NotifEvent.milestones,
                  fields: {'pct': m});
            }
          }
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

  /// Whether the reported `progress` describes the JOB rather than the printer's
  /// preparation. During bed levelling / vibration compensation the firmware
  /// reports a percentage of THAT phase: observed jumping 6 → 60 in 300 ms at
  /// `layer_num == 0`, which crossed two milestones at once before a single line
  /// of plastic was down. The job is underway from the first layer on.
  ///
  /// A frame without `layer_num` says nothing about the phase, so it counts as
  /// underway — a server that omits the field keeps the previous behaviour
  /// rather than going silent for the whole print.
  static bool _jobUnderway(PrinterStatus status) => (status.layerNum ?? 1) >= 1;

  /// One record per print for the progress this gate ignored. Prep lasts minutes
  /// and every frame in it carries a percentage, so recording each would bury the
  /// timeline; the first is the one that explains "the app went quiet at 60%".
  void _recordPrepProgress(int id, PrinterStatus status, _PrinterMemo memo) {
    if (memo.prepProgressLogged) return;
    memo.prepProgressLogged = true;
    NotifProbe.suppressed(
      NotifSkip.prepPhase,
      printerId: id,
      event: NotifEvent.milestones,
      fields: {'pct': status.progress?.round(), 'stage': status.stgCurName},
    );
  }

  void _processOffline(int id, PrinterStatus status, _PrinterMemo memo) {
    final connected = status.connected;
    if (connected == null) return; // Partial frame — no info
    if (connected) {
      // Only when a timer was really pending: the alert the grace period was
      // holding back never happened, which answers both "the offline alert came
      // fifteen seconds late" and "it never came at all". Guarded on the timer so
      // this is one record per flap, not one per connected frame.
      if (memo.offlineTimer != null) {
        NotifProbe.suppressed(NotifSkip.reconnected,
            printerId: id, event: NotifEvent.printerOffline);
      }
      memo.offlineTimer?.cancel();
      memo.offlineTimer = null;
      memo.offlineNotified = false;
    } else if (memo.connected != false && !memo.offlineNotified) {
      // Just disconnected — fire alert after grace period if still quiet.
      memo.offlineTimer?.cancel();
      memo.offlineTimer = _timer(_offlineGrace, () {
        memo.offlineTimer = null;
        memo.offlineNotified = true;
        if (_on(NotifEvent.printerOffline)) {
          _alertOffline(id, status);
        } else {
          NotifProbe.suppressed(_offReason,
              printerId: id, event: NotifEvent.printerOffline);
        }
      });
    }
    memo.connected = connected;
  }

  void _processHms(int id, PrinterStatus status, _PrinterMemo memo) {
    final errors = status.hmsErrors;
    if (errors == null) return; // Field missing in frame — no change
    final now = _now();
    // Forget codes absent past the grace window — only those can re-alert. Run
    // before refreshing so codes present this frame (still within grace) survive.
    memo.hmsLastSeen
        .removeWhere((_, seen) => now.difference(seen) >= _hmsClearGrace);

    // An offline printer can't be actively faulting — its `hms_errors` are just
    // the last-known values carried forward by mergedWith. Never alert while
    // disconnected, but still REFRESH last-seen for present codes below: that
    // pauses the clear-grace clock across the outage, so a fault known before
    // the disconnect doesn't spuriously re-alert on reconnect.
    final online = status.connected != false;
    for (final e in errors) {
      final key = _hmsKey(e);
      if (key == null) continue;
      final isNew = !memo.hmsLastSeen.containsKey(key);
      memo.hmsLastSeen[key] = now; // present this frame → refresh last-seen
      // Only ever the first sighting of a code gets this far, so each of the
      // records below is one per code per clear-grace window, not one per frame.
      // A record for the already-known case is deliberately absent: the WebSocket
      // lane carries `hms_codes` on every frame, so a standing code with no
      // notification record next to it *is* the dedup, visible on the same
      // timeline.
      if (!isNew) continue;
      final skip = _hmsSkipReason(e, online: online);
      if (skip != null) {
        NotifProbe.suppressed(
          skip,
          printerId: id,
          event: NotifEvent.printerError,
          fields: {'code': _hmsCode(e), 'sev': e.severity},
        );
        continue;
      }
      _alertError(id, status, e);
    }
  }

  /// Why this HMS code produces no alert, or null when it produces one.
  ///
  /// Four separate answers where the code used to fold them into one boolean.
  /// "Printer disconnected" is not "you turned this off", and neither is "the
  /// firmware sent a code nobody documented" — which is the single largest silent
  /// drop on this path, since one physical fault emits several codes and only one
  /// of them is a real fault.
  NotifSkip? _hmsSkipReason(HmsError e, {required bool online}) {
    if (!online) return NotifSkip.offline;
    if (!_on(NotifEvent.printerError)) return _offReason;
    if (_hmsSuppressed(e)) return NotifSkip.userAction;
    // Notify only on a real, documented fault (parity with bambuddy) — drops
    // the undocumented/phantom codes the firmware emits alongside one event.
    if (!hmsIsNotifiable(e, description: _hmsDescribe?.call(e))) {
      return NotifSkip.undocumented;
    }
    return null;
  }

  /// Stable dedup key for an HMS error: full 16-hex `ecode` when available,
  /// else the raw `code`. null when neither identifies the error.
  String? _hmsKey(HmsError e) {
    final ec = e.ecode;
    if (ec != null) return ec;
    final c = e.code?.trim();
    return (c != null && c.isNotEmpty) ? c : null;
  }

  /// Whether this is a user-action echo (cancel) that must never alert.
  bool _hmsSuppressed(HmsError e) {
    final ec = e.ecode;
    if (ec == null || ec.length != 16) return false;
    final short = '${ec.substring(0, 4)}_${ec.substring(12, 16)}';
    return _hmsUserActionCodes.contains(short);
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
    if (!triggered) return;
    if (_on(NotifEvent.lowFilament)) {
      _alertLowFilament(id, status, triggeredRemain ?? threshold);
    } else {
      NotifProbe.suppressed(_offReason,
          printerId: id, event: NotifEvent.lowFilament);
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
    if (!triggered) return;
    if (_on(NotifEvent.amsHumidity)) {
      _alertHumidity(id, status, value ?? threshold, isHt ?? false);
    } else {
      NotifProbe.suppressed(_offReason,
          printerId: id, event: NotifEvent.amsHumidity);
    }
  }

  void _processBedCooled(int id, PrinterStatus status, _PrinterMemo memo) {
    if (!memo.awaitingBedCool) return;
    final bed = status.temperatures?['bed'];
    if (bed == null) return;
    if (bed < _prefs.bedCooledTemp) {
      memo.awaitingBedCool = false;
      if (_on(NotifEvent.bedCooled)) {
        _alertBedCooled(id, status, bed.round());
      } else {
        NotifProbe.suppressed(_offReason,
            printerId: id, event: NotifEvent.bedCooled);
      }
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
        NotifProbe.ongoingReset();
        _notifications.clearOngoing();
      }
      return;
    }

    final lead = printing.first; // Finishes earliest
    final percent = (lead.progress ?? 0).round().clamp(0, 100);
    final key = _OngoingKey(lead.id, percent, lead.remainingTime, printing.length);
    if (key == _lastOngoing) return; // Nothing material changed
    _lastOngoing = key;
    // Recorded here rather than in the notification decorator: by the time the
    // service sees it, all of this is baked into a title and body made of the
    // user's job name, which never enters a log. The throttle above is what keeps
    // this to one record per real change instead of one per frame.
    NotifProbe.ongoing(
      printerId: lead.id,
      percent: percent,
      etaMin: lead.remainingTime,
      active: printing.length,
    );

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
      event: NotifEvent.printStarted,
      printerId: id,
      id: _startedAlertBase + id,
      title: l.notifStartedTitle,
      body: l.notifStartedBody(_jobLabel(status, l)),
      payload: 'printer:$id',
    );
  }

  void _alertFinished(int id, PrinterStatus status) {
    final l = _l10n();
    _notifications.showAlert(
      event: NotifEvent.printFinished,
      printerId: id,
      id: _finishedAlertBase + id,
      title: l.printFinishedTitle,
      body: l.printFinishedBody(_jobLabel(status, l)),
      payload: 'printer:$id',
    );
  }

  void _alertFailed(int id, PrinterStatus status) {
    final l = _l10n();
    _notifications.showAlert(
      event: NotifEvent.printFailed,
      printerId: id,
      id: _failedAlertBase + id,
      title: l.printFailedTitle,
      body: l.printFailedBody(_jobLabel(status, l)),
      payload: 'printer:$id',
    );
  }

  void _alertFirstLayer(int id, PrinterStatus status) {
    final l = _l10n();
    _notifications.showAlert(
      event: NotifEvent.firstLayer,
      printerId: id,
      id: _firstLayerAlertBase + id,
      title: l.notifFirstLayerTitle,
      body: l.notifFirstLayerBody(_jobLabel(status, l)),
      payload: 'printer:$id',
    );
  }

  void _alertMilestone(int id, PrinterStatus status, int percent) {
    final l = _l10n();
    _notifications.showAlert(
      event: NotifEvent.milestones,
      printerId: id,
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
      event: NotifEvent.plateNotEmpty,
      printerId: id,
      id: _plateAlertBase + id,
      title: l.notifPlateTitle,
      body: l.notifPlateBody(name ?? l.printersTitle),
      payload: 'printer:$id',
    );
  }

  void _alertOffline(int id, PrinterStatus status) {
    final l = _l10n();
    _notifications.showAlert(
      event: NotifEvent.printerOffline,
      printerId: id,
      id: _offlineAlertBase + id,
      title: l.notifOfflineTitle,
      body: l.notifOfflineBody(_printerLabel(status, l)),
      payload: 'printer:$id',
    );
  }

  void _alertError(int id, PrinterStatus status, HmsError err) {
    final l = _l10n();
    final detail = hmsHumanText(err, description: _hmsDescribe?.call(err));
    final fullCode = err.fullCode;
    _notifications.showAlert(
      event: NotifEvent.printerError,
      printerId: id,
      id: _errorAlertId(id, err),
      title: l.notifErrorTitle,
      body: l.notifErrorBody(_printerLabel(status, l), detail),
      payload: fullCode == null
          ? 'printer:$id'
          : hmsPayload(printerId: id, fullCode: fullCode, jobId: err.jobId),
      actions: fullCode == null ? null : _errorActions(err, l),
    );
  }

  /// Remediation buttons for a fault, or null when it offers none the app can
  /// send. Capped at [_maxAlertActions]: Android draws three and silently drops
  /// the rest, and the firmware lists the important ones first.
  List<NotificationAction>? _errorActions(HmsError err, AppLocalizations l) {
    final actions = hmsRenderableActions(err.actions).take(_maxAlertActions);
    if (actions.isEmpty) return null;
    return [
      for (final action in actions)
        NotificationAction(
          id: '$hmsActionIdPrefix$action',
          title: hmsActionLabel(l, action),
          // Stopping a print is confirmed in the app, never on the tap itself.
          opensApp: action == hmsStopAction,
        ),
    ];
  }

  /// HMS error alert ID — unique per (printer, code) so concurrent errors on same
  /// printer don't overwrite (same code re-hits same notification). Separate high
  /// band — doesn't collide with bases 1k–13k.
  int _errorAlertId(int id, HmsError err) {
    final code = err.fullCode ?? err.ecode ?? err.code ?? err.displayCode;
    return _errorAlertBase * 1000 + _stableDigest('$id:$code');
  }

  /// 20-bit FNV-1a digest, spelled out rather than taken from `Object.hash`,
  /// whose seed is drawn afresh on every VM start. This isolate restarts each
  /// time the app is backgrounded, so a seeded id handed the same standing fault
  /// a new notification after every restart instead of replacing the one already
  /// on screen.
  static int _stableDigest(String s) {
    var h = 0x811c9dc5;
    for (var i = 0; i < s.length; i++) {
      h = ((h ^ s.codeUnitAt(i)) * 0x01000193) & 0xffffffff;
    }
    return h & 0xfffff;
  }

  void _alertLowFilament(int id, PrinterStatus status, int remain) {
    final l = _l10n();
    _notifications.showAlert(
      event: NotifEvent.lowFilament,
      printerId: id,
      id: _lowFilamentAlertBase + id,
      title: l.notifLowFilamentTitle,
      body: l.notifLowFilamentBody(_printerLabel(status, l), remain),
      payload: 'printer:$id',
    );
  }

  void _alertHumidity(int id, PrinterStatus status, int humidity, bool isHt) {
    final l = _l10n();
    _notifications.showAlert(
      event: NotifEvent.amsHumidity,
      printerId: id,
      id: _humidityAlertBase + id,
      title: isHt ? l.notifHumidityHtTitle : l.notifHumidityTitle,
      body: l.notifHumidityBody(_printerLabel(status, l), humidity),
      payload: 'printer:$id',
    );
  }

  void _alertBedCooled(int id, PrinterStatus status, int temp) {
    final l = _l10n();
    _notifications.showAlert(
      event: NotifEvent.bedCooled,
      printerId: id,
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
