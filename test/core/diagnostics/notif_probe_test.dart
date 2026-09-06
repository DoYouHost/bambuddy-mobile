import 'dart:convert';

import 'package:bambuddy_mobile/core/diagnostics/diagnostic_recorder.dart';
import 'package:bambuddy_mobile/core/diagnostics/notif_probe.dart';
import 'package:bambuddy_mobile/core/diagnostics/session_facts.dart';
import 'package:bambuddy_mobile/core/notifications/notification_prefs.dart';
import 'package:bambuddy_mobile/core/notifications/notification_service.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The notification lane, which had no tests at all.
///
/// Two things are being pinned. First, the promise in
/// `docs/diagnostics-log.md` that a notification's `title` and `body` never
/// enter a record: they are the job label and the printer's name, and a
/// recording ends up on a public, permanent GitHub issue. Second, that the lane
/// actually answers the question it exists for — "why did I not get an alert" —
/// because a decision *not* to post leaves no trace on the device, so if it is
/// not in the log the reporter has to be asked, which is the whole failure mode
/// this log was built to avoid.
class _FakeNotifications implements NotificationService {
  Object? failWith;

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> showOngoing({
    required String title,
    required String body,
    required int progress,
  }) async {}

  @override
  Future<void> clearOngoing() async {}

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
    if (failWith != null) throw failWith!;
  }

  @override
  Future<bool> isAlertActive(int id) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DiagnosticRecorder recorder;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    recorder = DiagnosticRecorder(
      settings: SettingsRepository(await SharedPreferences.getInstance()),
      loadFacts: () async =>
          const SessionFacts(app: '0.12.1+1201000', flavor: 'mobile'),
      resolveDirectory: () async => null,
    );
    addTearDown(recorder.discard);
    await recorder.start();
  });

  /// The whole session as text, which is what actually gets uploaded.
  Future<String> raw() => recorder.stop();

  Future<List<Map<String, dynamic>>> notifRows() async {
    final jsonl = await recorder.stop();
    return [
      for (final line in const LineSplitter().convert(jsonl))
        if (jsonDecode(line) case final Map<String, dynamic> row
            when row['src'] == 'notif')
          row,
    ];
  }

  group('what a notification must never leave behind', () {
    test('the alert is recorded, its title and body are not', () async {
      // Both strings are the user's world: the job they named and the printer
      // they named. `LoggingNotifications` sees both and may keep neither.
      final service = LoggingNotifications(_FakeNotifications());

      await service.showAlert(
        event: NotifEvent.printFinished,
        printerId: 3,
        id: 77,
        title: 'Drukarka w piwnicy',
        body: 'cv-jan-kowalski-v3.3mf skończone',
      );

      final jsonl = await raw();
      expect(jsonl, isNot(contains('piwnicy')));
      expect(jsonl, isNot(contains('kowalski')));
      expect(jsonl, isNot(contains('3mf')));
    });

    test('the record still says enough to place the alert', () async {
      // Dropping the text is only acceptable because what is left answers
      // "which alert, for which printer, when".
      final service = LoggingNotifications(_FakeNotifications());

      await service.showAlert(
        event: NotifEvent.printFailed,
        printerId: 3,
        id: 77,
        title: 'anything',
        body: 'anything',
      );

      final rows = await notifRows();
      expect(rows.single['evt'], 'posted');
      expect(rows.single['event'], 'printFailed');
      expect(rows.single['printer_id'], 3);
      expect(rows.single['nid'], 77);
    });

    test(
      'a refused alert reports the exception class, never its message',
      () async {
        // A platform exception's message quotes what it was handed, and what it
        // was handed is the title and the body.
        final inner = _FakeNotifications()
          ..failWith = StateError('channel refused "cv-jan-kowalski-v3.3mf"');
        final service = LoggingNotifications(inner);

        await expectLater(
          service.showAlert(
            event: NotifEvent.printFinished,
            printerId: 3,
            id: 77,
            title: 'Drukarka w piwnicy',
            body: 'cv-jan-kowalski-v3.3mf skończone',
          ),
          throwsStateError,
        );

        final jsonl = await raw();
        expect(jsonl, isNot(contains('kowalski')));
        expect(jsonl, contains('StateError'));
      },
    );

    test('the same holds for a failed action and a failed init', () async {
      NotifProbe.actionFailed(
        StateError('mark done failed for cv-jan-kowalski-v3.3mf'),
        items: 2,
      );
      NotifProbe.initFailed(ArgumentError('bad channel Drukarka w piwnicy'));

      final jsonl = await raw();
      expect(jsonl, isNot(contains('kowalski')));
      expect(jsonl, isNot(contains('piwnicy')));
      expect(jsonl, contains('StateError'));
      expect(jsonl, contains('ArgumentError'));
    });

    test(
      'the ongoing record carries numbers, not the job it describes',
      () async {
        // The notification's own text is the job name; these four fields are
        // what the monitor collapses frames on, and all of them are the
        // printer's or ours.
        NotifProbe.ongoing(printerId: 3, percent: 42, etaMin: 18, active: 1);

        final rows = await notifRows();
        expect(rows.single['pct'], 42);
        expect(rows.single['eta_min'], 18);
        expect(rows.single.keys, isNot(contains('title')));
        expect(rows.single.keys, isNot(contains('body')));
      },
    );
  });

  group('why no alert arrived — the half that leaves no other trace', () {
    test('every skip reason survives as its own wire value', () async {
      // The summarising Action groups by these names. A reason that collapsed
      // into another would send the reader back to asking the reporter, which
      // is exactly what this lane exists to prevent.
      for (final reason in NotifSkip.values) {
        NotifProbe.suppressed(reason, printerId: 3);
      }

      final rows = await notifRows();
      expect(rows, hasLength(NotifSkip.values.length));
      expect(
        rows.map((r) => r['reason']).toSet(),
        NotifSkip.values.map((r) => r.name).toSet(),
      );
    });

    test(
      '"you turned it off" and "everything is off" stay different answers',
      () async {
        // Two different controls, two different things to tell the user to go
        // and change.
        NotifProbe.suppressed(
          NotifSkip.typeOff,
          event: NotifEvent.printFinished,
        );
        NotifProbe.suppressed(NotifSkip.alertsOff);

        final rows = await notifRows();
        expect(rows.first['reason'], 'typeOff');
        expect(rows.first['event'], 'printFinished');
        expect(rows.last['reason'], 'alertsOff');
      },
    );

    test(
      'a fleet-wide decision names no printer rather than guessing one',
      () async {
        // A maintenance poll fails for everything at once; naming one printer
        // would read as "only that one".
        NotifProbe.suppressed(NotifSkip.fetchFailed);

        final rows = await notifRows();
        expect(rows.single.containsKey('printer_id'), isFalse);
        expect(rows.single.containsKey('event'), isFalse);
      },
    );

    test(
      'priming is not a suppression, because nothing was decided yet',
      () async {
        // A fresh monitor stays silent on its first frame on purpose. Told as a
        // suppression it would describe a decision that never took place — and
        // this silence is the answer to a whole class of "the app swallowed it".
        NotifProbe.primed(3);

        final rows = await notifRows();
        expect(rows.single['evt'], 'primed');
        expect(rows.single['printer_id'], 3);
      },
    );

    test(
      'a print that ended in a state nothing acts on is flagged as unhandled',
      () async {
        // FINISH and FAILED are the only two the monitor acts on; everything
        // else silently drops the alert and the maintenance reminder with it,
        // so the level is what makes it findable in a long session.
        NotifProbe.printEnd(3, state: 'IDLE', handled: false);
        NotifProbe.printEnd(4, state: 'FINISH', handled: true);

        final rows = await notifRows();
        expect(rows.first['lvl'], 'warn');
        expect(rows.first['state'], 'IDLE');
        expect(
          rows.last.containsKey('lvl'),
          isFalse,
          reason: 'info is implied',
        );
      },
    );
  });

  group('the settings snapshot that explains the rest of the session', () {
    test('records which types are off, and the two OS-level gates', () async {
      // One line instead of a record per suppressed event — and it works even
      // when the recording covers none of the moments an alert was due.
      await NotifProbe.openSession(
        const NotificationPrefs(
          enabled: {NotifEvent.printFinished},
          alertsEnabled: false,
        ),
        permission: () async => true,
        channelImportance: () async => 0,
      );

      final rows = await notifRows();
      expect(rows.single['evt'], 'prefs');
      expect(rows.single['alerts'], isFalse);
      expect(rows.single['perm'], isTrue);
      // Granted permission with a muted channel is a real configuration, and
      // indistinguishable from a working one without this field.
      expect(rows.single['chan_imp'], 0);
      final off = (rows.single['off']! as List).cast<String>();
      expect(off, isNot(contains('printFinished')));
      expect(off, contains('printFailed'));
    });

    test(
      'a platform read that throws costs the field, not the snapshot',
      () async {
        // A recorder must not be able to cause the failure it exists to
        // describe.
        await NotifProbe.openSession(
          const NotificationPrefs(enabled: {NotifEvent.printFinished}),
          permission: () async =>
              throw StateError('no platform in a unit test'),
          channelImportance: () async => throw StateError('nor here'),
        );

        final rows = await notifRows();
        expect(rows, hasLength(1));
        expect(rows.single.containsKey('perm'), isFalse);
        expect(rows.single.containsKey('chan_imp'), isFalse);
      },
    );

    test('an unknown answer is an absent field, never a guessed one', () async {
      await NotifProbe.openSession(
        const NotificationPrefs(enabled: {NotifEvent.printFinished}),
        permission: () async => null,
        channelImportance: () async => null,
      );

      final rows = await notifRows();
      expect(rows.single.containsKey('perm'), isFalse);
    });
  });
}
