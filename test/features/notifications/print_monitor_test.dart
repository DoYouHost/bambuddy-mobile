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

/// Records calls instead of touching the plugin — we check the transitions only.
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

/// An AMS tray with a remaining amount and a type (non-empty), for low-filament
/// tests.
AmsTray _tray({int id = 0, int? remain, String type = 'PLA'}) =>
    AmsTray(id: id, remain: remain, trayType: type, trayColor: 'FFFFFFFF');

/// A timer the test drives — [fire] simulates the offline grace running out.
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

/// Every event on — for testing individual detections.
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
  // lookupAppLocalizations inside the monitor needs an initialised binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  // Fixed clock → a deterministic ETA time in the assertions.
  PrintMonitor monitor(_FakeNotifications fake) => PrintMonitor(
        fake,
        l10n: () => lookupAppLocalizations(const Locale('en')),
        clock: () => DateTime(2026, 6, 12, 20, 0),
      );

  test('entering a print shows the ongoing notification once; a repeat throttles',
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
    // 20:00 + 80 min → a finish time of 21:20 (not "in X").
    expect(fake.lastBody, contains('ETA 21:20'));

    // The same frame (no change in %/ETA) → no extra update.
    m.update(Map.of(frame));
    expect(fake.ongoingCount, 1);
  });

  test('a progress change updates the notification', () {
    final fake = _FakeNotifications();
    final m = monitor(fake);
    m.update({1: _status(state: 'RUNNING', progress: 42, remaining: 80)});
    m.update({1: _status(state: 'RUNNING', progress: 43, remaining: 79)});
    expect(fake.ongoingCount, 2);
    expect(fake.lastProgress, 43);
  });

  test('RUNNING → FINISH: one "finished" alert and a clean-up', () {
    final fake = _FakeNotifications();
    final m = monitor(fake);
    m.update({1: _status(state: 'RUNNING', progress: 99, remaining: 1, job: 'x')});
    m.update({1: _status(state: 'FINISH', progress: 100, remaining: 0, job: 'x')});

    expect(fake.alerts.length, 1);
    expect(fake.alerts.single['title'], 'Print finished');
    expect(fake.alerts.single['body'], 'x is done');
    expect(fake.clearCount, greaterThanOrEqualTo(1));

    // Further FINISH frames do not fire the alert again.
    m.update({1: _status(state: 'FINISH', progress: 100, remaining: 0, job: 'x')});
    expect(fake.alerts.length, 1);
  });

  test('RUNNING → FAILED: a "failed" alert', () {
    final fake = _FakeNotifications();
    final m = monitor(fake);
    m.update({1: _status(state: 'RUNNING', progress: 30, remaining: 50, job: 'y')});
    m.update({1: _status(state: 'FAILED', progress: 30, remaining: 0, job: 'y')});
    expect(fake.alerts.single['title'], 'Print failed');
    expect(fake.alerts.single['body'], 'y failed');
  });

  test('two printers: the ongoing one tracks the nearest ETA, with a +1 note', () {
    final fake = _FakeNotifications();
    final m = monitor(fake);
    m.update({
      1: _status(id: 1, state: 'RUNNING', progress: 10, remaining: 200, job: 'long'),
      2: _status(id: 2, state: 'RUNNING', progress: 80, remaining: 15, job: 'soon'),
    });
    expect(fake.lastTitle, 'soon'); // finishes soonest
    expect(fake.lastProgress, 80);
    expect(fake.lastBody, contains('+1'));
  });

  test('the end of every print clears the ongoing notification', () {
    final fake = _FakeNotifications();
    final m = monitor(fake);
    m.update({1: _status(state: 'RUNNING', progress: 50, remaining: 30)});
    expect(fake.clearCount, 0);
    m.update({1: _status(state: 'IDLE', progress: 0, remaining: 0)});
    expect(fake.clearCount, 1);
  });

  // --- New events (all enabled) ---

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

  // Alerts of one type share an id per printer; the band is computed the way
  // production does it, so the test does not pin itself to its width.
  int bandId(int band, [int printerId = 1]) =>
      band * alertBandWidth + printerId;

  // The last alert with a given id (alerts of the same type share an id per
  // printer — on the device a new one replaces the old; here the fake keeps all).
  Map<String, Object?>? alertById(_FakeNotifications fake, int id) {
    Map<String, Object?>? found;
    for (final a in fake.alerts) {
      if (a['id'] == id) found = a;
    }
    return found;
  }

  // HMS error alerts: the id is now unique per (printer, code), so we look them
  // up by title rather than by a fixed id. Each has its own id, so several
  // concurrent faults produce several separate notifications (different ids).
  final errorTitle = lookupAppLocalizations(const Locale('en')).notifErrorTitle;
  List<Map<String, Object?>> errorAlerts(_FakeNotifications fake) =>
      [for (final a in fake.alerts) if (a['title'] == errorTitle) a];

  test('starting a print fires the "started" alert (when enabled)', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake);
    m.update({1: _status(state: 'IDLE')});
    expect(alertById(fake, bandId(3)), isNull);
    m.update({1: _status(state: 'RUNNING', job: 'cube.3mf')});
    expect(alertById(fake, bandId(3))?['title'], 'Print started');
  });

  test('first layer DONE: alerts once, only when layer_num reaches 2', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake);
    m.update({1: _status(state: 'RUNNING', job: 'x', layerNum: 0)});
    expect(alertById(fake, bandId(4)), isNull);
    // Layer 1 only STARTED — not finished yet, no alert.
    m.update({1: _status(state: 'RUNNING', job: 'x', layerNum: 1)});
    expect(alertById(fake, bandId(4)), isNull);
    // Layer 2 → layer 1 is complete (parity with bambuddy's layer_num ≥ 2).
    m.update({1: _status(state: 'RUNNING', job: 'x', layerNum: 2)});
    expect(alertById(fake, bandId(4)), isNotNull);
    fake.alerts.clear();
    m.update({1: _status(state: 'RUNNING', job: 'x', layerNum: 3)});
    expect(alertById(fake, bandId(4)), isNull); // no repeat
  });

  test('milestones: 25/50/75 once each', () {
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
    expect(fake.alerts, isEmpty); // nothing new was crossed
  });

  test('milestones: the prep-phase percentage does not fire the thresholds', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake);
    // Calibration reports its own percentage at layer_num == 0 — an observed jump
    // of 6 → 60 in 300 ms crossed 25 and 50 before the first layer.
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 6, layerNum: 0)});
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 60, layerNum: 0)});
    expect(fake.alerts.where((a) => a['id'] == 5001), isEmpty);
    // The print really starts: the percentage counts from zero and the thresholds
    // work normally.
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 5, layerNum: 1)});
    expect(fake.alerts.where((a) => a['id'] == 5001), isEmpty);
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 30, layerNum: 8)});
    expect(alertById(fake, bandId(5))?['title'], '25% printed');
  });

  test('milestones: priming on a calibration frame does not eat the thresholds', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake);
    // The first frame is calibration at 60% — used as the baseline it would latch
    // 25 and 50 as sent and mute them for the whole real print.
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 60, layerNum: 0)});
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 30, layerNum: 8)});
    expect(alertById(fake, bandId(5))?['title'], '25% printed');
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 55, layerNum: 15)});
    expect(alertById(fake, bandId(5))?['title'], '50% printed');
  });

  test('milestones: priming mid-print still latches the thresholds', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake);
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 60, layerNum: 40)});
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 62, layerNum: 41)});
    expect(fake.alerts.where((a) => a['id'] == 5001), isEmpty);
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 80, layerNum: 55)});
    expect(alertById(fake, bandId(5))?['title'], '75% printed');
  });

  test('plate not empty: alerts from the WS plate_not_empty frame, not the status', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake);
    // The end of a print raises awaiting_plate_clear in the status — that must NOT
    // fire the alert (it is a queue gate, not object detection on the plate).
    m.update({1: _status(state: 'RUNNING', job: 'x')});
    m.update({1: _status(state: 'FINISH', awaitingPlateClear: true)});
    expect(alertById(fake, bandId(6)), isNull);
    // Only a separate WS frame fires the alert (with the printer name from it).
    m.onPlateNotEmpty(1, 'X1C');
    final alert = alertById(fake, bandId(6));
    expect(alert, isNotNull);
    expect(alert!['body'], contains('X1C'));
  });

  test('plate not empty: respects the event being disabled in prefs', () {
    final fake = _FakeNotifications();
    final m = monitor(fake); // default prefs: plateNotEmpty on, but…
    final off = PrintMonitor(
      fake,
      prefs: const NotificationPrefs(enabled: {}),
      l10n: () => lookupAppLocalizations(const Locale('en')),
      clock: () => DateTime(2026, 6, 12, 20, 0),
    );
    off.onPlateNotEmpty(1, 'X1C');
    expect(alertById(fake, bandId(6)), isNull);
    // sanity: the default monitor (plate on) does fire
    m.onPlateNotEmpty(1, 'X1C');
    expect(alertById(fake, bandId(6)), isNotNull);
  });

  test('offline: alerts only once the grace runs out; coming back online cancels it', () {
    final fake = _FakeNotifications();
    final timers = <_FakeTimer>[];
    final m = monitorAll(fake, timer: (d, cb) {
      final t = _FakeTimer(cb);
      timers.add(t);
      return t;
    });

    m.update({1: _status(state: 'IDLE', connected: true)});
    m.update({1: _status(state: 'IDLE', connected: false)});
    expect(alertById(fake, bandId(7)), isNull); // not yet — waiting on the grace
    expect(timers, hasLength(1));
    timers.single.fire();
    expect(alertById(fake, bandId(7))?['title'], 'Printer offline');

    // Second episode: offline, but back online before the grace runs out → no alert.
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
    timers2.single.fire(); // cancelled — no effect
    expect(alertById(fake2, 7001), isNull);
  });

  test('HMS fault: a new code alerts, a repeat does not; after the grace it alerts '
      'again',
      () {
    final fake = _FakeNotifications();
    var t = DateTime(2026, 6, 12, 20, 0);
    final m = monitorAll(fake, clock: () => t, hmsDescribe: describeAll);
    const err = HmsError(code: 'A', severity: 2);
    m.update({1: _status(state: 'RUNNING')}); // priming — no faults
    m.update({1: _status(state: 'RUNNING', hms: [err])});
    expect(errorAlerts(fake), hasLength(1));
    fake.alerts.clear();
    m.update({1: _status(state: 'RUNNING', hms: [err])});
    expect(errorAlerts(fake), isEmpty); // the same code
    // A short gap (< grace) and back → still the same fault, no second alert.
    m.update({1: _status(state: 'RUNNING', hms: const [])});
    t = t.add(const Duration(seconds: 5));
    m.update({1: _status(state: 'RUNNING', hms: [err])});
    expect(errorAlerts(fake), isEmpty);
    // A longer absence (> grace) → the code is forgotten, a new occurrence alerts.
    // Frames keep arriving throughout — silence across the whole feed is a
    // different situation and has its own test below.
    for (var i = 0; i < 4; i++) {
      t = t.add(const Duration(seconds: 10));
      m.update({1: _status(state: 'RUNNING', hms: const [])});
    }
    m.update({1: _status(state: 'RUNNING', hms: [err])});
    expect(errorAlerts(fake), hasLength(1));
  });

  test('HMS fault: silence in the feed does not clear the memory — a reconnect '
      'does not alert again', () {
    final fake = _FakeNotifications();
    var t = DateTime(2026, 6, 12, 20, 0);
    final m = monitorAll(fake, clock: () => t, hmsDescribe: describeAll);
    const err = HmsError(code: 'A', severity: 2);

    m.update({1: _status(state: 'RUNNING')}); // priming
    m.update({1: _status(state: 'RUNNING', hms: [err])});
    expect(errorAlerts(fake), hasLength(1));
    fake.alerts.clear();

    // The socket dies and nothing arrives for two minutes. The socket watchdog is
    // longer than the grace, so every detected drop looks exactly like this — and
    // the fault still stands, because the first frame back still carries it.
    t = t.add(const Duration(minutes: 2));
    m.update({1: _status(state: 'RUNNING', hms: [err])});

    expect(errorAlerts(fake), isEmpty);
  });

  test('HMS fault: an offline printer does not alert; a code known from before the '
      'disconnect does not alert on return, a fresh one does', () {
    final fake = _FakeNotifications();
    var t = DateTime(2026, 6, 12, 20, 0);
    final m = monitorAll(fake, clock: () => t, hmsDescribe: describeAll);
    const err = HmsError(code: 'A', severity: 2);
    const other = HmsError(code: 'B', severity: 3);
    // Online with fault A → one alert (the edge). Remembered afterwards.
    m.update({1: _status(state: 'IDLE', connected: true)}); // priming
    m.update({1: _status(state: 'IDLE', connected: true, hms: [err])});
    expect(errorAlerts(fake), hasLength(1));
    fake.alerts.clear();
    // Offline: mergedWith carries the old hms_errors forward — no alert even
    // though the code "vanished and came back", and even though the grace elapsed
    // (the memory is frozen).
    m.update({1: _status(state: 'IDLE', connected: false, hms: const [])});
    t = t.add(const Duration(seconds: 60));
    m.update({1: _status(state: 'IDLE', connected: false, hms: [err])});
    expect(errorAlerts(fake), isEmpty);
    // Back online: the same code A from before the disconnect does NOT alert again…
    m.update({1: _status(state: 'IDLE', connected: true, hms: [err])});
    expect(errorAlerts(fake), isEmpty);
    // …but a genuinely new code B after the return does.
    m.update({1: _status(state: 'IDLE', connected: true, hms: [err, other])});
    expect(errorAlerts(fake), hasLength(1));
  });

  test('an HMS fault first seen after the disconnect alerts on return', () {
    final fake = _FakeNotifications();
    var t = DateTime(2026, 6, 12, 20, 0);
    final m = monitorAll(fake, clock: () => t, hmsDescribe: describeAll);
    const err = HmsError(code: 'A', severity: 2);

    m.update({1: _status(state: 'RUNNING', connected: true)}); // priming
    // The fault appears in the very frame where the printer disappears — nobody has
    // reported it yet, so remembering it would mute it forever.
    m.update({1: _status(state: 'RUNNING', connected: false, hms: [err])});
    expect(errorAlerts(fake), isEmpty);

    // A second printer keeps sending frames: each one also grinds through the
    // first printer's state, so the grace would never elapse if the code were
    // latched.
    for (var i = 0; i < 3; i++) {
      t = t.add(const Duration(seconds: 45));
      m.update({1: _status(state: 'RUNNING', connected: false, hms: [err])});
    }
    expect(errorAlerts(fake), isEmpty);

    // The printer comes back still carrying that fault — now the user must hear
    // about it.
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

  test('HMS fault: several new codes in one frame → separate alerts (different '
      'ids)',
      () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake, hmsDescribe: describeAll);
    const a = HmsError(code: 'A', severity: 2);
    const b = HmsError(code: 'B', severity: 3);
    m.update({1: _status(state: 'RUNNING')}); // priming
    m.update({1: _status(state: 'RUNNING', hms: [a, b])});
    final alerts = errorAlerts(fake);
    expect(alerts, hasLength(2)); // both codes, none lost
    expect(alerts.map((e) => e['id']).toSet(), hasLength(2)); // different ids
  });

  test('HMS fault: a code with no known description is skipped (bambuddy parity)', () {
    final fake = _FakeNotifications();
    // No description resolver → an undocumented code; same for X2D sev 6 noise.
    final m = monitorAll(fake);
    m.update({1: _status(state: 'RUNNING')});
    m.update({
      1: _status(state: 'RUNNING', hms: [
        const HmsError(code: 'A', severity: 2), // documented severity, no description
        const HmsError(code: '0x20070', attr: 83887616, module: 5, severity: 6),
      ]),
    });
    expect(errorAlerts(fake), isEmpty); // nothing without a description alerts
  });

  test('HMS fault: a server-side description is enough even without the catalog', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake); // no catalog resolver
    m.update({1: _status(state: 'RUNNING')});
    m.update({
      1: _status(state: 'RUNNING', hms: [
        const HmsError(code: 'A', severity: 2, message: 'Filament runout'),
      ]),
    });
    expect(errorAlerts(fake), hasLength(1));
  });

  test('HMS fault: a cancel echo (0500_400E) does not alert', () {
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

  test('low filament: hysteresis per tray', () {
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
    expect(alertById(fake, bandId(9)), isNull); // still low — no spam
    m.update({1: _status(state: 'RUNNING', ams: unitFull)}); // reset
    m.update({1: _status(state: 'RUNNING', ams: unitLow)});
    expect(alertById(fake, bandId(9)), isNotNull); // dropped again
  });

  test('high AMS humidity: the edge above the threshold', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake);
    m.update({1: _status(state: 'IDLE', ams: [const AmsUnit(id: 0, humidity: 40)])});
    expect(alertById(fake, bandId(10)), isNull);
    m.update({1: _status(state: 'IDLE', ams: [const AmsUnit(id: 0, humidity: 70)])});
    expect(alertById(fake, bandId(10)), isNotNull);
  });

  test('AMS humidity: two units crossing in one frame report the worse reading',
      () {
    // There is one humidity notification per printer, so the frame that latches
    // both units has to spend it on the wetter one — the other is latched too and
    // stays quiet for the whole cooldown, so an under-reported value is not
    // corrected later.
    final fake = _FakeNotifications();
    final m = monitorAll(fake);

    m.update({
      1: _status(state: 'IDLE', ams: [
        const AmsUnit(id: 0, humidity: 40),
        const AmsUnit(id: 1, humidity: 40),
      ]),
    });
    m.update({
      1: _status(state: 'IDLE', ams: [
        const AmsUnit(id: 0, humidity: 88),
        const AmsUnit(id: 1, humidity: 65),
      ]),
    });

    expect(alertById(fake, bandId(10))?['body'], contains('88'));
  });

  test('AMS humidity: jitter around the threshold does not ring on every crossing',
      () {
    // The server looks every five minutes, we look at every frame — roughly once a
    // second. A reading sitting on the threshold crosses it endlessly.
    final fake = _FakeNotifications();
    var t = DateTime(2026, 6, 12, 20, 0);
    final m = monitorAll(fake, clock: () => t);
    AmsUnit at(int h) => AmsUnit(id: 0, humidity: h);

    m.update({1: _status(state: 'IDLE', ams: [at(50)])}); // priming
    m.update({1: _status(state: 'IDLE', ams: [at(61)])});
    expect(fake.alerts, hasLength(1));

    for (final h in [60, 61, 59, 61, 58, 61]) {
      t = t.add(const Duration(seconds: 5));
      m.update({1: _status(state: 'IDLE', ams: [at(h)])});
    }

    expect(fake.alerts, hasLength(1), reason: 'still the same damp spool');
  });

  test('AMS humidity: a real drop re-arms it, but no more than once an hour', () {
    final fake = _FakeNotifications();
    var t = DateTime(2026, 6, 12, 20, 0);
    final m = monitorAll(fake, clock: () => t);
    AmsUnit at(int h) => AmsUnit(id: 0, humidity: h);

    m.update({1: _status(state: 'IDLE', ams: [at(50)])}); // priming
    m.update({1: _status(state: 'IDLE', ams: [at(61)])});
    expect(fake.alerts, hasLength(1));

    // It went under the band (60 − 3), so the latch releases — but the hour is not
    // up yet, so a fresh rise is only recorded.
    m.update({1: _status(state: 'IDLE', ams: [at(56)])});
    t = t.add(const Duration(minutes: 20));
    m.update({1: _status(state: 'IDLE', ams: [at(70)])});
    expect(fake.alerts, hasLength(1), reason: 'cooldown');

    // An hour after the first alert the same situation is worth a word again.
    m.update({1: _status(state: 'IDLE', ams: [at(56)])});
    t = t.add(const Duration(minutes: 45));
    m.update({1: _status(state: 'IDLE', ams: [at(70)])});
    expect(fake.alerts, hasLength(2));
  });

  test('AMS humidity: a rise muted by the cooldown is deferred, not lost', () {
    final fake = _FakeNotifications();
    var t = DateTime(2026, 6, 12, 20, 0);
    final m = monitorAll(fake, clock: () => t);
    AmsUnit at(int h) => AmsUnit(id: 0, humidity: h);

    m.update({1: _status(state: 'IDLE', ams: [at(50)])}); // priming
    m.update({1: _status(state: 'IDLE', ams: [at(61)])});
    expect(fake.alerts, hasLength(1));

    // A drop under the band, then a rise still inside the cooldown → silence, but
    // the latch is already set.
    m.update({1: _status(state: 'IDLE', ams: [at(56)])});
    t = t.add(const Duration(minutes: 10));
    m.update({1: _status(state: 'IDLE', ams: [at(70)])});
    expect(fake.alerts, hasLength(1));

    // And it never comes down again. The latch must not eat an alert nobody ever
    // said out loud — once the hour is up, it is owed.
    for (var i = 0; i < 3; i++) {
      t = t.add(const Duration(minutes: 20));
      m.update({1: _status(state: 'IDLE', ams: [at(70)])});
    }

    expect(fake.alerts, hasLength(2));
  });

  test('AMS humidity: a steady high reading says it once, not every hour', () {
    // A deliberate difference from the server, which reminds every hour: here every
    // other event alerts on the edge, not off a clock.
    final fake = _FakeNotifications();
    var t = DateTime(2026, 6, 12, 20, 0);
    final m = monitorAll(fake, clock: () => t);
    AmsUnit at(int h) => AmsUnit(id: 0, humidity: h);

    m.update({1: _status(state: 'IDLE', ams: [at(50)])}); // priming
    m.update({1: _status(state: 'IDLE', ams: [at(70)])});
    expect(fake.alerts, hasLength(1));

    for (var i = 0; i < 5; i++) {
      t = t.add(const Duration(minutes: 30));
      m.update({1: _status(state: 'IDLE', ams: [at(70)])});
    }

    expect(fake.alerts, hasLength(1));
  });

  test('bed cooled: only after a finished print and below the threshold', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake);
    // A cold bed with no print before it → no alert.
    m.update({1: _status(state: 'IDLE', temps: {'bed': 25})});
    expect(alertById(fake, bandId(11)), isNull);
    // A print and its end arm the wait for the cool-down.
    m.update({1: _status(state: 'RUNNING', job: 'x', temps: {'bed': 60})});
    m.update({1: _status(state: 'FINISH', job: 'x', temps: {'bed': 60})});
    expect(alertById(fake, bandId(11)), isNull); // still hot
    m.update({1: _status(state: 'FINISH', job: 'x', temps: {'bed': 30})});
    expect(alertById(fake, bandId(11))?['title'], 'Bed cooled');
  });

  test('priming: the first frame mid-flight does NOT fire past events', () {
    final fake = _FakeNotifications();
    final m = monitorAll(fake);
    // A fresh monitor (as after the background isolate restarts) meets the printer
    // already 38% into a print, past the first layer, with a standing HMS fault and
    // low filament — none of those events should fire.
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
    expect(fake.alerts, isEmpty); // only the ongoing progress, no alerts
    expect(fake.ongoingCount, 1);

    // But a real edge after priming does work: 50% crossed.
    m.update({1: _status(state: 'RUNNING', progress: 55, layerNum: 30)});
    expect(alertById(fake, bandId(5))?['title'], '50% printed');
  });

  test('gating: default prefs let through neither "started" nor milestones', () {
    final fake = _FakeNotifications();
    final m = monitor(fake); // default prefs
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 30)});
    expect(alertById(fake, bandId(3)), isNull); // started OFF
    expect(alertById(fake, bandId(5)), isNull); // milestones OFF
  });

  // --- Tor diagnostyczny (src:notif) ---

  group('diagnostics', () {
    late DiagnosticRecorder recorder;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      recorder = DiagnosticRecorder(
        settings: SettingsRepository(await SharedPreferences.getInstance()),
        loadFacts: () async =>
            const SessionFacts(app: '0.11.3+1103', flavor: 'mobile'),
        // Memory instead of disk: we check the records, not a mirror on a file.
        resolveDirectory: () async => null,
      );
    });

    // Resets the `DiagnosticRecorder.active` static between tests.
    tearDown(() => recorder.discard());

    /// Uruchamia nagrywanie, wykonuje [body] i zwraca surowy JSONL sesji.
    Future<String> raw(FutureOr<void> Function() body) async {
      await recorder.start();
      await body();
      return recorder.stop();
    }

    /// The notification-path records alone, in write order.
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

    /// A monitor that writes to the log: a decorator over the fake service.
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

    test('first layer disabled: one record, not one per frame', () async {
      // The `_on` gate was evaluated per frame, so a record inside the condition
      // would give one entry per frame until the print ended.
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

    test('milestones disabled: one record per threshold', () async {
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

    test('prep phase: one record per print, not one per frame', () async {
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

      // Asserted on the raw text, not on parsed fields: a new nested field must not
      // slip past the test.
      expect(jsonl, isNot(contains('secret-model')));
      expect(jsonl, isNot(contains('Kitchen')));
      expect(only(await rows(() {}), 'posted'), isEmpty); // sanity
    });

    test('a posted alert carries the type, the printer and our id', () async {
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

    test('an HMS alert carries the printer, even though its id is a hash', () async {
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

    test('a platform rejection gives the exception class, not the message',
        () async {
      // The decorator is checked directly: the exception is **rethrown** so it does
      // not vanish from the isolate, so going through the monitor (which does not
      // await the future) it would surface as an unhandled error and fail the test.
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
      // The platform exception's message is not under our control, and the only
      // strings in this method's reach are the title and the body.
      expect(error.containsKey('msg'), isFalse);
      expect(jsonEncode(error), isNot(contains('secret-model')));
    });

    test('progress notification: a record per content change, not per frame', () async {
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
      // The same branch eats the maintenance reminder — that is what the record says.
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

    test('priming records a baseline that implies nothing', () async {
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
      // The first frame fires nothing — that is the whole content of this record.
      expect(only(all, 'posted'), isEmpty);
      expect(only(all, 'suppressed'), isEmpty);
    });

    test('HMS: the reasons are kept apart, and a known code stays silent', () async {
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

    test('HMS on a disconnected printer: reason offline, not typeOff', () async {
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

    test('a printer returning before the grace runs out leaves a trace', () async {
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
        m.update({1: _status(connected: true)}); // back before it fires
        m.update({1: _status(connected: true)}); // bez timera → bez rekordu
      });

      final skips = only(all, 'suppressed');
      expect(skips, hasLength(1));
      expect(skips.single['reason'], 'reconnected');
      expect(timers.single.isActive, isFalse);
    });

    test('the prefs snapshot lists the disabled types and the system state', () async {
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

    test('an unresponsive platform does not break the snapshot', () async {
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

/// A fake where the platform rejects every alert.
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
