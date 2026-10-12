import 'dart:async';

import 'package:clock/clock.dart';

import '../../core/format/text_utils.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/ams/slot_addressing.dart';
import '../../core/diagnostics/notif_probe.dart';
import '../../core/format/datetime_format.dart';
import '../../core/models/printer_status.dart';
import '../../core/notifications/background_api.dart';
import '../../core/notifications/hms_actions.dart';
import '../../core/notifications/hms_catalog.dart';
import '../../core/notifications/notification_prefs.dart';
import '../../core/printers/offline_debounce.dart';
import '../../core/app_context.dart';
import '../../l10n/app_localizations.dart';

/// `TimerFactory` is part of this library's surface: the monitor takes one so
/// tests can control time instead of waiting out a window.
export '../../core/printers/offline_debounce.dart' show TimerFactory;

/// The band width moved to core so a core isolate can compute its own ids;
/// re-exported so every caller keeps reading it from here.
export '../../core/notifications/notification_service.dart' show alertBandWidth;

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

/// How long an HMS code is remembered after it last appeared: a flicker shorter
/// than this is the same fault. Parity with bambuddy (docs/notification-rules.md, "HMS faults").
const Duration _hmsClearGrace = Duration(seconds: 30);

/// How long an HMS fault has to stand before it alerts. Our own rule, not
/// bambuddy's (docs/notification-rules.md, "HMS faults").
const Duration _hmsHold = Duration(seconds: 15);

/// User-cancel echoes, not faults; dropped as bambuddy does, kept here as a safety
/// net for older servers (docs/notification-rules.md, "HMS faults").
const Set<String> _hmsUserActionCodes = {
  '0300_400C', // "The task was canceled."
  '0500_400E', // "Printing was cancelled."
};

/// How far AMS humidity has to fall back below the threshold before its alert
/// re-arms (docs/notification-rules.md, "AMS humidity").
const int _humidityRearmMargin = 3;

/// bambuddy's `AMS_ALARM_COOLDOWN_MINUTES = 60`, but rationing fresh stays rather
/// than reminding (docs/notification-rules.md, "AMS humidity").
const Duration _humidityAlertCooldown = Duration(hours: 1);

/// Something that may happen at most once per print: a latch, plus one record for
/// the ones that explain a silence (docs/notification-rules.md, "Once per print").
class OncePerPrint {
  bool _fired = false;

  /// Whether it has already happened during this print.
  bool get fired => _fired;

  /// Latches and runs [body] the first time; does nothing afterwards. Returns
  /// whether this call was the one that fired.
  bool claim([void Function()? body]) {
    if (_fired) return false;
    _fired = true;
    body?.call();
    return true;
  }

  void reset() => _fired = false;
}

/// The events this monitor allows itself once per print. Keyed by an enum so
/// [_PrinterMemo.resetForNewPrint] clears a newly added one without anybody
/// remembering to add a line — which is the failure this type exists to stop.
enum PrintOnce {
  /// The first-layer alert.
  firstLayer,

  /// The record for progress ignored during the prep phase.
  prepProgressRecorded,

  /// The record for a frame still describing the *previous* job.
  previousJobRecorded,
}

/// Monitor state for one printer — tracks event edges between frames.
class _PrinterMemo {
  _PrinterMemo(TimerFactory timerFactory)
    : offline = OfflineDebounce(timerFactory: timerFactory);

  bool printing = false;

  /// See [PrintOnce]; read through [once].
  final Map<PrintOnce, OncePerPrint> _once = {
    for (final event in PrintOnce.values) event: OncePerPrint(),
  };

  OncePerPrint once(PrintOnce event) => _once[event]!;

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

  /// Faults seen, passed every filter, and now standing out [_hmsHold]. Also in
  /// [hmsLastSeen], which is what keeps a second frame from starting a second
  /// hold; a hold that ends without an alert takes the code out of both.
  final Map<String, _Hold> hmsHeld = {};
  final Set<int> lowFilamentTrays = {};
  final Set<int> humidUnits = {};

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

  /// What the frame that started this print said about the job — which, in the
  /// case that matters, is the job that had just ended. Null once a frame has
  /// brought something of its own. See [PrintMonitor._describesThisPrint].
  _JobFrame? previousJob;

  /// Reset print-specific state on starting a new print.
  void resetForNewPrint() {
    for (final once in _once.values) {
      once.reset();
    }
    milestonesSent.clear();
    awaitingBedCool = false;
    previousJob = null;
  }

  void dispose() {
    offline.dispose();
    for (final hold in hmsHeld.values) {
      hold.pause();
    }
    hmsHeld.clear();
  }
}

/// The time an HMS fault still has to stand, and the timer counting it down
/// while the printer carries the fault.
class _Hold {
  _Hold(this.fault) : remaining = _hmsHold;

  /// The latest copy of the fault, for the job id and actions its buttons send.
  HmsError fault;
  Duration remaining;
  Timer? _timer;
  DateTime? _since;

  bool get running => _timer != null;

  void run(TimerFactory timer, void Function() onDone) {
    _since = clock.now();
    _timer = timer(remaining, onDone);
  }

  /// Stops the count and keeps what is left of it.
  void pause() {
    final since = _since;
    if (since != null) remaining -= clock.now().difference(since);
    _timer?.cancel();
    _timer = null;
    _since = null;
  }
}

/// The job-scoped half of one frame: which print it describes, how far in, and
/// how far along. Compared as a whole, so any of the three moving is evidence
/// that the printer has published something about the print that is running now.
typedef _JobFrame = ({int? layer, int? progress, String? job});

/// Throttling key for the ongoing notification: one field per thing the
/// notification actually shows — which printer leads, its whole percent, its ETA
/// minute and how many are running. Anything else would redraw it on a WS frame
/// that changes nothing a reader can see.
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
    required this._serverUrl,
    this._prefs = NotificationPrefs.defaults,
    AppLocalizations Function()? l10n,
    DateTimeFormats Function()? formats,
    TimerFactory? timerFactory,
    String? Function(HmsError)? hmsDescribe,
    this._onPrintEnded,
  }) : _l10n = l10n ?? systemAppLocalizations,
       _formats = formats ?? DateTimeFormats.system,
       _timer = timerFactory ?? Timer.new,
       // ignore: prefer_initializing_formals — private field with a named param
       _hmsDescribe = hmsDescribe;

  final NotificationService _notifications;

  /// The server these printers belong to, tagged into the HMS payload so a
  /// button tapped after a switch is not sent to another server's printer.
  final String _serverUrl;
  final NotificationPrefs _prefs;
  final AppLocalizations Function() _l10n;

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

  /// The frames the last [update] brought: a held fault is judged against the
  /// printer as it is when the hold runs out, not as it was when it started.
  Map<int, PrinterStatus> _latest = const {};
  _OngoingKey? _lastOngoing;

  /// When the last frame arrived, so a gap in the feed itself can be told from
  /// time passing with the feed healthy. Only the second kind may age an HMS code
  /// out of memory.
  DateTime? _lastFrameAt;

  /// Posts [alert], or records the one line that says why it was not posted
  /// (docs/notification-rules.md, "Alert or record why not"). [fields] rides on the record only.
  void _alertOrRecordOff(
    int id,
    NotifEvent event,
    void Function() alert, {
    Map<String, Object?> fields = const {},
  }) {
    if (_on(event)) {
      alert();
      return;
    }
    NotifProbe.suppressed(
      _offReason,
      printerId: id,
      event: event,
      fields: fields,
    );
  }

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
    _latest = Map.of(statuses);
    _carryHmsMemoryOverFeedGap();
    for (final entry in statuses.entries) {
      // The first frame of each printer is only primed: a monitor is rebuilt on
      // every background entry and would fire long-past events as fresh edges.
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
      _memo.remove(id)?.dispose();
    }

    _updateOngoing(statuses);
  }

  /// Holds every remembered HMS code over a break in the feed longer than the grace
  /// (docs/notification-rules.md, "HMS faults").
  void _carryHmsMemoryOverFeedGap() {
    final now = clock.now();
    final last = _lastFrameAt;
    _lastFrameAt = now;
    if (last == null || now.difference(last) < _hmsClearGrace) return;
    for (final memo in _memo.values) {
      memo.hmsLastSeen.updateAll((_, _) => now);
    }
  }

  /// Cancels every pending per-printer timer (offline grace, HMS holds), so none
  /// fires into a notification service the torn-down isolate no longer has.
  void dispose() {
    for (final memo in _memo.values) {
      memo.dispose();
    }
  }

  /// "Plate not empty" event from separate WS frame `plate_not_empty` (camera
  /// detected objects on bed at print start → bambuddy held the print).
  /// Only correct source for this alert — see comment at step 5) in [_processPrinter].
  /// Printer name from frame (status may not be known), with fallback to list title.
  void onPlateNotEmpty(int printerId, String? printerName) {
    _alertOrRecordOff(
      printerId,
      NotifEvent.plateNotEmpty,
      () => _alertPlate(printerId, printerName),
    );
  }

  /// Baseline from the first observed frame: records what is already there so later
  /// frames detect only true edges, and fires nothing (docs/notification-rules.md, "Baseline").
  /// [id] is the map key, not `status.id`.
  void _prime(int id, _PrinterMemo memo, PrinterStatus status) {
    memo.printing = status.isPrinting;
    // Nothing job-scoped is read off a frame that does not describe the job; it is
    // recorded as the one to beat instead (docs/notification-rules.md, "Baseline").
    if (!status.jobUnderway) {
      memo.previousJob = _jobFrame(status);
    } else {
      // If we prime after the first layer, just record it — no alert. The
      // baseline reading, deliberately without the window's ceiling; the two
      // are one pair in [PrinterStatus.firstLayerPassed].
      if (status.firstLayerPassed) memo.once(PrintOnce.firstLayer).claim();
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
      final now = clock.now();
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
      _alertOrRecordOff(
        id,
        NotifEvent.printStarted,
        () => _alertStarted(id, status),
      );
    }

    // 2) Print end (edge printing → not-printing): success / error.
    if (wasPrinting && !isPrinting) {
      final state = status.state?.toUpperCase();
      switch (state) {
        case 'FINISH':
        case 'FINISHED':
          memo.awaitingBedCool = true;
          _alertOrRecordOff(
            id,
            NotifEvent.printFinished,
            () => _alertFinished(id, status),
          );
          // Maintenance reminder independent of print finish prefs.
          _onPrintEnded?.call(id);
        case 'FAILED':
          memo.awaitingBedCool = true;
          _alertOrRecordOff(
            id,
            NotifEvent.printFailed,
            () => _alertFailed(id, status),
          );
          _onPrintEnded?.call(id);
        // Other/unknown final state → no false alert.
      }
      // Every end is recorded, handled or not (docs/notification-rules.md, "Print end").
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
    // [_firstLayerDone]. The latch is set whatever the preference says
    // (docs/notification-rules.md, "First layer").
    if (isPrinting &&
        !memo.once(PrintOnce.firstLayer).fired &&
        describesThisPrint &&
        _firstLayerDone(id, status)) {
      memo.once(PrintOnce.firstLayer).claim();
      _alertOrRecordOff(
        id,
        NotifEvent.firstLayer,
        () => _alertFirstLayer(id, status),
      );
    }

    // 4) Progress milestones (once per print). Same latch-on-the-edge shape as
    // the first layer above, plus the prep-phase gate — see [PrinterStatus.jobUnderway].
    if (isPrinting && status.progress != null && describesThisPrint) {
      if (!status.jobUnderway) {
        _recordPrepProgress(id, status, memo);
      } else {
        final pct = status.progress!.round();
        for (final m in _milestones) {
          // `add` is false when the threshold was already crossed — the same guard
          // as the old `!contains(m)`, with the latch now on the edge.
          if (pct >= m && memo.milestonesSent.add(m)) {
            _alertOrRecordOff(
              id,
              NotifEvent.milestones,
              () => _alertMilestone(id, status, m),
              fields: {'pct': m},
            );
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

  /// Whether this frame says the first layer is behind us, on the terms of bambuddy's
  /// `on_layer_change` (server #1837): layer 2, a window that stops at 10, and not
  /// while the printer is in a stage of its own. Records the one frame it turns down
  /// per print (docs/notification-rules.md, "First layer").
  bool _firstLayerDone(int id, PrinterStatus status) {
    if (!status.firstLayerInWindow) return false;
    if (!status.inNamedStage) return true;
    NotifProbe.suppressed(
      NotifSkip.prepPhase,
      printerId: id,
      event: NotifEvent.firstLayer,
      fields: {'layer': status.layerNum, 'stage': status.stgCur},
    );
    return false;
  }

  /// Whether this frame's job numbers belong to the print running now, not to the
  /// previous one that bambuddy's rolling merge still carries
  /// (docs/notification-rules.md, "Which frame describes this print").
  bool _describesThisPrint(int id, PrinterStatus status, _PrinterMemo memo) {
    final previous = memo.previousJob;
    if (previous == null) return true;
    if (_jobFrame(status) != previous) {
      memo.previousJob = null;
      return true;
    }
    // No `event`: this one reading gates both the first layer and the
    // milestones, so naming either would describe a narrower decision than the
    // one that was taken.
    memo
        .once(PrintOnce.previousJobRecorded)
        .claim(
          () => NotifProbe.suppressed(
            NotifSkip.previousJob,
            printerId: id,
            fields: {
              'layer': previous.layer,
              'pct': previous.progress,
              'stage': status.stgCur,
            },
          ),
        );
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
    memo
        .once(PrintOnce.prepProgressRecorded)
        .claim(
          () => NotifProbe.suppressed(
            NotifSkip.prepPhase,
            printerId: id,
            event: NotifEvent.milestones,
            fields: {
              'pct': status.progress?.round(),
              'stage': status.stgCurName,
            },
          ),
        );
  }

  void _processOffline(int id, PrinterStatus status, _PrinterMemo memo) {
    memo.offline.observe(
      status.connected,
      onSustained: () {
        _alertOrRecordOff(
          id,
          NotifEvent.printerOffline,
          () => _alertOffline(id, status),
        );
      },
      // The alert the wait was holding back never happened, which answers both
      // "the offline alert came fifteen seconds late" and "it never came at
      // all". One record per flap: a disconnect already alerted for is not
      // holding anything back.
      onFlicker: () => NotifProbe.suppressed(
        NotifSkip.reconnected,
        printerId: id,
        event: NotifEvent.printerOffline,
      ),
    );
  }

  void _processHms(int id, PrinterStatus status, _PrinterMemo memo) {
    final errors = status.hmsErrors;
    if (errors == null) return; // Field missing in frame — no change
    final now = clock.now();
    // An offline printer cannot be faulting: its `hms_errors` are carried-forward
    // values. Never alert while disconnected, but still refresh last-seen below
    // (docs/notification-rules.md, "HMS faults").
    final online = status.connected != false;
    // Forget codes absent past the grace, only while connected: a frame from a
    // disconnected printer carries no evidence that anything cleared.
    if (online) {
      _pauseAbsentHolds(memo, errors);
      memo.hmsLastSeen.removeWhere((key, seen) {
        if (now.difference(seen) < _hmsClearGrace) return false;
        _dropHold(id, memo, key);
        return true;
      });
      memo.hmsDeferredOffline.clear();
    }

    for (final e in errors) {
      final key = _hmsKey(e);
      if (key == null) continue;
      final isNew = !memo.hmsLastSeen.containsKey(key);
      if (isNew && !online) {
        // Never announced: latching it would silence it for good if the printer returns
        // with the fault standing. Defer instead (docs/notification-rules.md, "HMS faults").
        if (memo.hmsDeferredOffline.add(key)) {
          NotifProbe.suppressed(
            NotifSkip.offline,
            printerId: id,
            event: NotifEvent.printerError,
            fields: {'code': _hmsCode(e), 'sev': e.severity, 'lvl': e.level},
          );
        }
        continue;
      }
      memo.hmsLastSeen[key] = now;
      final hold = memo.hmsHeld[key];
      if (hold != null) {
        hold.fault = e;
        if (!hold.running && online) _runHold(id, memo, key);
      }
      // Only a code's first sighting gets this far: one record per code per grace
      // window, and none for the known case, where the standing code is the dedup
      // (docs/notification-rules.md, "HMS faults").
      if (!isNew) continue;
      final skip = _hmsSkipReason(e);
      if (skip != null) {
        NotifProbe.suppressed(
          skip,
          printerId: id,
          event: NotifEvent.printerError,
          fields: {'code': _hmsCode(e), 'sev': e.severity, 'lvl': e.level},
        );
        continue;
      }
      memo.hmsHeld[key] = _Hold(e);
      _runHold(id, memo, key);
    }
  }

  /// Counts down what is left of a fault's hold. It alerts only if the
  /// printer still carries the fault, online, when the count reaches zero.
  void _runHold(int id, _PrinterMemo memo, String key) {
    final hold = memo.hmsHeld[key]!;
    hold.run(_timer, () {
      memo.hmsHeld.remove(key);
      final status = _latest[id];
      if (status == null || status.connected == false) {
        // Never announced, so it is not latched either — the same deferral a
        // fault first seen while offline gets. It holds again from the frame
        // that brings the printer back with it.
        memo.hmsLastSeen.remove(key);
        NotifProbe.suppressed(
          NotifSkip.offline,
          printerId: id,
          event: NotifEvent.printerError,
          fields: {'code': key},
        );
        return;
      }
      _alertError(id, status, hold.fault);
    });
  }

  /// Pauses the hold of every fault an online frame no longer carries. It
  /// resumes when the fault is back, and ends only once the fault has stayed
  /// away for [_hmsClearGrace] ([_dropHold]).
  void _pauseAbsentHolds(_PrinterMemo memo, List<HmsError> errors) {
    if (memo.hmsHeld.isEmpty) return;
    final present = errors.map(_hmsKey).toSet();
    for (final MapEntry(:key, value: hold) in memo.hmsHeld.entries) {
      if (hold.running && !present.contains(key)) hold.pause();
    }
  }

  /// Ends a hold whose fault cleared for good before it had stood long enough.
  void _dropHold(int id, _PrinterMemo memo, String key) {
    final hold = memo.hmsHeld.remove(key);
    if (hold == null) return;
    hold.pause();
    NotifProbe.suppressed(
      NotifSkip.transient,
      printerId: id,
      event: NotifEvent.printerError,
      fields: {'code': key},
    );
  }

  /// Why this HMS code produces no alert, or null when it produces one: off, a
  /// user-action code, or undocumented (docs/notification-rules.md, "HMS faults").
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
    _alertOrRecordOff(
      id,
      NotifEvent.lowFilament,
      () => _alertLowFilament(id, status, triggeredRemain ?? threshold),
    );
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
        final now = clock.now();
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
    // Read out of the mutable locals: a closure cannot keep the promotion the
    // null check just made.
    final worst = value;
    final worstIsHt = isHt ?? false;
    if (worst == null) return;
    _alertOrRecordOff(
      id,
      NotifEvent.amsHumidity,
      () => _alertHumidity(id, status, worst, worstIsHt),
    );
  }

  void _processBedCooled(int id, PrinterStatus status, _PrinterMemo memo) {
    if (!memo.awaitingBedCool) return;
    final bed = status.temperatures?['bed'];
    if (bed == null) return;
    if (bed < _prefs.bedCooledTemp) {
      memo.awaitingBedCool = false;
      _alertOrRecordOff(
        id,
        NotifEvent.bedCooled,
        () => _alertBedCooled(id, status, bed.round()),
      );
    }
  }

  /// What goes after "ETA" in the ongoing notification, or null for none; branches in
  /// the order of [PrinterStatus.etaRank] (docs/notification-rules.md, "The ongoing notification").
  String? _etaText(PrinterStatus s) {
    final minutes = s.remainingTime;
    if (minutes == null) return null;
    if (minutes > 0) {
      final now = clock.now();
      return _formats().clockOnDay(
        now.add(Duration(minutes: minutes)),
        now: now,
      );
    }
    return s.isPreparing ? null : _l10n().notifEtaSoon;
  }

  /// Ongoing notification for currently printing (one, for earliest ETA).
  void _updateOngoing(Map<int, PrinterStatus> statuses) {
    final printing = statuses.values.where((s) => s.isPrinting).toList()
      ..sort((a, b) => a.etaRank.compareTo(b.etaRank));

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
    // The mean over every printing machine, for the log only
    // (docs/notification-rules.md, "The ongoing notification").
    final reported = [for (final s in printing) ?s.progress?.clamp(0, 100)];
    final overall = reported.isEmpty
        ? percent
        : (reported.reduce((a, b) => a + b) / reported.length).round().clamp(
            0,
            100,
          );
    // Everything the notification shows, and nothing else. The mean used to be
    // here because the body printed it; now that it does not, keeping it would
    // re-post a notification whose every visible field is unchanged.
    final key = _OngoingKey(
      lead.id,
      percent,
      lead.remainingTime,
      printing.length,
    );
    if (key == _lastOngoing) return;
    _lastOngoing = key;
    // Recorded here, not in the notification decorator, whose title and body carry the
    // job name that never enters a log.
    NotifProbe.ongoing(
      printerId: lead.id,
      percent: percent,
      etaMin: lead.remainingTime,
      active: printing.length,
      overall: overall,
    );

    final l = _l10n();
    final eta = _etaText(lead);
    final String title;
    final String body;
    if (printing.length == 1) {
      // One printer: the job is what the user is waiting for, and the machine
      // it runs on needs no saying.
      title = _jobLabel(lead, l);
      body = eta == null ? '$percent%' : l.notifOngoingBody(percent, eta);
    } else {
      // Several: the headline is how many run; the bar, the line and the ETA
      // belong to the one that finishes first.
      title = l.printingCount(printing.length);
      // Not `lead.name ?? …`: a printer named "  " would leave the line with
      // a gap between two separators.
      final name = _printerLabel(lead, l);
      // Prefixed with the dashboard's own label so both surfaces pick the same printer
      // and call it the same thing.
      final line = eta == null
          ? l.notifOngoingMultiBodyNoEta(name, percent)
          : l.notifOngoingMultiBody(name, percent, eta);
      body = '${l.nextAvailableLabel}$line';
    }
    // A preparing machine gets the indeterminate bar: its zero percent is not progress.
    _notifications.showOngoing(
      title: title,
      body: body,
      progress: lead.isPreparing ? null : percent,
    );
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
    final name = (printerName?.trim().isNotEmpty ?? false)
        ? printerName!.trim()
        : null;
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
          : hmsPayload(
              printerId: id,
              fullCode: fullCode,
              jobId: err.jobId,
              serverUrl: _serverUrl,
            ),
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
    // Stable, or the same standing fault got a new notification after every
    // restart of this isolate instead of replacing the one on screen.
    return _errorAlertBase + stableDigest('$id:$code') % alertBandWidth;
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
}
