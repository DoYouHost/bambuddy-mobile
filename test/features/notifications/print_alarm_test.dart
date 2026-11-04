import 'dart:async';
import 'dart:convert';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:bambuddy_mobile/core/diagnostics/report_config.dart';

import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/notifications/alarm_ringer.dart';
import 'package:bambuddy_mobile/core/notifications/notification_prefs.dart';
import 'package:bambuddy_mobile/features/notifications/print_monitor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';
import '../../hms_samples.dart';

/// Inside the default 22:00–07:00 window.
final _night = DateTime(2026, 11, 4, 23, 30);

class _Ringer implements AlarmRinger {
  final List<Map<String, Object?>> rings = [];
  bool answer = true;

  @override
  Future<bool> ring({
    required int id,
    required String title,
    required String body,
    required String stopLabel,
    required int minutes,
    required String printer,
  }) async {
    rings.add({
      'id': id,
      'title': title,
      'body': body,
      'stop': stopLabel,
      'minutes': minutes,
      'printer': printer,
    });
    return answer;
  }

  @override
  Future<bool> canFullScreen() async => true;

  @override
  Future<void> openFullScreenSettings() async {}
}

class _Timers {
  final List<FakeTimer> started = [];

  Timer call(Duration d, void Function() cb) {
    final t = FakeTimer(d, cb);
    started.add(t);
    return t;
  }

  void elapse() {
    final due = started.where((t) => t.isActive).toList();
    started.removeWhere(due.contains);
    for (final t in due) {
      t.fire();
    }
  }
}

PrinterStatus _status({
  String? state,
  String? job,
  List<HmsError>? hms,
  List<AmsUnit>? ams,
}) => PrinterStatus(
  id: 1,
  name: 'X1C',
  state: state,
  currentPrint: job,
  hmsErrors: hms,
  ams: ams,
);

AmsUnit _unit(int? minutes, {int? status, int id = 0}) =>
    AmsUnit(id: id, dryTime: minutes, dryStatus: status);

void main() {
  late _Ringer ringer;
  late _Timers timers;

  PrintMonitor monitor({
    AlarmPrefs alarm = const AlarmPrefs(enabled: true),
    Set<NotifEvent> notifications = const {},
    String? Function(int)? locationOf,
  }) {
    ringer = _Ringer();
    timers = _Timers();
    return PrintMonitor(
      RecordingNotifications(),
      serverUrl: 'http://bambuddy.lan',
      prefs: NotificationPrefs(enabled: notifications, alarm: alarm),
      l10n: () => en,
      timerFactory: timers.call,
      hmsDescribe: (e) => 'described',
      alarm: ringer,
      alarmLocationOf: locationOf,
    );
  }

  void at(String description, void Function(TestClock time) body) =>
      testWithClock(description, _night, (time) async {
        body(time);
        // Lets the `then` on a ring run.
        await Future<void>.delayed(Duration.zero);
      });

  void finishPrint(PrintMonitor m) {
    m.update({1: _status(state: 'RUNNING', job: 'cube.3mf')});
    m.update({1: _status(state: 'FINISH', job: 'cube.3mf')});
  }

  group('print finished', () {
    at('rings once, with the labels and the length the user chose', (_) {
      final m = monitor(alarm: const AlarmPrefs(enabled: true, ringMinutes: 3));
      finishPrint(m);
      m.update({1: _status(state: 'FINISH', job: 'cube.3mf')});
      expect(ringer.rings, [
        {
          'id': 18 * alertBandWidth + 1,
          'title': en.printFinishedTitle,
          'body': en.printFinishedBody('cube.3mf'),
          'stop': en.alarmStop,
          'minutes': 3,
          'printer': 'X1C',
        },
      ]);
    });

    at('rings with the finish notification switched off', (_) {
      final m = monitor();
      finishPrint(m);
      expect(ringer.rings, hasLength(1));
    });

    at('stays silent with the alarm off', (_) {
      final m = monitor(alarm: const AlarmPrefs());
      finishPrint(m);
      expect(ringer.rings, isEmpty);
    });

    at('stays silent with its event cleared', (_) {
      final m = monitor(
        alarm: const AlarmPrefs(
          enabled: true,
        ).withEvent(AlarmEvent.printFinished, false),
      );
      finishPrint(m);
      expect(ringer.rings, isEmpty);
    });

    at('a print that had ended before the monitor started is no news', (_) {
      final m = monitor();
      m.update({1: _status(state: 'FINISH')});
      m.update({1: _status(state: 'FINISH')});
      expect(ringer.rings, isEmpty);
    });

    at('a cancel is not a finish', (_) {
      final m = monitor();
      m.update({1: _status(state: 'RUNNING')});
      m.update({1: _status(state: 'IDLE')});
      expect(ringer.rings, isEmpty);
    });
  });

  group('excluded printers', () {
    at('an excluded printer stays silent', (_) {
      final m = monitor(
        alarm: const AlarmPrefs(enabled: true, excludedPrinters: {1}),
      );
      finishPrint(m);
      expect(ringer.rings, isEmpty);
    });

    at('another printer still rings', (_) {
      final m = monitor(
        alarm: const AlarmPrefs(enabled: true, excludedPrinters: {2}),
      );
      finishPrint(m);
      expect(ringer.rings, hasLength(1));
    });

    at('a printer in an excluded location stays silent', (_) {
      final m = monitor(
        alarm: const AlarmPrefs(enabled: true, excludedLocations: {'Garage'}),
        locationOf: (id) => id == 1 ? 'Garage' : null,
      );
      finishPrint(m);
      expect(ringer.rings, isEmpty);
    });

    at('a printer whose location is unknown rings', (_) {
      final m = monitor(
        alarm: const AlarmPrefs(enabled: true, excludedLocations: {'Garage'}),
        locationOf: (_) => null,
      );
      finishPrint(m);
      expect(ringer.rings, hasLength(1));
    });

    at('exclusions hold for every event, drying included', (_) {
      final m = monitor(
        alarm: const AlarmPrefs(enabled: true, excludedPrinters: {1}),
      );
      m.update({
        1: _status(state: 'IDLE', ams: [_unit(1, status: 2)]),
      });
      m.update({
        1: _status(state: 'IDLE', ams: [_unit(0, status: 0)]),
      });
      m.update({1: _status(state: 'RUNNING')});
      m.update({1: _status(state: 'FAILED')});
      expect(ringer.rings, isEmpty);
    });
  });

  group('hours', () {
    at('outside the window it stays silent', (time) {
      time.now = DateTime(2026, 11, 4, 12);
      final m = monitor();
      finishPrint(m);
      expect(ringer.rings, isEmpty);
    });

    at('the window switched off rings at noon too', (time) {
      time.now = DateTime(2026, 11, 4, 12);
      final m = monitor(
        alarm: const AlarmPrefs(enabled: true, windowEnabled: false),
      );
      finishPrint(m);
      expect(ringer.rings, hasLength(1));
    });

    at('the window is read when it rings, not when the print started', (time) {
      time.now = DateTime(2026, 11, 4, 21, 59);
      final m = monitor();
      m.update({1: _status(state: 'RUNNING')});
      m.update({1: _status(state: 'RUNNING')});
      time.now = DateTime(2026, 11, 4, 22);
      m.update({1: _status(state: 'FINISH')});
      expect(ringer.rings, hasLength(1));
    });
  });

  group('print stopped', () {
    at('a failed print rings', (_) {
      final m = monitor();
      m.update({1: _status(state: 'RUNNING', job: 'cube.3mf')});
      m.update({1: _status(state: 'FAILED', job: 'cube.3mf')});
      expect(ringer.rings.single['title'], en.printFailedTitle);
    });

    at('a fault that pauses the print rings once it has stood', (_) {
      final m = monitor();
      final runout = hmsRunout.fault;
      expect(runout.level, 2);
      m.update({1: _status(state: 'RUNNING')});
      m.update({
        1: _status(state: 'PAUSE', hms: [runout]),
      });
      expect(ringer.rings, isEmpty, reason: 'not before the hold');
      timers.elapse();
      expect(ringer.rings.single['title'], en.notifErrorTitle);
    });

    at('a fault that only prompts does not ring', (_) {
      final prompt = HmsSample.printError(
        'a prompt',
        0x0300C004,
        description: 'Check the nozzle.',
        alerts: true,
      ).fault;
      expect(prompt.level, 3);
      final m = monitor(notifications: {NotifEvent.printerError});
      m.update({1: _status(state: 'RUNNING')});
      m.update({
        1: _status(state: 'RUNNING', hms: [prompt]),
      });
      timers.elapse();
      expect(ringer.rings, isEmpty);
    });

    at('a stopping fault on an idle printer does not ring', (_) {
      final m = monitor();
      m.update({1: _status(state: 'IDLE')});
      m.update({
        1: _status(state: 'IDLE', hms: [hmsRunout.fault]),
      });
      timers.elapse();
      expect(ringer.rings, isEmpty);
    });

    at('the fault alarm off and its notification off: no hold at all', (_) {
      final m = monitor(
        alarm: const AlarmPrefs(
          enabled: true,
        ).withEvent(AlarmEvent.printBlocked, false),
      );
      m.update({1: _status(state: 'RUNNING')});
      m.update({
        1: _status(state: 'PAUSE', hms: [hmsRunout.fault]),
      });
      expect(timers.started, isEmpty);
      expect(ringer.rings, isEmpty);
    });
  });

  group('drying finished', () {
    void dry(PrintMonitor m, List<AmsUnit> frames) {
      for (final unit in frames) {
        m.update({
          1: _status(state: 'IDLE', ams: [unit]),
        });
      }
    }

    at('the countdown reaching zero rings', (_) {
      final m = monitor();
      dry(m, [_unit(2, status: 2), _unit(1, status: 2), _unit(0, status: 0)]);
      expect(ringer.rings.single, {
        'id': 18 * alertBandWidth + 1,
        'title': en.alarmEvtDrying,
        'body': en.alarmEvtDryingDesc,
        'stop': en.alarmStop,
        'minutes': 10,
        'printer': 'X1C',
      });
    });

    at('a zero while the unit is still drying is not the end', (_) {
      final m = monitor();
      dry(m, [
        _unit(720, status: 1),
        _unit(0, status: 1),
        _unit(719, status: 2),
      ]);
      expect(ringer.rings, isEmpty);
      // The real end still sees a non-zero reading before it.
      dry(m, [_unit(1, status: 2), _unit(0, status: 0)]);
      expect(ringer.rings, hasLength(1));
    });

    at('the cooling that closes a cycle is still the cycle', (_) {
      // dry_time reads 0 through Cooling (dry_status 3); the server waits for
      // the phase to end before it calls the cycle complete.
      final m = monitor();
      dry(m, [_unit(1, status: 2), _unit(0, status: 3), _unit(0, status: 3)]);
      expect(ringer.rings, isEmpty);
      dry(m, [_unit(0, status: 0)]);
      expect(ringer.rings, hasLength(1));
    });

    at('a monitor that starts during the cooling still rings at its end', (_) {
      final m = monitor();
      dry(m, [_unit(0, status: 3), _unit(0, status: 3)]);
      expect(ringer.rings, isEmpty);
      dry(m, [_unit(0, status: 0)]);
      expect(ringer.rings, hasLength(1));
    });

    at('cooling after a gap in the feed still counts as run to term', (_) {
      final m = monitor();
      // Last seen with time left, then nothing until the cooling.
      dry(m, [_unit(10, status: 2), _unit(10, status: 2), _unit(0, status: 3)]);
      dry(m, [_unit(0, status: 0)]);
      expect(ringer.rings, hasLength(1));
    });

    at('cooling after an idle zero still counts as run to term', (_) {
      final m = monitor();
      // The whole countdown fell into a gap in the feed.
      dry(m, [_unit(0), _unit(0), _unit(0, status: 3), _unit(0, status: 0)]);
      expect(ringer.rings, hasLength(1));
    });

    at('a monitor that starts while the unit checks does not invent a cycle', (
      _,
    ) {
      final m = monitor();
      dry(m, [_unit(0, status: 1), _unit(0, status: 0)]);
      expect(ringer.rings, isEmpty);
    });

    at('a cycle stopped with time left does not ring', (_) {
      final m = monitor();
      dry(m, [_unit(700, status: 2), _unit(0, status: 0)]);
      expect(ringer.rings, isEmpty);
    });

    at('ended at the margin still rings, one minute over does not', (_) {
      final m = monitor();
      dry(m, [_unit(5, status: 2), _unit(0, status: 0)]);
      expect(ringer.rings, hasLength(1));
      dry(m, [_unit(6, status: 2), _unit(0, status: 0)]);
      expect(ringer.rings, hasLength(1));
    });

    at('a frame without the field is no news', (_) {
      final m = monitor();
      dry(m, [_unit(1, status: 2), _unit(null), _unit(0, status: 0)]);
      expect(ringer.rings, hasLength(1));
    });

    at('an idle unit at zero rings nothing, however long it sits', (_) {
      final m = monitor();
      dry(m, [_unit(0), _unit(0), _unit(0)]);
      expect(ringer.rings, isEmpty);
    });

    at('each unit keeps its own countdown', (_) {
      final m = monitor();
      m.update({
        1: _status(
          state: 'IDLE',
          ams: [_unit(1, status: 2), _unit(30, status: 2, id: 1)],
        ),
      });
      m.update({
        1: _status(
          state: 'IDLE',
          ams: [_unit(0, status: 0), _unit(29, status: 2, id: 1)],
        ),
      });
      expect(ringer.rings, hasLength(1));
    });
  });

  group('diagnostics', () {
    late DiagnosticRecorder recorder;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      recorder = DiagnosticRecorder(
        sessions: MemorySessionStore(),
        redactor: bambuddyRedactor,
        sessionDuration: recordingLimit,
        sessionBytes: recordingSizeLimit,
        loadFacts: () async => const SessionFacts(app: '0.17.2+1'),
        resolveDirectory: () async => null,
      );
    });
    tearDown(() => recorder.discard());

    Future<List<Map<String, Object?>>> rows(
      FutureOr<void> Function() body,
    ) async {
      await recorder.start();
      await body();
      final jsonl = await recorder.stop();
      return [
        for (final line in const LineSplitter().convert(jsonl))
          if (jsonDecode(line) case final Map<String, Object?> row
              when row['src'] == 'notif')
            row,
      ];
    }

    testWithClock('a ring that went through is recorded as rang', _night, (
      _,
    ) async {
      final all = await rows(() async {
        finishPrint(monitor());
        await Future<void>.delayed(Duration.zero);
      });
      expect(
        [
          for (final r in all)
            if (r['evt'] == 'alarm') r['outcome'],
        ],
        ['ringing', 'rang'],
      );
    });

    testWithClock(
      'a hold only the alarm asked for says nothing about the alert when it clears',
      _night,
      (time) async {
        final all = await rows(() {
          final m = monitor();
          m.update({1: _status(state: 'RUNNING')});
          m.update({
            1: _status(state: 'PAUSE', hms: [hmsRunout.fault]),
          });
          // Gone before the hold, and away past the grace.
          m.update({1: _status(state: 'PAUSE', hms: const [])});
          // Frames keep coming: a silent feed would hold the code instead.
          for (var i = 0; i < 4; i++) {
            time.tick(const Duration(seconds: 10));
            m.update({1: _status(state: 'PAUSE', hms: const [])});
          }
        });
        expect([
          for (final r in all)
            if (r['evt'] == 'suppressed') r['reason'],
        ], isEmpty);
        expect(ringer.rings, isEmpty);
      },
    );
  });
}
