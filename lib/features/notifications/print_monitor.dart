import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:clock/clock.dart' as ambient;
import 'package:flutter/widgets.dart' show Locale;

import '../../core/ams/slot_addressing.dart';
import '../../core/diagnostics/notif_probe.dart';
import '../../core/format/datetime_format.dart';
import '../../core/models/printer_status.dart';
import '../../core/notifications/background_api.dart';
import '../../core/notifications/hms_actions.dart';
import '../../core/notifications/hms_catalog.dart';
import '../../core/notifications/notification_prefs.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/printers/offline_debounce.dart';
import '../../l10n/app_localizations.dart';

/// `TimerFactory` is part of this library's surface: the monitor takes one so
/// tests can control time instead of waiting out a window.
export '../../core/printers/offline_debounce.dart' show TimerFactory;

/// Room reserved per event type. The offsets added to a base are server row ids
/// (a printer, a maintenance task), which grow without bound and are never
/// reused after a delete — so the band has to be wide enough that no realistic
/// install reaches the next event type's numbers and starts replacing its
/// notifications.
const int alertBandWidth = 1000000;

/// Alert ID base per event type; add `printer_id` so alerts from different
/// printers (and types) don't overwrite each other. ID
/// [foregroundServiceNotificationId] belongs to the service's own notification
/// and is deliberately below every band here.
const int _finishedAlertBase = alertBandWidth;
const int _failedAlertBase = 2 * alertBandWidth;
const int _startedAlertBase = 3 * alertBandWidth;
const int _firstLayerAlertBase = 4 * alertBandWidth;
const int _milestoneAlertBase = 5 * alertBandWidth;
const int _plateAlertBase = 6 * alertBandWidth;
const int _offlineAlertBase = 7 * alertBandWidth;
const int _errorAlertBase = 8 * alertBandWidth;
const int _lowFilamentAlertBase = 9 * alertBandWidth;
const int _humidityAlertBase = 10 * alertBandWidth;
const int _bedCooledAlertBase = 11 * alertBandWidth;

/// Progress milestone thresholds (%).
const List<int> _milestones = [25, 50, 75];

/// Buttons an alert may carry. Android's notification shade lays out three and
/// drops whatever follows without a word.
const int _maxAlertActions = 3;


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

/// How far AMS humidity has to fall back below the user's threshold before its
/// alert re-arms.
///
/// bambuddy compares against a bare threshold and needs no band, because it only
/// looks every five minutes ([AMS_HISTORY_INTERVAL]) and holds the cooldown
/// below. This monitor sees every frame — roughly one a second — so a reading
/// resting on the threshold crosses it constantly, and without a band each dip
/// would re-arm the alert.
const int _humidityRearmMargin = 3;

/// How soon a unit that has retreated below the band and risen again is worth
/// another alert. The number is bambuddy's `AMS_ALARM_COOLDOWN_MINUTES = 60`;
/// the meaning is not. There it is a reminder interval — a unit sitting above
/// the threshold is announced again every hour. Here a stay is announced once,
/// and this only rations how often a fresh stay counts as fresh, because every
/// other event in this monitor alerts on the edge rather than on a timer.
const Duration _humidityAlertCooldown = Duration(hours: 1);

/// Highest `layer_num` still worth announcing as "first layer done", matching
/// bambuddy's own `2 <= layer_num <= 10` window. Above it the counter belongs to
/// a print we joined halfway or to the one that just ended.
const int _firstLayerLayerCeiling = 10;


/// Monitor state for one printer — tracks event edges between frames.
class _PrinterMemo {
  _PrinterMemo(TimerFactory timerFactory)
      : offline = OfflineDebounce(timerFactory: timerFactory);

  bool printing = false;
  bool firstLayerSent = false;
  final Set<int> milestonesSent = {};

  /// Whether this printer counts as offline, and the wait that keeps a flicker
  /// from alerting. The printer card follows the same rule.
  final OfflineDebounce offline;

  /// HMS code → last time it was seen in a frame. A code is forgotten once it
  /// has been absent for [_hmsClearGrace], so a genuinely new occurrence can
  /// re-alert while brief flaps/gaps stay silent.
  final Map<String, DateTime> hmsLastSeen = {};

  /// Codes that first showed up while the printer was disconnected, so no alert
  /// was ever posted for them. Kept out of [hmsLastSeen] until the printer
  /// answers again — held here only so the deferral is recorded once instead of
  /// on every frame of the outage. Cleared the moment it is back.
  final Set<String> hmsDeferredOffline = {};
  final Set<int> lowFilamentTrays = {}; // Latched tray IDs below threshold
  final Set<int> humidUnits = {}; // Latched AMS unit IDs above threshold

  /// Units whose current stay above the band has already been announced. Kept
  /// apart from [humidUnits] because a rise the cooldown swallowed leaves the
  /// unit latched but unannounced, and that alert is owed once the hour is up —
  /// otherwise a unit that never dips again is silently written off.
  final Set<int> humidAnnounced = {};

  /// When each unit last had a humidity alert. The latch above already covers a
  /// reading that stays up; this covers one that keeps crossing the band, where
  /// every crossing is a fresh latch and would otherwise be a fresh alert.
  final Map<int, DateTime> humidAlertedAt = {};
  bool awaitingBedCool = false;

  /// Whether the prep-phase progress was already recorded as ignored for this
  /// print — calibration reports a percentage on every frame, so without this
  /// the record would repeat for the whole phase instead of once.
  bool prepProgressLogged = false;

  /// What the frame that started this print said about the job — which, in the
  /// case that matters, is the job that had just ended. Null once a frame has
  /// brought something of its own. See [PrintMonitor._describesThisPrint].
  _JobFrame? previousJob;

  /// Whether that wait has been recorded for this print. Same reason as
  /// [prepProgressLogged]: the wait can span the whole pre-print sequence at
  /// roughly a frame a second.
  bool previousJobLogged = false;

  /// Reset print-specific state on starting a new print.
  void resetForNewPrint() {
    firstLayerSent = false;
    milestonesSent.clear();
    awaitingBedCool = false;
    prepProgressLogged = false;
    previousJob = null;
    previousJobLogged = false;
  }
}

/// The job-scoped half of one frame: which print it describes, how far in, and
/// how far along. Compared as a whole, so any of the three moving is evidence
/// that the printer has published something about the print that is running now.
typedef _JobFrame = ({int? layer, int? progress, String? job});

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
    DateTimeFormats Function()? formats,
    TimerFactory? timerFactory,
    String? Function(HmsError)? hmsDescribe,
    this._onPrintEnded,
  })  : _l10n = l10n ?? systemAppLocalizations,
        _now = clock ?? (() => ambient.clock.now()),
        _formats = formats ?? DateTimeFormats.system,
        _timer = timerFactory ?? Timer.new,
        // ignore: prefer_initializing_formals — private field with a named param
        _hmsDescribe = hmsDescribe;

  final NotificationService _notifications;
  final NotificationPrefs _prefs;
  final AppLocalizations Function() _l10n;
  final DateTime Function() _now;

  /// Read per notification rather than cached: the user can flip the system
  /// 24-hour switch while the service runs, and a monitor built at boot would
  /// otherwise keep spelling ETAs the old way until the next restart.
  final DateTimeFormats Function() _formats;
  final TimerFactory _timer;

  /// Callback invoked after print ends (success/error) — hooks up overdue
  /// maintenance reminder ([MaintenanceMonitor.remindOnPrintEnd]).
  final void Function(int printerId)? _onPrintEnded;

  /// Optional HMS code description resolver (Bambu catalog). null → fallback to
  /// "level · module (code)" format.
  final String? Function(HmsError)? _hmsDescribe;

  final Map<int, _PrinterMemo> _memo = {};
  _OngoingKey? _lastOngoing;

  /// When the last frame arrived, so a gap in the feed itself can be told from
  /// time passing with the feed healthy. Only the second kind may age an HMS code
  /// out of memory.
  DateTime? _lastFrameAt;

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
    _carryHmsMemoryOverFeedGap();
    for (final entry in statuses.entries) {
      // First frame of each printer is only primed, no alerts from it —
      // else fresh monitor (background isolate restarts on every background entry)
      // would treat current state as just-happened edges and fire "first layer/25%/HMS error"
      // for events that happened long ago.
      final isNew = !_memo.containsKey(entry.key);
      final memo = _memo.putIfAbsent(entry.key, () => _PrinterMemo(_timer));
      if (isNew) {
        _prime(entry.key, memo, entry.value);
      } else {
        _processPrinter(entry.key, entry.value, memo);
      }
    }
    // Printers gone from map — drop their timers and state.
    final gone = _memo.keys.where((id) => !statuses.containsKey(id)).toList();
    for (final id in gone) {
      _memo.remove(id)?.offline.dispose();
    }

    _updateOngoing(statuses);
  }

  /// Holds every remembered HMS code over a break in the feed.
  ///
  /// The clear-grace window is wall time, but the only evidence a fault cleared
  /// is a frame that no longer carries it. When nothing arrives at all — the
  /// socket dropped, the phone dozed — the window elapses against silence, and
  /// the first frame back would forget every standing code and alert about all of
  /// them again. The socket's own idle watchdog is longer than the window, so
  /// every disconnect it catches lands here.
  void _carryHmsMemoryOverFeedGap() {
    final now = _now();
    final last = _lastFrameAt;
    _lastFrameAt = now;
    if (last == null || now.difference(last) < _hmsClearGrace) return;
    for (final memo in _memo.values) {
      memo.hmsLastSeen.updateAll((_, _) => now);
    }
  }

  /// Cancels all pending per-printer offline-grace timers. Call when this
  /// monitor is being torn down (e.g. `onDestroy` of the background isolate) —
  /// without it, a timer scheduled just before teardown could still fire and
  /// touch a notification service that's no longer valid.
  void dispose() {
    for (final memo in _memo.values) {
      memo.offline.dispose();
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
    // Nothing job-scoped can be read off a frame that does not describe the job
    // ([_jobUnderway]). Priming off a calibration frame ("60%" at layer 0) would
    // latch 25 and 50 as already sent and swallow both when the real print
    // reaches them — the mirror image of the burst the gate in step 4) prevents.
    // The dispatch race reaches priming too, through an isolate that restarts
    // while it is on: the pre-print sequence has ticked `layer_num` past 2 while
    // the name and the percentage are still the finished print's. A latch set
    // from that frame has no edge left to clear it — priming records the printer
    // as already printing, so no print-start edge follows and the new print's
    // first layer would go by in silence. So the frame is recorded as the one to
    // beat instead, exactly as the print-start edge does with it.
    if (!_jobUnderway(status)) {
      memo.previousJob = _jobFrame(status);
    } else {
      // "First layer DONE" = printer is already on layer ≥ 2 (parity with
      // bambuddy: `on_first_layer_complete` fires at layer_num ≥ 2). If we prime
      // after completion, just record it — no alert. Deliberately without
      // [_firstLayerDone]'s upper bound: that window is there to decide whether
      // an alert is *due*, while a baseline asks whether it is *spent*, and a
      // counter in the hundreds is the plainest yes there is.
      if ((status.layerNum ?? 0) >= 2) memo.firstLayerSent = true;
      if (status.progress != null) {
        final pct = status.progress!.round();
        for (final m in _milestones) {
          if (pct >= m) memo.milestonesSent.add(m);
        }
      }
    }
    memo.offline.seed(status.connected);
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
          final key = units[i].id ?? i;
          // Announced as well as latched: this stay predates the monitor, and an
          // unannounced latch is one the next frame would decide is still owed.
          memo.humidUnits.add(key);
          memo.humidAnnounced.add(key);
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
        'stage': status.stgCur,
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
      // This frame's job numbers are the previous print's until the printer
      // says otherwise — see [_describesThisPrint].
      memo.previousJob = _jobFrame(status);
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

    // Everything below that describes the JOB — the first layer, the progress
    // milestones — needs a frame that describes THIS job. Read once: both steps
    // ask the same question of the same frame, and the record it may write is
    // one per print.
    final describesThisPrint = _describesThisPrint(id, status, memo);

    // 3) First layer DONE (once per print), on bambuddy's own terms — see
    // [_firstLayerDone].
    //
    // The latch is set regardless of the preference, so the decision — an alert
    // or one suppression record — happens once per edge. With the check inside
    // the condition it was retaken on every frame for the rest of the print,
    // which a record would have turned into hundreds of lines. Sound because
    // `_prefs` is immutable for this monitor's whole life (the service is rebuilt
    // from scratch on the next background entry); if live preferences ever land,
    // this silently becomes "enable mid-print, stay quiet until the next one".
    // `_prime` latches both of these without alerting, when it primes off a
    // frame that describes the job at all.
    //
    // The latch stays clear while a frame is merely unusable, so an alert this
    // frame could not settle is still owed on the next one. bambuddy holds its
    // own flag the same way (`_first_layer_notified`).
    if (isPrinting &&
        !memo.firstLayerSent &&
        describesThisPrint &&
        _firstLayerDone(id, status)) {
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
    if (isPrinting && status.progress != null && describesThisPrint) {
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

  /// Whether the reported `progress` describes the JOB rather than a stage of
  /// the printer's own. During bed levelling / vibration compensation the
  /// firmware reports a percentage of THAT phase: observed jumping 6 → 60 in
  /// 300 ms at `layer_num == 0`, which crossed two milestones at once before a
  /// single line of plastic was down. The job is underway from the first layer
  /// on, and only while the printer is not in a stage of its own.
  ///
  /// The stage half ([PrinterStatus.inNamedStage]) is what the layer check alone
  /// cannot cover: Bambu firmware ticks `layer_num` through the pre-print
  /// sequence, so "layer ≥ 1" is true while the bed is still being scanned. A
  /// crossing this drops is not lost — nothing latches, so it is announced from
  /// the next frame that describes the job.
  ///
  /// That half is deliberately not narrowed to the pre-print window, so a stage
  /// the printer enters *mid*-print (a filament change, a user pause) holds a
  /// threshold back until it clears rather than announcing it on time. The
  /// alternative — trusting the percentage once the print looks underway — is
  /// what let a stale 100% cross all three thresholds at once, and a milestone
  /// arriving a filament change late is the cheaper of the two.
  ///
  /// A frame without `layer_num` says nothing about the phase, so it counts as
  /// underway — a server that omits the field keeps the previous behaviour
  /// rather than going silent for the whole print.
  static bool _jobUnderway(PrinterStatus status) =>
      (status.layerNum ?? 1) >= 1 && !status.inNamedStage;

  /// Whether this frame says the first layer is behind us, on the terms
  /// bambuddy's own `on_layer_change` uses (server #1837):
  ///
  /// * layer **2** is the first layer *done* — layer 1 is it being printed;
  /// * the window stops at **10**, because a counter far past 2 belongs either
  ///   to a print we joined halfway or to the job that has just ended, and
  ///   neither is news. bambuddy's window is the same `[2, 10]`;
  /// * a printer **in a stage of its own is not laying that layer down**: the
  ///   firmware ticks `layer_num` through bed levelling, bed scanning and
  ///   nozzle cleaning, which announced a first layer minutes before the first
  ///   line of plastic — and, right after a dispatch, under the previous
  ///   print's name. bambuddy gates on `mc_print_sub_stage`, which the
  ///   WebSocket does not carry; [PrinterStatus.inNamedStage] asks the same
  ///   question of the field both lanes do carry.
  ///
  /// Records the one frame it turns down per print, because "the first layer
  /// went by and nothing arrived" is otherwise indistinguishable from the alert
  /// being switched off.
  bool _firstLayerDone(int id, PrinterStatus status) {
    final layer = status.layerNum;
    if (layer == null || layer < 2 || layer > _firstLayerLayerCeiling) {
      return false;
    }
    if (!status.inNamedStage) return true;
    NotifProbe.suppressed(
      NotifSkip.prepPhase,
      printerId: id,
      event: NotifEvent.firstLayer,
      fields: {'layer': layer, 'stage': status.stgCur},
    );
    return false;
  }

  /// Whether this frame's job numbers belong to the print that is running now.
  ///
  /// bambuddy's state is a rolling merge of the printer's partial MQTT reports,
  /// so the frame that flips a printer to RUNNING still carries the previous
  /// print's name, layer and percentage — the printer has not published the new
  /// job's yet. That frame is why a job sent seconds earlier announced the
  /// *finished* one's first layer: `layer_num` was still the number the pre-print
  /// sequence had ticked, and the name still the file that had just come off the
  /// plate. Nothing job-scoped runs until one of the three moves.
  ///
  /// Deliberately not a comparison against the new job's identity: the app
  /// cannot know it — the name arrives on the wire in its own time, and the
  /// same file printed twice in a row is a legitimate case that would fail such
  /// a test. "Something new arrived" is the weakest question that answers this,
  /// and it opens for the rest of the print the moment it is answered.
  bool _describesThisPrint(int id, PrinterStatus status, _PrinterMemo memo) {
    final previous = memo.previousJob;
    if (previous == null) return true;
    if (_jobFrame(status) != previous) {
      memo.previousJob = null;
      return true;
    }
    if (!memo.previousJobLogged) {
      memo.previousJobLogged = true;
      // No `event`: this one reading gates both the first layer and the
      // milestones, so naming either would describe a narrower decision than
      // the one that was taken.
      NotifProbe.suppressed(
        NotifSkip.previousJob,
        printerId: id,
        fields: {
          'layer': previous.layer,
          'pct': previous.progress,
          'stage': status.stgCur,
        },
      );
    }
    return false;
  }

  /// The job half of a frame. The name is compared, never recorded — a print's
  /// file name is user data and stays out of the log (`docs/diagnostics-log.md`).
  static _JobFrame _jobFrame(PrinterStatus status) => (
        layer: status.layerNum,
        progress: status.progress?.round(),
        job: status.currentPrint ?? status.gcodeFile,
      );

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
    memo.offline.observe(
      status.connected,
      onSustained: () {
        if (_on(NotifEvent.printerOffline)) {
          _alertOffline(id, status);
        } else {
          NotifProbe.suppressed(_offReason,
              printerId: id, event: NotifEvent.printerOffline);
        }
      },
      // The alert the wait was holding back never happened, which answers both
      // "the offline alert came fifteen seconds late" and "it never came at
      // all". One record per flap: a disconnect already alerted for is not
      // holding anything back.
      onFlicker: () => NotifProbe.suppressed(NotifSkip.reconnected,
          printerId: id, event: NotifEvent.printerOffline),
    );
  }

  void _processHms(int id, PrinterStatus status, _PrinterMemo memo) {
    final errors = status.hmsErrors;
    if (errors == null) return; // Field missing in frame — no change
    final now = _now();
    // An offline printer can't be actively faulting — its `hms_errors` are just
    // the last-known values carried forward by mergedWith. This is the same rule
    // `displayableHmsErrors` applies for every screen; it is spelled out again
    // here because this path needs the carried-forward codes themselves, which
    // that function drops. Change the meaning of "offline" there and this line
    // has to move with it.
    // Never alert while
    // disconnected, but still REFRESH last-seen for present codes below: that
    // pauses the clear-grace clock across the outage, so a fault known before
    // the disconnect doesn't spuriously re-alert on reconnect.
    final online = status.connected != false;
    // Forget codes absent past the grace window — only those can re-alert. Run
    // before refreshing so codes present this frame (still within grace) survive,
    // and only while connected: a frame from a disconnected printer carries no
    // evidence that anything cleared, so the whole memory holds still for the
    // outage rather than ageing out against a clock nothing is answering.
    if (online) {
      memo.hmsLastSeen
          .removeWhere((_, seen) => now.difference(seen) >= _hmsClearGrace);
      memo.hmsDeferredOffline.clear();
    }

    for (final e in errors) {
      final key = _hmsKey(e);
      if (key == null) continue;
      final isNew = !memo.hmsLastSeen.containsKey(key);
      if (isNew && !online) {
        // Never announced, so latching it would silence it for good: the printer
        // can come back with this fault still standing, and until then nothing
        // ages it out — with a second printer streaming frames the grace window
        // is refreshed faster than it can elapse. Defer the decision instead.
        if (memo.hmsDeferredOffline.add(key)) {
          NotifProbe.suppressed(
            NotifSkip.offline,
            printerId: id,
            event: NotifEvent.printerError,
            fields: {'code': _hmsCode(e), 'sev': e.severity},
          );
        }
        continue;
      }
      memo.hmsLastSeen[key] = now; // present this frame → refresh last-seen
      // Only ever the first sighting of a code gets this far, so each of the
      // records below is one per code per clear-grace window, not one per frame.
      // A record for the already-known case is deliberately absent: the WebSocket
      // lane carries `hms_codes` on every frame, so a standing code with no
      // notification record next to it *is* the dedup, visible on the same
      // timeline.
      if (!isNew) continue;
      final skip = _hmsSkipReason(e);
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
  /// Three separate answers where the code used to fold them into one boolean.
  /// "You turned this off" is not "the firmware sent a code nobody documented" —
  /// the latter being the single largest silent drop on this path, since one
  /// physical fault emits several codes and only one of them is a real fault.
  /// Every answer here settles the code for the life of this isolate; a
  /// disconnected printer is the one case that does not, so it is deferred by
  /// the caller rather than answered here.
  NotifSkip? _hmsSkipReason(HmsError e) {
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
    int? value;
    bool? isHt;
    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      final humidity = unit.humidity;
      if (humidity == null) continue;
      final key = unit.id ?? i;
      if (humidity > threshold) {
        final justRose = memo.humidUnits.add(key);
        // Said once per stay, not once per frame — but the saying is what counts
        // as done, so a rise the cooldown swallowed is still owed one.
        if (memo.humidAnnounced.contains(key)) continue;
        final last = memo.humidAlertedAt[key];
        final now = _now();
        if (last != null && now.difference(last) < _humidityAlertCooldown) {
          // Only on the rise itself: the frames after it would repeat this
          // record every second until the hour is up.
          if (justRose) {
            NotifProbe.suppressed(
              NotifSkip.throttled,
              printerId: id,
              event: NotifEvent.amsHumidity,
              fields: {'unit': key, 'humidity': humidity},
            );
          }
          continue;
        }
        memo.humidAlertedAt[key] = now;
        memo.humidAnnounced.add(key);
        // Worst unit wins when several cross in the same frame — there is
        // only one notification slot per printer, so the driest excuse loses.
        if (value == null || humidity > value) {
          value = humidity;
          isHt = unit.isAmsHt;
        }
      } else if (humidity <= threshold - _humidityRearmMargin) {
        // Only a real retreat re-arms it. Sitting one point under the threshold
        // is the same damp unit, not a resolved one.
        memo.humidUnits.remove(key);
        memo.humidAnnounced.remove(key);
      }
    }
    if (value == null) return;
    if (_on(NotifEvent.amsHumidity)) {
      _alertHumidity(id, status, value, isHt ?? false);
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
    return _errorAlertBase + _stableDigest('$id:$code');
  }

  /// FNV-1a digest folded into one band, spelled out rather than taken from
  /// `Object.hash`, whose seed is drawn afresh on every VM start. This isolate
  /// restarts each time the app is backgrounded, so a seeded id handed the same
  /// standing fault a new notification after every restart instead of replacing
  /// the one already on screen.
  static int _stableDigest(String s) {
    var h = 0x811c9dc5;
    for (var i = 0; i < s.length; i++) {
      h = ((h ^ s.codeUnitAt(i)) * 0x01000193) & 0xffffffff;
    }
    return h % alertBandWidth;
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
  /// Keyed by [globalTrayId], so the latch survives an AMS being re-seated.
  Map<int, int> _trayRemains(PrinterStatus status) {
    final out = <int, int>{};
    final List<AmsUnit> units = status.ams ?? const [];
    for (var u = 0; u < units.length; u++) {
      final int unitId = units[u].id ?? u;
      for (final AmsTray t in units[u].trays ?? const []) {
        final int? remain = t.remain;
        if (remain != null && remain >= 0 && !t.isEmpty) {
          out[globalTrayId(amsId: unitId, trayId: t.id ?? 0)] = remain;
        }
      }
    }
    for (final t in status.externalSpools) {
      final remain = t.remain;
      if (remain != null && remain >= 0 && !t.isEmpty) {
        // `vt_tray` already reports the holder's global id.
        out[t.id ?? externalTrayIdBase] = remain;
      }
    }
    return out;
  }

  /// ETA as concrete finish time (e.g. "21:20"), not "in X".
  /// If print finishes different day, the date comes along.
  String? _etaClock(int? minutes) {
    if (minutes == null) return null;
    final now = _now();
    return _formats()
        .clockOnDay(now.add(Duration(minutes: minutes)), now: now);
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
