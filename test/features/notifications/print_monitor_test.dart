import 'dart:async';
import 'dart:convert';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:bambuddy_mobile/core/diagnostics/notif_probe.dart';
import 'package:bambuddy_mobile/core/format/datetime_format.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/notifications/notification_prefs.dart';
import 'package:bambuddy_mobile/core/notifications/notification_service.dart';
import 'package:bambuddy_mobile/features/notifications/print_monitor.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';
import 'package:bambuddy_mobile/core/diagnostics/report_config.dart';

/// The instant every case here runs on: the ETAs in the assertions are spelled
/// from it, and the cases that care about elapsed time move on from it with
/// `time.tick`.
final _start = DateTime(2026, 6, 12, 20, 0);

PrinterStatus _status({
  int id = 1,
  String? state,
  double? progress,
  int? remaining,
  String? job,
  String? name,
  bool? connected,
  int? layerNum,
  int? stgCur,
  bool? awaitingPlateClear,
  List<HmsError>? hms,
  List<AmsUnit>? ams,
  List<AmsTray>? vtTray,
  Map<String, double>? temps,
}) => PrinterStatus(
  id: id,
  name: name,
  state: state,
  progress: progress,
  remainingTime: remaining,
  currentPrint: job,
  connected: connected,
  layerNum: layerNum,
  stgCur: stgCur,
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

/// Every event on — for testing individual detections.
const _allOn = NotificationPrefs(
  enabled: {
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
  },
);

void main() {
  // lookupAppLocalizations inside the monitor needs an initialised binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A case in this file, on the ambient clock pinned to [_start]. The monitor
  /// takes no clock of its own; a case that needs time to pass moves it with
  /// `time.tick`.
  void testAt(String description, dynamic Function(TestClock time) body) =>
      testWithClock(description, _start, body);

  // A pinned 24-hour formatter → a deterministic ETA time in the assertions,
  // independent of the host's own clock preference. The instant itself is
  // `_start`, installed as the ambient clock by `testWithClock`.
  PrintMonitor monitor(RecordingNotifications fake, {bool use24Hour = true}) =>
      PrintMonitor(
        fake,
        l10n: () => lookupAppLocalizations(const Locale('en')),
        formats: () =>
            DateTimeFormats.forTest(locale: 'en_US', use24Hour: use24Hour),
      );

  testAt(
    'entering a print shows the ongoing notification once; a repeat throttles',
    (_) {
      final fake = RecordingNotifications();
      final m = monitor(fake);

      final frame = {
        1: _status(
          state: 'RUNNING',
          progress: 42,
          remaining: 80,
          job: 'cube.3mf',
        ),
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
    },
  );

  testAt('the ongoing ETA follows the system clock preference', (_) {
    final fake = RecordingNotifications();
    monitor(fake, use24Hour: false).update({
      1: _status(
        state: 'RUNNING',
        progress: 42,
        remaining: 80,
        job: 'cube.3mf',
      ),
    });
    // Same 21:20 finish, spelled the way a 12-hour device spells it.
    expect(fake.lastBody, contains('ETA 9:20 PM'));
  });

  testAt('the service isolate spells the ETA on the clock the app published', (
    _,
  ) {
    // The regression, on the path that had it: built without a formatter, the
    // way the foreground service builds it. That isolate's engine is never told
    // what the 12/24-hour switch says, so it used to fall back to a 12-hour
    // clock and put `ETA 8:29 PM` on a phone that is set to 24 hours.
    DateTimeFormats.rememberSystemClock(true);
    addTearDown(() => DateTimeFormats.rememberSystemClock(null));

    final fake = RecordingNotifications();
    PrintMonitor(
      fake,
      l10n: () => lookupAppLocalizations(const Locale('en')),
    ).update({
      1: _status(
        state: 'RUNNING',
        progress: 42,
        remaining: 80,
        job: 'cube.3mf',
      ),
    });

    expect(fake.lastBody, contains('ETA 21:20'));
  });

  testAt('a progress change updates the notification', (_) {
    final fake = RecordingNotifications();
    final m = monitor(fake);
    m.update({1: _status(state: 'RUNNING', progress: 42, remaining: 80)});
    m.update({1: _status(state: 'RUNNING', progress: 43, remaining: 79)});
    expect(fake.ongoingCount, 2);
    expect(fake.lastProgress, 43);
  });

  group('several printers at once', () {
    // One notification, one print: the count is the headline, and the machine
    // that finishes first owns the bar, the line and the ETA. No second figure
    // for the shelf — the headline count already says there is more running.
    testAt('the headline counts, the bar and the line follow the lead', (_) {
      final fake = RecordingNotifications();
      final m = monitor(fake);
      m.update({
        1: _status(
          id: 1,
          state: 'RUNNING',
          progress: 40,
          remaining: 80,
          name: 'X1 Carbon',
        ),
        2: _status(
          id: 2,
          state: 'RUNNING',
          progress: 80,
          remaining: 12,
          name: 'P1S',
        ),
      });

      expect(fake.lastTitle, '2 printing');
      expect(fake.lastProgress, 80, reason: "the lead's own figure");
      // The lead is the one finishing first, and it is named by machine: with
      // two printers the job name no longer says which one this is.
      expect(fake.lastBody, contains('P1S (80%'));
      expect(fake.lastBody, contains('ETA'));
      // The same words the dashboard's chip uses, from the same string: under a
      // "2 printing" headline a bare machine name does not say why that one.
      expect(fake.lastBody, startsWith('Next available: '));
      // The other machine's 40% is nowhere in the notification, averaged or
      // otherwise: this notification is about one print.
      expect(fake.lastBody, isNot(contains('40')));
    });

    testAt('a printer that reports no progress does not draw a bar', (_) {
      final fake = RecordingNotifications();
      final m = monitor(fake);
      m.update({
        1: _status(id: 1, state: 'RUNNING', progress: 40, remaining: 80),
        2: _status(id: 2, state: 'RUNNING', remaining: 12, name: 'P1S'),
      });

      // The silent printer has the nearer ETA, so it leads — and a lead with no
      // measured position gets the indeterminate bar, not one pinned at zero.
      // The mean still exists for the log (`overall_pct`), where silence is left
      // out rather than counted as zero.
      expect(fake.lastProgress, isNull);
      expect(fake.lastIndeterminate, isTrue);
    });

    testAt('a printer reporting zero leads on its ETA, and its bar animates', (
      _,
    ) {
      final fake = RecordingNotifications();
      final m = monitor(fake);
      m.update({
        1: _status(id: 1, state: 'RUNNING', progress: 40, remaining: 80),
        2: _status(
          id: 2,
          state: 'RUNNING',
          progress: 0,
          remaining: 12,
          name: 'P1S',
        ),
      });

      // Twelve minutes against eighty, so P1S leads with its own zero. The text
      // still says 0% — that is where the print stands — but the bar has nothing
      // to draw, so it animates instead of sitting empty.
      expect(fake.lastBody, contains('P1S (0%'));
      expect(fake.lastProgress, isNull);
      expect(fake.lastIndeterminate, isTrue);
    });

    testAt('one machine out of range does not move the bar past 100', (_) {
      final fake = RecordingNotifications();
      final m = monitor(fake);
      m.update({
        1: _status(id: 1, state: 'RUNNING', progress: 40, remaining: 80),
        2: _status(
          id: 2,
          state: 'RUNNING',
          progress: 900,
          remaining: 12,
          name: 'P1S',
        ),
      });

      // A frame out of range is clamped, not passed through: the bar is a
      // fraction of 100 and 900 would leave it undrawable.
      expect(fake.lastProgress, 100);
    });

    testAt('a printer that is not the lead does not redraw the notification', (
      _,
    ) {
      final fake = RecordingNotifications();
      final m = monitor(fake);
      m.update({
        1: _status(id: 1, state: 'RUNNING', progress: 40, remaining: 80),
        2: _status(id: 2, state: 'RUNNING', progress: 80, remaining: 12),
      });
      expect(fake.ongoingCount, 1);

      // Printer 1 advanced twenty points, and not one of them is on screen: the
      // notification is the lead's, and the lead's frame is unchanged. Redrawing
      // here would re-post an identical notification on every WS frame.
      m.update({
        1: _status(id: 1, state: 'RUNNING', progress: 60, remaining: 70),
        2: _status(id: 2, state: 'RUNNING', progress: 80, remaining: 12),
      });
      expect(fake.ongoingCount, 1);
      expect(fake.lastProgress, 80);
    });

    testAt('dropping back to one printer restores the job as the headline', (
      _,
    ) {
      final fake = RecordingNotifications();
      final m = monitor(fake);
      m.update({
        1: _status(id: 1, state: 'RUNNING', progress: 40, remaining: 80),
        2: _status(id: 2, state: 'RUNNING', progress: 80, remaining: 12),
      });
      m.update({
        1: _status(
          id: 1,
          state: 'RUNNING',
          progress: 40,
          remaining: 80,
          job: 'cube.3mf',
        ),
        2: _status(id: 2, state: 'IDLE'),
      });

      expect(fake.lastTitle, 'cube.3mf');
      expect(fake.lastProgress, 40);
    });
  });

  // `remaining_time` is zero in three different situations and the server never
  // sends null for a printing machine (`PrinterState` defaults it to 0), so the
  // number alone cannot say which one this is. Progress is the second half of
  // the answer, and each group below pins one reading of the pair.
  group('a zero in remaining_time', () {
    testAt('heating does not take the lead from a print about to finish', (_) {
      final fake = RecordingNotifications();
      final m = monitor(fake);
      m.update({
        1: _status(
          id: 1,
          state: 'PREPARE',
          progress: 0,
          remaining: 0,
          name: 'X1 Carbon',
        ),
        2: _status(
          id: 2,
          state: 'RUNNING',
          progress: 87,
          remaining: 12,
          name: 'P1S',
        ),
      });

      // Sorted on the raw minutes, the heating machine's zero would put it in
      // front of the one twelve minutes from done.
      expect(fake.lastBody, contains('P1S (87%'));
      expect(fake.lastProgress, 87);
    });

    testAt('heating alone shows no ETA rather than the current time', (_) {
      final fake = RecordingNotifications();
      monitor(fake).update({
        1: _status(state: 'PREPARE', progress: 0, remaining: 0, job: 'cube'),
      });

      // The zero means "nothing estimated yet". Rendered as a clock it used to
      // put the current time on the notification as the finish time.
      expect(fake.lastBody, isNot(contains('ETA')));
      expect(fake.lastBody, isNot(contains('soon')));
    });

    testAt('the last minute of a print keeps the lead', (_) {
      final fake = RecordingNotifications();
      final m = monitor(fake);
      m.update({
        1: _status(
          id: 1,
          state: 'RUNNING',
          progress: 40,
          remaining: 80,
          name: 'X1 Carbon',
        ),
        2: _status(
          id: 2,
          state: 'RUNNING',
          progress: 99,
          remaining: 0,
          name: 'P1S',
        ),
      });

      // The same zero as the heating case above, and the opposite answer: this
      // one really is the next to finish.
      expect(fake.lastBody, contains('P1S (99%'));
      expect(fake.lastProgress, 99);
    });

    testAt('the last minute of a print reads "soon", not a clock time', (_) {
      final fake = RecordingNotifications();
      monitor(fake).update({
        1: _status(state: 'RUNNING', progress: 99, remaining: 0, job: 'cube'),
      });

      expect(fake.lastBody, contains('ETA soon'));
    });

    testAt('one printer, still heating: the bar animates, the ETA stays', (_) {
      final fake = RecordingNotifications();
      // Straight off a real phone: a single machine at 0% with an estimate
      // already reported. The bar used to sit empty across the full width and
      // read as "nothing is happening" on a printer that is heating its bed.
      monitor(fake).update({
        1: _status(
          state: 'RUNNING',
          progress: 0,
          remaining: 29,
          job: 'gridfinitystoragebox_5xy_handle',
        ),
      });

      expect(fake.lastProgress, isNull);
      expect(fake.lastIndeterminate, isTrue);
      // The estimate is a separate fact from the position, and it survives.
      expect(fake.lastBody, contains('0%'));
      expect(fake.lastBody, contains('ETA'));
    });

    testAt('the bar stops animating on the first measured percent', (_) {
      final fake = RecordingNotifications();
      final m = monitor(fake);
      m.update({1: _status(state: 'RUNNING', progress: 0, remaining: 29)});
      expect(fake.lastIndeterminate, isTrue);

      m.update({1: _status(state: 'RUNNING', progress: 1, remaining: 28)});
      expect(fake.lastProgress, 1);
      expect(fake.lastIndeterminate, isFalse);
    });

    testAt('a first layer keeps the estimate it already reported', (_) {
      final fake = RecordingNotifications();
      final m = monitor(fake);
      m.update({
        1: _status(
          id: 1,
          state: 'RUNNING',
          progress: 40,
          remaining: 80,
          name: 'X1 Carbon',
        ),
        2: _status(
          id: 2,
          state: 'RUNNING',
          progress: 0,
          remaining: 12,
          name: 'P1S',
        ),
      });

      // The third reading of a zero, and the one a rule written on
      // `isPreparing` alone gets wrong: zero percent with a real estimate is a
      // first layer, not a machine that has said nothing. Twelve minutes beats
      // eighty and the ETA is a clock time.
      expect(fake.lastBody, contains('P1S (0%'));
      expect(fake.lastBody, isNot(contains('soon')));
      expect(fake.lastBody, contains('ETA'));
    });
  });

  testAt('RUNNING → FINISH: one "finished" alert and a clean-up', (_) {
    final fake = RecordingNotifications();
    final m = monitor(fake);
    m.update({
      1: _status(state: 'RUNNING', progress: 99, remaining: 1, job: 'x'),
    });
    m.update({
      1: _status(state: 'FINISH', progress: 100, remaining: 0, job: 'x'),
    });

    expect(fake.alerts.length, 1);
    expect(fake.alerts.single['title'], 'Print finished');
    expect(fake.alerts.single['body'], 'x is done');
    expect(fake.clearCount, greaterThanOrEqualTo(1));

    // Further FINISH frames do not fire the alert again.
    m.update({
      1: _status(state: 'FINISH', progress: 100, remaining: 0, job: 'x'),
    });
    expect(fake.alerts.length, 1);
  });

  testAt('RUNNING → FAILED: a "failed" alert', (_) {
    final fake = RecordingNotifications();
    final m = monitor(fake);
    m.update({
      1: _status(state: 'RUNNING', progress: 30, remaining: 50, job: 'y'),
    });
    m.update({
      1: _status(state: 'FAILED', progress: 30, remaining: 0, job: 'y'),
    });
    expect(fake.alerts.single['title'], 'Print failed');
    expect(fake.alerts.single['body'], 'y failed');
  });

  testAt('two printers: the line and the bar both follow the nearest ETA', (_) {
    final fake = RecordingNotifications();
    final m = monitor(fake);
    m.update({
      1: _status(
        id: 1,
        state: 'RUNNING',
        progress: 10,
        remaining: 200,
        job: 'long',
        name: 'X1C',
      ),
      2: _status(
        id: 2,
        state: 'RUNNING',
        progress: 80,
        remaining: 15,
        job: 'soon',
        name: 'P1S',
      ),
    });

    expect(fake.lastBody, contains('P1S (80%')); // finishes soonest
    // The bar belongs to the same print as the line and the ETA.
    expect(fake.lastProgress, 80);
    expect(fake.lastTitle, '2 printing');
  });

  testAt('the end of every print clears the ongoing notification', (_) {
    final fake = RecordingNotifications();
    final m = monitor(fake);
    m.update({1: _status(state: 'RUNNING', progress: 50, remaining: 30)});
    expect(fake.clearCount, 0);
    m.update({1: _status(state: 'IDLE', progress: 0, remaining: 0)});
    expect(fake.clearCount, 1);
  });

  // --- New events (all enabled) ---

  PrintMonitor monitorAll(
    RecordingNotifications fake, {
    TimerFactory? timer,
    String? Function(HmsError)? hmsDescribe,
  }) => PrintMonitor(
    fake,
    prefs: _allOn,
    l10n: () => lookupAppLocalizations(const Locale('en')),
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
  Map<String, Object?>? alertById(RecordingNotifications fake, int id) {
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
  List<Map<String, Object?>> errorAlerts(RecordingNotifications fake) => [
    for (final a in fake.alerts)
      if (a['title'] == errorTitle) a,
  ];

  testAt('starting a print fires the "started" alert (when enabled)', (_) {
    final fake = RecordingNotifications();
    final m = monitorAll(fake);
    m.update({1: _status(state: 'IDLE')});
    expect(alertById(fake, bandId(3)), isNull);
    m.update({1: _status(state: 'RUNNING', job: 'cube.3mf')});
    expect(alertById(fake, bandId(3))?['title'], 'Print started');
  });

  testAt('first layer DONE: alerts once, only when layer_num reaches 2', (_) {
    final fake = RecordingNotifications();
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

  group('a print sent while the previous one is still on the wire', () {
    // The report this group exists for: a print finished, the next was sent,
    // and seconds later the watch announced the FIRST one's first layer.
    //
    // bambuddy's state is a rolling merge of the printer's partial MQTT
    // reports, so the frame that flips the printer back to RUNNING still
    // carries the finished job's name, layer and percentage — the printer has
    // not published the new job's yet. On top of that the firmware ticks
    // `layer_num` through the pre-print sequence (server #1837), so the
    // counter reaches 2 while the bed is still being scanned.

    /// Print A running past its first layer, then finishing there.
    void finishPrintA(PrintMonitor m, {required int layer}) {
      m.update({
        1: _status(
          state: 'RUNNING',
          job: 'A.3mf',
          layerNum: layer,
          progress: 90,
        ),
      });
      m.update({
        1: _status(
          state: 'FINISH',
          job: 'A.3mf',
          layerNum: layer,
          progress: 100,
        ),
      });
    }

    testAt("the finished job's layer does not announce a first layer", (_) {
      final fake = RecordingNotifications();
      final m = monitorAll(fake);
      // A ends on layer 8 — inside the [2, 10] window, so the window alone
      // would not save this.
      finishPrintA(m, layer: 8);
      fake.alerts.clear();

      // B is dispatched: RUNNING again, every job number on the wire still A's.
      m.update({
        1: _status(state: 'RUNNING', job: 'A.3mf', layerNum: 8, progress: 100),
      });
      expect(
        alertById(fake, bandId(4)),
        isNull,
        reason: 'nothing about B has arrived yet',
      );
      m.update({
        1: _status(state: 'RUNNING', job: 'A.3mf', layerNum: 8, progress: 100),
      });
      expect(alertById(fake, bandId(4)), isNull);

      // The printer finally publishes B, from its layer 0.
      m.update({
        1: _status(state: 'RUNNING', job: 'B.3mf', layerNum: 0, progress: 0),
      });
      expect(alertById(fake, bandId(4)), isNull);
      m.update({
        1: _status(state: 'RUNNING', job: 'B.3mf', layerNum: 2, progress: 1),
      });
      expect(
        alertById(fake, bandId(4))?['body'],
        contains('B.3mf'),
        reason: "B's own first layer, under B's own name",
      );
    });

    testAt('a layer ticked by the pre-print sequence is not the first layer', (
      _,
    ) {
      final fake = RecordingNotifications();
      final m = monitorAll(fake);
      finishPrintA(m, layer: 8);
      fake.alerts.clear();

      // Dispatch, then the pre-print sequence ticking layers: bed scan (9) and
      // nozzle cleaning (14). The name on the wire is still A's, which is what
      // the reported notification showed.
      m.update({
        1: _status(state: 'RUNNING', job: 'A.3mf', layerNum: 8, progress: 100),
      });
      m.update({
        1: _status(state: 'RUNNING', job: 'A.3mf', layerNum: 2, stgCur: 9),
      });
      expect(alertById(fake, bandId(4)), isNull);
      m.update({
        1: _status(state: 'RUNNING', job: 'A.3mf', layerNum: 3, stgCur: 14),
      });
      expect(alertById(fake, bandId(4)), isNull);

      // Stage 0 is "Printing": the alert was owed, not lost, and it names B.
      m.update({
        1: _status(state: 'RUNNING', job: 'B.3mf', layerNum: 3, stgCur: 0),
      });
      expect(alertById(fake, bandId(4))?['body'], contains('B.3mf'));
    });

    testAt('a counter far past the first layer is not news', (_) {
      final fake = RecordingNotifications();
      final m = monitorAll(fake);
      // The same window bambuddy uses: [2, 10]. Above it the number belongs to
      // a print we joined halfway or to the one that just ended.
      finishPrintA(m, layer: 40);
      fake.alerts.clear();
      m.update({
        1: _status(state: 'RUNNING', job: 'A.3mf', layerNum: 40, progress: 100),
      });
      m.update({
        1: _status(state: 'RUNNING', job: 'B.3mf', layerNum: 40, stgCur: 0),
      });
      expect(alertById(fake, bandId(4)), isNull);
    });

    testAt('a server that reports no stage still gets the alert', (_) {
      final fake = RecordingNotifications();
      final m = monitorAll(fake);
      // `stg_cur` has been in every status the server sends since v0.1.6, older
      // than any version this app talks to — but a frame without it must keep
      // working: null is "no stage reported", not "preparing".
      m.update({1: _status(state: 'IDLE')});
      m.update({1: _status(state: 'RUNNING', job: 'x', layerNum: 0)});
      m.update({1: _status(state: 'RUNNING', job: 'x', layerNum: 2)});
      expect(alertById(fake, bandId(4)), isNotNull);
    });

    testAt("the finished job's percentage does not fire milestones", (_) {
      final fake = RecordingNotifications();
      final m = monitorAll(fake);
      // The other half of the same stale frame: 100% from the print that just
      // came off the plate would cross all three thresholds at once.
      finishPrintA(m, layer: 5);
      fake.alerts.clear();
      m.update({
        1: _status(state: 'RUNNING', job: 'A.3mf', layerNum: 5, progress: 100),
      });
      expect(fake.alerts.where((a) => a['id'] == bandId(5)), isEmpty);

      m.update({
        1: _status(state: 'RUNNING', job: 'B.3mf', layerNum: 1, progress: 0),
      });
      m.update({
        1: _status(state: 'RUNNING', job: 'B.3mf', layerNum: 9, progress: 30),
      });
      expect(
        alertById(fake, bandId(5))?['title'],
        '25% printed',
        reason: "B's own thresholds still work",
      );
    });

    // The same race seen by a monitor that is *born* into it. The background
    // isolate is rebuilt on every entry into the background, so the first frame
    // this monitor ever sees — the one it primes from, firing nothing — can be
    // the stale one. Priming records the printer as already printing, so no
    // print-start edge follows to clear a latch set from that frame.
    testAt(
      "a monitor primed mid-dispatch still announces the new print's first layer",
      (_) {
        final fake = RecordingNotifications();
        final m = monitorAll(fake);
        // Layer 3 with the bed being scanned (stage 9), under A's name: the
        // pre-print sequence of B, described with what is left of A.
        m.update({
          1: _status(state: 'RUNNING', job: 'A.3mf', layerNum: 3, stgCur: 9),
        });
        m.update({
          1: _status(state: 'RUNNING', job: 'B.3mf', layerNum: 2, stgCur: 0),
        });
        expect(
          alertById(fake, bandId(4))?['body'],
          contains('B.3mf'),
          reason: 'the baseline may not spend an alert this print is owed',
        );
      },
    );

    testAt('a monitor primed mid-dispatch keeps the new thresholds', (_) {
      final fake = RecordingNotifications();
      final m = monitorAll(fake);
      // A's 100% as a baseline would latch all three thresholds at once.
      m.update({
        1: _status(
          state: 'RUNNING',
          job: 'A.3mf',
          layerNum: 3,
          progress: 100,
          stgCur: 9,
        ),
      });
      m.update({
        1: _status(
          state: 'RUNNING',
          job: 'B.3mf',
          layerNum: 4,
          progress: 30,
          stgCur: 0,
        ),
      });
      expect(alertById(fake, bandId(5))?['title'], '25% printed');
    });

    testAt(
      'a stage entered mid-print holds a threshold back, it does not drop it',
      (_) {
        final fake = RecordingNotifications();
        final m = monitorAll(fake);
        m.update({1: _status(state: 'IDLE')});
        m.update({
          1: _status(
            state: 'RUNNING',
            job: 'B.3mf',
            layerNum: 5,
            progress: 10,
            stgCur: 0,
          ),
        });
        // 25% is crossed during a filament change (stage 4). The gate does not
        // distinguish this from the pre-print sequence, so the crossing waits —
        // the accepted price of the frame that fired three thresholds off a stale
        // 100%.
        m.update({
          1: _status(
            state: 'RUNNING',
            job: 'B.3mf',
            layerNum: 30,
            progress: 26,
            stgCur: 4,
          ),
        });
        expect(fake.alerts.where((a) => a['id'] == bandId(5)), isEmpty);
        // Nothing latched while it waited, so the alert is still owed once the
        // printer is laying plastic again.
        m.update({
          1: _status(
            state: 'RUNNING',
            job: 'B.3mf',
            layerNum: 31,
            progress: 27,
            stgCur: 0,
          ),
        });
        expect(alertById(fake, bandId(5))?['title'], '25% printed');
      },
    );
  });

  testAt('milestones: 25/50/75 once each', (_) {
    final fake = RecordingNotifications();
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

  testAt('milestones: the prep-phase percentage does not fire the thresholds', (
    _,
  ) {
    final fake = RecordingNotifications();
    final m = monitorAll(fake);
    // Calibration reports its own percentage at layer_num == 0 — an observed jump
    // of 6 → 60 in 300 ms crossed 25 and 50 before the first layer.
    m.update({
      1: _status(state: 'RUNNING', job: 'x', progress: 6, layerNum: 0),
    });
    m.update({
      1: _status(state: 'RUNNING', job: 'x', progress: 60, layerNum: 0),
    });
    expect(fake.alerts.where((a) => a['id'] == 5001), isEmpty);
    // The print really starts: the percentage counts from zero and the thresholds
    // work normally.
    m.update({
      1: _status(state: 'RUNNING', job: 'x', progress: 5, layerNum: 1),
    });
    expect(fake.alerts.where((a) => a['id'] == 5001), isEmpty);
    m.update({
      1: _status(state: 'RUNNING', job: 'x', progress: 30, layerNum: 8),
    });
    expect(alertById(fake, bandId(5))?['title'], '25% printed');
  });

  testAt(
    'milestones: priming on a calibration frame does not eat the thresholds',
    (_) {
      final fake = RecordingNotifications();
      final m = monitorAll(fake);
      // The first frame is calibration at 60% — used as the baseline it would latch
      // 25 and 50 as sent and mute them for the whole real print.
      m.update({
        1: _status(state: 'RUNNING', job: 'x', progress: 60, layerNum: 0),
      });
      m.update({
        1: _status(state: 'RUNNING', job: 'x', progress: 30, layerNum: 8),
      });
      expect(alertById(fake, bandId(5))?['title'], '25% printed');
      m.update({
        1: _status(state: 'RUNNING', job: 'x', progress: 55, layerNum: 15),
      });
      expect(alertById(fake, bandId(5))?['title'], '50% printed');
    },
  );

  testAt('milestones: priming mid-print still latches the thresholds', (_) {
    final fake = RecordingNotifications();
    final m = monitorAll(fake);
    m.update({
      1: _status(state: 'RUNNING', job: 'x', progress: 60, layerNum: 40),
    });
    m.update({
      1: _status(state: 'RUNNING', job: 'x', progress: 62, layerNum: 41),
    });
    expect(fake.alerts.where((a) => a['id'] == 5001), isEmpty);
    m.update({
      1: _status(state: 'RUNNING', job: 'x', progress: 80, layerNum: 55),
    });
    expect(alertById(fake, bandId(5))?['title'], '75% printed');
  });

  testAt(
    'plate not empty: alerts from the WS plate_not_empty frame, not the status',
    (_) {
      final fake = RecordingNotifications();
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
    },
  );

  testAt('plate not empty: respects the event being disabled in prefs', (_) {
    final fake = RecordingNotifications();
    final m = monitor(fake); // default prefs: plateNotEmpty on, but…
    final off = PrintMonitor(
      fake,
      prefs: const NotificationPrefs(enabled: {}),
      l10n: () => lookupAppLocalizations(const Locale('en')),
    );
    off.onPlateNotEmpty(1, 'X1C');
    expect(alertById(fake, bandId(6)), isNull);
    // sanity: the default monitor (plate on) does fire
    m.onPlateNotEmpty(1, 'X1C');
    expect(alertById(fake, bandId(6)), isNotNull);
  });

  testAt(
    'offline: alerts only once the grace runs out; coming back online cancels it',
    (_) {
      final fake = RecordingNotifications();
      final timers = <FakeTimer>[];
      final m = monitorAll(
        fake,
        timer: (d, cb) {
          final t = FakeTimer(Duration.zero, cb);
          timers.add(t);
          return t;
        },
      );

      m.update({1: _status(state: 'IDLE', connected: true)});
      m.update({1: _status(state: 'IDLE', connected: false)});
      expect(
        alertById(fake, bandId(7)),
        isNull,
      ); // not yet — waiting on the grace
      expect(timers, hasLength(1));
      timers.single.fire();
      expect(alertById(fake, bandId(7))?['title'], 'Printer offline');

      // Second episode: offline, but back online before the grace runs out → no alert.
      final fake2 = RecordingNotifications();
      final timers2 = <FakeTimer>[];
      final m2 = monitorAll(
        fake2,
        timer: (d, cb) {
          final t = FakeTimer(Duration.zero, cb);
          timers2.add(t);
          return t;
        },
      );
      m2.update({1: _status(state: 'IDLE', connected: true)});
      m2.update({1: _status(state: 'IDLE', connected: false)});
      m2.update({1: _status(state: 'IDLE', connected: true)});
      timers2.single.fire(); // cancelled — no effect
      expect(alertById(fake2, 7001), isNull);
    },
  );

  testAt(
    'HMS fault: a new code alerts, a repeat does not; after the grace it alerts '
    'again',
    (time) {
      final fake = RecordingNotifications();
      final m = monitorAll(fake, hmsDescribe: describeAll);
      const err = HmsError(code: 'A', severity: 2);
      m.update({1: _status(state: 'RUNNING')}); // priming — no faults
      m.update({
        1: _status(state: 'RUNNING', hms: [err]),
      });
      expect(errorAlerts(fake), hasLength(1));
      fake.alerts.clear();
      m.update({
        1: _status(state: 'RUNNING', hms: [err]),
      });
      expect(errorAlerts(fake), isEmpty); // the same code
      // A short gap (< grace) and back → still the same fault, no second alert.
      m.update({1: _status(state: 'RUNNING', hms: const [])});
      time.tick(const Duration(seconds: 5));
      m.update({
        1: _status(state: 'RUNNING', hms: [err]),
      });
      expect(errorAlerts(fake), isEmpty);
      // A longer absence (> grace) → the code is forgotten, a new occurrence alerts.
      // Frames keep arriving throughout — silence across the whole feed is a
      // different situation and has its own test below.
      for (var i = 0; i < 4; i++) {
        time.tick(const Duration(seconds: 10));
        m.update({1: _status(state: 'RUNNING', hms: const [])});
      }
      m.update({
        1: _status(state: 'RUNNING', hms: [err]),
      });
      expect(errorAlerts(fake), hasLength(1));
    },
  );

  testAt('HMS fault: silence in the feed does not clear the memory — a reconnect '
      'does not alert again', (time) {
    final fake = RecordingNotifications();
    final m = monitorAll(fake, hmsDescribe: describeAll);
    const err = HmsError(code: 'A', severity: 2);

    m.update({1: _status(state: 'RUNNING')}); // priming
    m.update({
      1: _status(state: 'RUNNING', hms: [err]),
    });
    expect(errorAlerts(fake), hasLength(1));
    fake.alerts.clear();

    // The socket dies and nothing arrives for two minutes. The socket watchdog is
    // longer than the grace, so every detected drop looks exactly like this — and
    // the fault still stands, because the first frame back still carries it.
    time.tick(const Duration(minutes: 2));
    m.update({
      1: _status(state: 'RUNNING', hms: [err]),
    });

    expect(errorAlerts(fake), isEmpty);
  });

  testAt(
    'HMS fault: an offline printer does not alert; a code known from before the '
    'disconnect does not alert on return, a fresh one does',
    (time) {
      final fake = RecordingNotifications();
      final m = monitorAll(fake, hmsDescribe: describeAll);
      const err = HmsError(code: 'A', severity: 2);
      const other = HmsError(code: 'B', severity: 3);
      // Online with fault A → one alert (the edge). Remembered afterwards.
      m.update({1: _status(state: 'IDLE', connected: true)}); // priming
      m.update({
        1: _status(state: 'IDLE', connected: true, hms: [err]),
      });
      expect(errorAlerts(fake), hasLength(1));
      fake.alerts.clear();
      // Offline: mergedWith carries the old hms_errors forward — no alert even
      // though the code "vanished and came back", and even though the grace elapsed
      // (the memory is frozen).
      m.update({1: _status(state: 'IDLE', connected: false, hms: const [])});
      time.tick(const Duration(seconds: 60));
      m.update({
        1: _status(state: 'IDLE', connected: false, hms: [err]),
      });
      expect(errorAlerts(fake), isEmpty);
      // Back online: the same code A from before the disconnect does NOT alert again…
      m.update({
        1: _status(state: 'IDLE', connected: true, hms: [err]),
      });
      expect(errorAlerts(fake), isEmpty);
      // …but a genuinely new code B after the return does.
      m.update({
        1: _status(state: 'IDLE', connected: true, hms: [err, other]),
      });
      expect(errorAlerts(fake), hasLength(1));
    },
  );

  testAt('an HMS fault first seen after the disconnect alerts on return', (
    time,
  ) {
    final fake = RecordingNotifications();
    final m = monitorAll(fake, hmsDescribe: describeAll);
    const err = HmsError(code: 'A', severity: 2);

    m.update({1: _status(state: 'RUNNING', connected: true)}); // priming
    // The fault appears in the very frame where the printer disappears — nobody has
    // reported it yet, so remembering it would mute it forever.
    m.update({
      1: _status(state: 'RUNNING', connected: false, hms: [err]),
    });
    expect(errorAlerts(fake), isEmpty);

    // A second printer keeps sending frames: each one also grinds through the
    // first printer's state, so the grace would never elapse if the code were
    // latched.
    for (var i = 0; i < 3; i++) {
      time.tick(const Duration(seconds: 45));
      m.update({
        1: _status(state: 'RUNNING', connected: false, hms: [err]),
      });
    }
    expect(errorAlerts(fake), isEmpty);

    // The printer comes back still carrying that fault — now the user must hear
    // about it.
    time.tick(const Duration(seconds: 45));
    m.update({
      1: _status(state: 'RUNNING', connected: true, hms: [err]),
    });

    expect(errorAlerts(fake), hasLength(1));
  });

  testAt('an HMS alert carries the fault it is about, and its buttons', (_) {
    final fake = RecordingNotifications();
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
    m.update({
      1: _status(state: 'RUNNING', hms: [err]),
    });

    final alert = errorAlerts(fake).single;
    // The payload is what the background handler rebuilds the command from.
    expect(alert['payload'], 'hms:1:03008004:746795586');
    final actions = alert['actions']! as List<NotificationAction>;
    expect(actions.map((a) => a.id), [
      'hms:RESUME_PRINTING',
      'hms:STOP_PRINTING',
    ]);
    // Resuming runs on the tap; stopping a print opens the app to ask first.
    expect(actions.map((a) => a.opensApp), [false, true]);
  });

  testAt('an HMS alert lands on the same id in every isolate', (_) {
    // Pinned to literals on purpose: this isolate restarts on every trip to the
    // background, and an id derived from a per-run seed handed the same standing
    // fault a second notification each time instead of replacing the first. A
    // seeded id would not survive the constants below twice.
    final fake = RecordingNotifications();
    final m = monitorAll(fake, hmsDescribe: describeAll);
    const err = HmsError(code: '0x8004', severity: 3, fullCode: '03008004');
    const other = HmsError(code: 'A', severity: 2);

    m.update({1: _status(state: 'RUNNING')}); // priming
    m.update({
      1: _status(state: 'RUNNING', hms: [err, other]),
    });

    expect(errorAlerts(fake).map((a) => a['id']), [8544723, 8921897]);
  });

  testAt('an HMS alert offers no buttons the app could not send', (_) {
    final fake = RecordingNotifications();
    final m = monitorAll(fake, hmsDescribe: describeAll);
    // No full_code (server pre-0.2.4.8): nothing identifies the fault to the
    // firmware, so the alert stays a plain message.
    const legacy = HmsError(
      code: 'A',
      severity: 2,
      actions: ['RESUME_PRINTING'],
    );
    // A code whose only offer is handled by the printer's own screen.
    const screenOnly = HmsError(
      code: '0x8011',
      attr: 0x03008011,
      severity: 3,
      fullCode: '03008011',
      actions: ['CHECK_ASSISTANT'],
    );
    m.update({1: _status(state: 'RUNNING')}); // priming
    m.update({
      1: _status(state: 'RUNNING', hms: [legacy, screenOnly]),
    });

    final alerts = errorAlerts(fake);
    expect(alerts, hasLength(2));
    expect(alerts.map((a) => a['actions']), everyElement(isNull));
    expect(alerts.first['payload'], 'printer:1');
  });

  testAt('an alert never grows more buttons than Android draws', (_) {
    final fake = RecordingNotifications();
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
    m.update({
      1: _status(state: 'RUNNING', hms: [err]),
    });

    final actions =
        errorAlerts(fake).single['actions']! as List<NotificationAction>;
    expect(actions, hasLength(3));
  });

  testAt(
    'HMS fault: several new codes in one frame → separate alerts (different '
    'ids)',
    (_) {
      final fake = RecordingNotifications();
      final m = monitorAll(fake, hmsDescribe: describeAll);
      const a = HmsError(code: 'A', severity: 2);
      const b = HmsError(code: 'B', severity: 3);
      m.update({1: _status(state: 'RUNNING')}); // priming
      m.update({
        1: _status(state: 'RUNNING', hms: [a, b]),
      });
      final alerts = errorAlerts(fake);
      expect(alerts, hasLength(2)); // both codes, none lost
      expect(alerts.map((e) => e['id']).toSet(), hasLength(2)); // different ids
    },
  );

  testAt(
    'HMS fault: a code with no known description is skipped (bambuddy parity)',
    (_) {
      final fake = RecordingNotifications();
      // No description resolver → an undocumented code; same for X2D sev 6 noise.
      final m = monitorAll(fake);
      m.update({1: _status(state: 'RUNNING')});
      m.update({
        1: _status(
          state: 'RUNNING',
          hms: [
            const HmsError(
              code: 'A',
              severity: 2,
            ), // documented severity, no description
            const HmsError(
              code: '0x20070',
              attr: 83887616,
              module: 5,
              severity: 6,
            ),
          ],
        ),
      });
      expect(
        errorAlerts(fake),
        isEmpty,
      ); // nothing without a description alerts
    },
  );

  testAt(
    'HMS fault: a server-side description is enough even without the catalog',
    (_) {
      final fake = RecordingNotifications();
      final m = monitorAll(fake); // no catalog resolver
      m.update({1: _status(state: 'RUNNING')});
      m.update({
        1: _status(
          state: 'RUNNING',
          hms: [
            const HmsError(code: 'A', severity: 2, message: 'Filament runout'),
          ],
        ),
      });
      expect(errorAlerts(fake), hasLength(1));
    },
  );

  testAt('HMS fault: a cancel echo (0500_400E) does not alert', (_) {
    final fake = RecordingNotifications();
    final m = monitorAll(fake, hmsDescribe: describeAll);
    m.update({1: _status(state: 'RUNNING')});
    // ecode = attr(0x05000000) + code(0x400E) → short 0500_400E.
    m.update({
      1: _status(
        state: 'RUNNING',
        hms: [
          const HmsError(
            code: '0x400E',
            attr: 0x05000000,
            module: 5,
            severity: 2,
          ),
        ],
      ),
    });
    expect(errorAlerts(fake), isEmpty);
  });

  testAt('low filament: hysteresis per tray', (_) {
    final fake = RecordingNotifications();
    final m = monitorAll(fake);
    final unitFull = [
      AmsUnit(id: 0, trays: [_tray(remain: 50)]),
    ];
    final unitLow = [
      AmsUnit(id: 0, trays: [_tray(remain: 5)]),
    ];
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

  testAt('high AMS humidity: the edge above the threshold', (_) {
    final fake = RecordingNotifications();
    final m = monitorAll(fake);
    m.update({
      1: _status(state: 'IDLE', ams: [const AmsUnit(id: 0, humidity: 40)]),
    });
    expect(alertById(fake, bandId(10)), isNull);
    m.update({
      1: _status(state: 'IDLE', ams: [const AmsUnit(id: 0, humidity: 70)]),
    });
    expect(alertById(fake, bandId(10)), isNotNull);
  });

  testAt('AMS humidity: two units crossing in one frame report the worse reading', (
    _,
  ) {
    // There is one humidity notification per printer, so the frame that latches
    // both units has to spend it on the wetter one — the other is latched too and
    // stays quiet for the whole cooldown, so an under-reported value is not
    // corrected later.
    final fake = RecordingNotifications();
    final m = monitorAll(fake);

    m.update({
      1: _status(
        state: 'IDLE',
        ams: [
          const AmsUnit(id: 0, humidity: 40),
          const AmsUnit(id: 1, humidity: 40),
        ],
      ),
    });
    m.update({
      1: _status(
        state: 'IDLE',
        ams: [
          const AmsUnit(id: 0, humidity: 88),
          const AmsUnit(id: 1, humidity: 65),
        ],
      ),
    });

    expect(alertById(fake, bandId(10))?['body'], contains('88'));
  });

  testAt(
    'AMS humidity: jitter around the threshold does not ring on every crossing',
    (time) {
      // The server looks every five minutes, we look at every frame — roughly once a
      // second. A reading sitting on the threshold crosses it endlessly.
      final fake = RecordingNotifications();
      final m = monitorAll(fake);
      AmsUnit at(int h) => AmsUnit(id: 0, humidity: h);

      m.update({
        1: _status(state: 'IDLE', ams: [at(50)]),
      }); // priming
      m.update({
        1: _status(state: 'IDLE', ams: [at(61)]),
      });
      expect(fake.alerts, hasLength(1));

      for (final h in [60, 61, 59, 61, 58, 61]) {
        time.tick(const Duration(seconds: 5));
        m.update({
          1: _status(state: 'IDLE', ams: [at(h)]),
        });
      }

      expect(fake.alerts, hasLength(1), reason: 'still the same damp spool');
    },
  );

  testAt('AMS humidity: a real drop re-arms it, but no more than once an hour', (
    time,
  ) {
    final fake = RecordingNotifications();
    final m = monitorAll(fake);
    AmsUnit at(int h) => AmsUnit(id: 0, humidity: h);

    m.update({
      1: _status(state: 'IDLE', ams: [at(50)]),
    }); // priming
    m.update({
      1: _status(state: 'IDLE', ams: [at(61)]),
    });
    expect(fake.alerts, hasLength(1));

    // It went under the band (60 − 3), so the latch releases — but the hour is not
    // up yet, so a fresh rise is only recorded.
    m.update({
      1: _status(state: 'IDLE', ams: [at(56)]),
    });
    time.tick(const Duration(minutes: 20));
    m.update({
      1: _status(state: 'IDLE', ams: [at(70)]),
    });
    expect(fake.alerts, hasLength(1), reason: 'cooldown');

    // An hour after the first alert the same situation is worth a word again.
    m.update({
      1: _status(state: 'IDLE', ams: [at(56)]),
    });
    time.tick(const Duration(minutes: 45));
    m.update({
      1: _status(state: 'IDLE', ams: [at(70)]),
    });
    expect(fake.alerts, hasLength(2));
  });

  testAt('AMS humidity: a rise muted by the cooldown is deferred, not lost', (
    time,
  ) {
    final fake = RecordingNotifications();
    final m = monitorAll(fake);
    AmsUnit at(int h) => AmsUnit(id: 0, humidity: h);

    m.update({
      1: _status(state: 'IDLE', ams: [at(50)]),
    }); // priming
    m.update({
      1: _status(state: 'IDLE', ams: [at(61)]),
    });
    expect(fake.alerts, hasLength(1));

    // A drop under the band, then a rise still inside the cooldown → silence, but
    // the latch is already set.
    m.update({
      1: _status(state: 'IDLE', ams: [at(56)]),
    });
    time.tick(const Duration(minutes: 10));
    m.update({
      1: _status(state: 'IDLE', ams: [at(70)]),
    });
    expect(fake.alerts, hasLength(1));

    // And it never comes down again. The latch must not eat an alert nobody ever
    // said out loud — once the hour is up, it is owed.
    for (var i = 0; i < 3; i++) {
      time.tick(const Duration(minutes: 20));
      m.update({
        1: _status(state: 'IDLE', ams: [at(70)]),
      });
    }

    expect(fake.alerts, hasLength(2));
  });

  testAt('AMS humidity: a steady high reading says it once, not every hour', (
    time,
  ) {
    // A deliberate difference from the server, which reminds every hour: here every
    // other event alerts on the edge, not off a clock.
    final fake = RecordingNotifications();
    final m = monitorAll(fake);
    AmsUnit at(int h) => AmsUnit(id: 0, humidity: h);

    m.update({
      1: _status(state: 'IDLE', ams: [at(50)]),
    }); // priming
    m.update({
      1: _status(state: 'IDLE', ams: [at(70)]),
    });
    expect(fake.alerts, hasLength(1));

    for (var i = 0; i < 5; i++) {
      time.tick(const Duration(minutes: 30));
      m.update({
        1: _status(state: 'IDLE', ams: [at(70)]),
      });
    }

    expect(fake.alerts, hasLength(1));
  });

  testAt('bed cooled: only after a finished print and below the threshold', (
    _,
  ) {
    final fake = RecordingNotifications();
    final m = monitorAll(fake);
    // A cold bed with no print before it → no alert.
    m.update({
      1: _status(state: 'IDLE', temps: {'bed': 25}),
    });
    expect(alertById(fake, bandId(11)), isNull);
    // A print and its end arm the wait for the cool-down.
    m.update({
      1: _status(state: 'RUNNING', job: 'x', temps: {'bed': 60}),
    });
    m.update({
      1: _status(state: 'FINISH', job: 'x', temps: {'bed': 60}),
    });
    expect(alertById(fake, bandId(11)), isNull); // still hot
    m.update({
      1: _status(state: 'FINISH', job: 'x', temps: {'bed': 30}),
    });
    expect(alertById(fake, bandId(11))?['title'], 'Bed cooled');
  });

  testAt('priming: the first frame mid-flight does NOT fire past events', (_) {
    final fake = RecordingNotifications();
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

  testAt('gating: default prefs let through neither "started" nor milestones', (
    _,
  ) {
    final fake = RecordingNotifications();
    final m = monitor(fake); // default prefs
    m.update({1: _status(state: 'RUNNING', job: 'x', progress: 30)});
    expect(alertById(fake, bandId(3)), isNull); // started OFF
    expect(alertById(fake, bandId(5)), isNull); // milestones OFF
  });

  // --- Diagnostic lane (src:notif) ---

  group('diagnostics', () {
    late DiagnosticRecorder recorder;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      recorder = DiagnosticRecorder(
        sessions: MemorySessionStore(),
        redactor: bambuddyRedactor,
        sessionDuration: recordingLimit,
        sessionBytes: recordingSizeLimit,
        loadFacts: () async =>
            const SessionFacts(app: '0.11.3+1103', extra: {'flavor': 'mobile'}),
        // Memory instead of disk: we check the records, not a mirror on a file.
        resolveDirectory: () async => null,
      );
    });

    // Resets the `DiagnosticRecorder.active` static between tests.
    tearDown(() => recorder.discard());

    /// Starts a recording, runs [body] and returns the session's raw JSONL.
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
    ) => [
      for (final r in all)
        if (r['evt'] == evt) r,
    ];

    /// A monitor that writes to the log: a decorator over the fake service.
    PrintMonitor logged(
      RecordingNotifications fake, {
      NotificationPrefs prefs = _allOn,
      TimerFactory? timer,
      String? Function(HmsError)? hmsDescribe,
      void Function(int)? onPrintEnded,
    }) => PrintMonitor(
      LoggingNotifications(fake),
      prefs: prefs,
      l10n: () => lookupAppLocalizations(const Locale('en')),
      timerFactory: timer,
      hmsDescribe: hmsDescribe,
      onPrintEnded: onPrintEnded,
    );

    const firstLayerOff = NotificationPrefs(enabled: {NotifEvent.printStarted});

    testAt('first layer disabled: one record, not one per frame', (_) async {
      // The `_on` gate was evaluated per frame, so a record inside the condition
      // would give one entry per frame until the print ended.
      final fake = RecordingNotifications();
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

    testAt('milestones disabled: one record per threshold', (_) async {
      final fake = RecordingNotifications();
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

    testAt('prep phase: one record per print, not one per frame', (_) async {
      final fake = RecordingNotifications();
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
      // The 6% frame is the one that started the print, and it is turned down
      // one step earlier — by the reading that waits for the printer to publish
      // the new job (`previousJob`), which leaves its own record. 60% is the
      // first frame this gate was asked about.
      expect(skips.single['pct'], 60);
    });

    testAt('a new print arms the latches again', (_) async {
      final fake = RecordingNotifications();
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

    testAt('neither the file name nor the printer name reaches the log', (
      _,
    ) async {
      final fake = RecordingNotifications();
      final m = logged(fake, hmsDescribe: describeAll);
      final jsonl = await raw(() {
        m.update({
          1: _status(state: 'IDLE', name: 'Kitchen X1C', connected: true),
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

    testAt('a posted alert carries the type, the printer and our id', (
      _,
    ) async {
      final fake = RecordingNotifications();
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

    testAt('an HMS alert carries the printer, even though its id is a hash', (
      _,
    ) async {
      final fake = RecordingNotifications();
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

    testAt('a platform rejection gives the exception class, not the message', (
      _,
    ) async {
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

    testAt(
      'progress notification: a record per content change, not per frame',
      (_) async {
        final fake = RecordingNotifications();
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
      },
    );

    testAt('print end in an unknown state: a warning record, no alert', (
      _,
    ) async {
      final fake = RecordingNotifications();
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

    testAt('print end in FINISH: an info record next to the alert', (_) async {
      final fake = RecordingNotifications();
      final ended = <int>[];
      final m = logged(fake, onPrintEnded: ended.add);
      final all = await rows(() {
        m.update({1: _status(state: 'RUNNING', progress: 50)});
        m.update({1: _status(state: 'FINISH', progress: 100)});
      });

      final end = only(all, 'print_end').single;
      expect(end['state'], 'FINISH');
      expect(end.containsKey('lvl'), isFalse); // info is not written out
      expect(ended, [1]);
    });

    testAt('priming records a baseline that implies nothing', (_) async {
      final fake = RecordingNotifications();
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

    testAt('HMS: the reasons are kept apart, and a known code stays silent', (
      _,
    ) async {
      final fake = RecordingNotifications();
      // No catalog description and severity 1 → an undocumented code.
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

    testAt('HMS on a disconnected printer: reason offline, not typeOff', (
      _,
    ) async {
      final fake = RecordingNotifications();
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

    testAt('a printer returning before the grace runs out leaves a trace', (
      _,
    ) async {
      final fake = RecordingNotifications();
      final timers = <FakeTimer>[];
      final m = logged(
        fake,
        timer: (d, cb) {
          final t = FakeTimer(Duration.zero, cb);
          timers.add(t);
          return t;
        },
      );
      final all = await rows(() {
        m.update({1: _status(connected: true)});
        m.update({1: _status(connected: false)});
        m.update({1: _status(connected: true)}); // back before it fires
        m.update({1: _status(connected: true)}); // no timer → no record
      });

      final skips = only(all, 'suppressed');
      expect(skips, hasLength(1));
      expect(skips.single['reason'], 'reconnected');
      expect(timers.single.isActive, isFalse);
    });

    testAt('the prefs snapshot lists the disabled types and the system state', (
      _,
    ) async {
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

    testAt('an unresponsive platform does not break the snapshot', (_) async {
      final all = await rows(() async {
        await NotifProbe.openSession(
          NotificationPrefs.defaults,
          permission: () async => throw StateError('no channel'),
          channelImportance: () async => null,
        );
      });

      final prefs = only(all, 'prefs').single;
      // A missing field means "no answer", not "denied".
      expect(prefs.containsKey('perm'), isFalse);
      expect(prefs.containsKey('chan_imp'), isFalse);
    });
  });
}

/// A fake where the platform rejects every alert.
class _ThrowingNotifications extends RecordingNotifications {
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
  }) async => throw StateError('plugin not initialised');
}
