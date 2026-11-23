import 'dart:async';

import 'package:bambuddy_mobile/core/api/edge_access_probe.dart';
import 'package:bambuddy_mobile/core/notifications/edge_session_alert.dart';
import 'package:bambuddy_mobile/core/notifications/notification_prefs.dart';
import 'package:bambuddy_mobile/core/notifications/notification_service.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

// What happens when Cloudflare stops accepting the browser session (#72): one
// mark and one notification per ending, wherever it was noticed.

void main() {
  late SharedPreferences prefs;
  late RecordingNotifications notifications;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    // A server is set up; the setup screen's own probe is the next test's case.
    await SettingsRepository(prefs).saveProfile(
      const ServerProfile(
        baseUrl: 'https://printers.example.com',
        authMode: AuthMode.none,
      ),
    );
    notifications = RecordingNotifications();
  });

  tearDown(() {
    EdgeSessionSignal.listener = null;
    EdgeSessionSignal.acceptedListener = null;
  });

  EdgeSessionAlert alert({bool canPost = true}) => EdgeSessionAlert(
    settings: () => SettingsRepository(prefs).reloaded(),
    notifications: canPost ? notifications : null,
    l10n: () => en,
  );

  Future<void> savePrefs(NotificationPrefs value) =>
      prefs.setString('notification_prefs', value.encode());

  test('writes the mark and tells the user, once', () async {
    await alert().ended('printers.example.com');

    expect(
      SettingsRepository(prefs).loadEdgeSessionEnded(),
      'printers.example.com',
    );
    final posted = notifications.alerts.single;
    expect(posted['event'], NotifEvent.edgeSessionEnded);
    expect(posted['id'], edgeSessionAlertId);
    expect(posted['title'], en.notifEdgeSessionTitle);
    expect(posted['body'], en.notifEdgeSessionBody);
    expect(posted['payload'], 'edge_session');
  });

  test('a refused service token is told as one, with its own words', () async {
    await alert().ended('printers.example.com', token: true);

    final posted = notifications.alerts.single;
    expect(posted['event'], NotifEvent.edgeSessionEnded);
    expect(posted['title'], en.notifEdgeTokenTitle);
    expect(posted['body'], en.notifEdgeTokenBody);
  });

  test('the probe tells which kind it was', () async {
    alert().listen();
    EdgeSessionSignal.ended('printers.example.com', token: true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(notifications.alerts.single['title'], en.notifEdgeTokenTitle);
  });

  test('with no server set up there is nothing to warn about', () async {
    // The setup screen probes with the credential it was just given.
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await alert().ended('printers.example.com', token: true);

    expect(notifications.alerts, isEmpty);
    expect(SettingsRepository(prefs).loadEdgeSessionEnded(), isNull);
  });

  test('every request that met the ending reports it, and one posts', () async {
    final handler = alert();
    await Future.wait([
      handler.ended('printers.example.com'),
      handler.ended('printers.example.com'),
      handler.ended('printers.example.com'),
    ]);
    expect(notifications.alerts, hasLength(1));
  });

  test('a later request finds the mark and says nothing', () async {
    await alert().ended('printers.example.com');
    await alert().ended('printers.example.com');
    expect(notifications.alerts, hasLength(1));
  });

  test('one that another isolate already told is not told again', () async {
    final store = SettingsRepository(prefs);
    await store.saveEdgeSessionEnded('printers.example.com');
    await store.saveEdgeSessionNotified('printers.example.com');
    await alert().ended('printers.example.com');
    expect(notifications.alerts, isEmpty);
  });

  test('one that an isolate that could not post recorded is told', () async {
    // A notification button's isolate has no service: it leaves the ending
    // written and nothing said, and must not stand for "told".
    await alert(canPost: false).ended('printers.example.com');
    expect(notifications.alerts, isEmpty);

    await alert().ended('printers.example.com');
    expect(notifications.alerts, hasLength(1));

    await alert().ended('printers.example.com');
    expect(notifications.alerts, hasLength(1), reason: 'and then it is told');
  });

  test(
    'a session that ends again after the mark was cleared is told',
    () async {
      final handler = alert();
      await handler.ended('printers.example.com');
      await SettingsRepository(prefs).saveEdgeSessionEnded(null);
      await handler.ended('printers.example.com');
      expect(notifications.alerts, hasLength(2));
    },
  );

  test('where nothing can be posted, the mark is still written', () async {
    await alert(canPost: false).ended('printers.example.com');
    expect(
      SettingsRepository(prefs).loadEdgeSessionEnded(),
      'printers.example.com',
    );
    expect(notifications.alerts, isEmpty);
  });

  test('the user having switched the event off keeps it quiet', () async {
    await savePrefs(
      NotificationPrefs.defaults.withEvent(NotifEvent.edgeSessionEnded, false),
    );
    await alert().ended('printers.example.com');
    expect(notifications.alerts, isEmpty);
    expect(
      SettingsRepository(prefs).loadEdgeSessionEnded(),
      'printers.example.com',
      reason: 'the banner still says it',
    );
  });

  test('so does every alert being off', () async {
    await savePrefs(NotificationPrefs.defaults.copyWith(alertsEnabled: false));
    await alert().ended('printers.example.com');
    expect(notifications.alerts, isEmpty);
  });

  test('the event is on for an install that predates it', () {
    // No manifest of known events in the saved prefs: written before this
    // existed, so it takes what the build ships it with.
    final prefs = NotificationPrefs.fromJson(const {'enabled': <String>[]});
    expect(prefs.isOn(NotifEvent.edgeSessionEnded), isTrue);
  });

  test('is what the probe reaches once the isolate listens', () async {
    alert().listen();
    EdgeSessionSignal.ended('printers.example.com');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(notifications.alerts, hasLength(1));
  });

  group('when Cloudflare accepts it again', () {
    final start = DateTime.utc(2026, 11, 24, 9);
    const host = 'printers.example.com';

    /// Runs [body] with the clock at [start] plus what has been advanced.
    Future<void> timed(
      Future<void> Function(void Function(Duration) advance) body,
    ) {
      var now = start;
      return withClock(Clock(() => now), () => body((d) => now = now.add(d)));
    }

    test('clears both marks and tells the app', () async {
      await timed((advance) async {
        final handler = alert();
        await handler.ended(host);
        final recovered = <String>[];
        final sub = edgeSessionRecoveries.listen(recovered.add);
        addTearDown(sub.cancel);

        advance(edgeAcceptedCheckEvery);
        await handler.accepted(host);
        await Future<void>.delayed(Duration.zero);

        final store = SettingsRepository(prefs);
        expect(store.loadEdgeSessionEnded(), isNull);
        expect(store.loadEdgeSessionNotified(), isNull);
        expect(recovered, [host]);
      });
    });

    test('takes the notification back off the screen', () async {
      await timed((advance) async {
        final handler = alert();
        await handler.ended(host);
        advance(edgeAcceptedCheckEvery);
        await handler.accepted(host);

        expect(notifications.cancelled, [edgeSessionAlertId]);
      });
    });

    test(
      'takes nothing back that was never told, or is not this host\'s',
      () async {
        await timed((advance) async {
          final handler = alert();
          await handler.accepted(host); // nothing recorded
          await handler.ended('other.example.com');
          advance(edgeAcceptedCheckEvery);
          await handler.accepted(host); // another host's ending

          expect(notifications.cancelled, isEmpty);
        });
      },
    );

    test('where nothing can be posted there is nothing to take back', () async {
      await timed((advance) async {
        final handler = alert(canPost: false);
        await handler.ended(host);
        advance(edgeAcceptedCheckEvery);
        await handler.accepted(host);

        expect(SettingsRepository(prefs).loadEdgeSessionEnded(), isNull);
      });
    });

    test('is not believed at once: the first look is a minute later', () async {
      // A request already on its way when the refusal came may be one that got
      // through, and would take the banner down the moment it went up.
      await timed((advance) async {
        final handler = alert();
        await handler.ended(host);
        advance(const Duration(seconds: 5));
        await handler.accepted(host);
        expect(SettingsRepository(prefs).loadEdgeSessionEnded(), host);
      });
    });

    test('looks once a minute, not at every request', () async {
      await timed((advance) async {
        final handler = alert();
        await handler.accepted(host); // the first look, nothing recorded yet
        await SettingsRepository(prefs).saveEdgeSessionEnded(host);

        advance(const Duration(seconds: 30));
        await handler.accepted(host);
        expect(SettingsRepository(prefs).loadEdgeSessionEnded(), host);

        advance(const Duration(seconds: 31));
        await handler.accepted(host);
        expect(SettingsRepository(prefs).loadEdgeSessionEnded(), isNull);
      });
    });

    test('holds off by the ending\'s own time, from any isolate', () async {
      // One isolate finds it out; another, with no hold-off of its own, gets a
      // request through a moment later. It must not take the banner down.
      await timed((advance) async {
        await alert().ended(host);
        advance(const Duration(seconds: 10));
        await alert().accepted(host);
        expect(SettingsRepository(prefs).loadEdgeSessionEnded(), host);

        advance(edgeAcceptedCheckEvery);
        await alert().accepted(host);
        expect(SettingsRepository(prefs).loadEdgeSessionEnded(), isNull);
      });
    });

    test('does not clear an ending found out while it was looking', () async {
      await timed((advance) async {
        final gate = Completer<void>();
        var first = true;
        // The look is slow to read the marks; an ending is written meanwhile.
        final looking = EdgeSessionAlert(
          settings: () async {
            if (first) {
              first = false;
              await gate.future;
            }
            return SettingsRepository(prefs).reloaded();
          },
          notifications: notifications,
          l10n: () => en,
        ).accepted(host);

        await alert().ended(host);
        gate.complete();
        await looking;

        expect(SettingsRepository(prefs).loadEdgeSessionEnded(), host);
      });
    });

    test('an ending and a recovery take turns on the marks', () async {
      // Side by side the refusal would read the marks the recovery is about to
      // clear, find them set and do nothing, and the recovery would then clear
      // them: the refusal dropped. So the second does not start until the first
      // is done.
      await timed((advance) async {
        final store = SettingsRepository(prefs);
        await store.saveEdgeSessionEnded(host, at: start);
        await store.saveEdgeSessionNotified(host);
        advance(edgeAcceptedCheckEvery * 2);

        final gate = Completer<void>();
        var reads = 0;
        final handler = EdgeSessionAlert(
          settings: () async {
            if (++reads == 1) await gate.future;
            return SettingsRepository(prefs).reloaded();
          },
          notifications: notifications,
          l10n: () => en,
        );
        final both = [handler.accepted(host), handler.ended(host)];
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(reads, 1, reason: 'the other one waits for its turn');

        gate.complete();
        await Future.wait(both);
        expect(reads, 2);
      });
    });

    test('a recovery of another host does not take this one\'s down', () async {
      await timed((advance) async {
        final handler = alert();
        await handler.ended(host);
        // Cleared behind the app's back, as another isolate would have.
        await SettingsRepository(prefs).saveEdgeSessionEnded(null);

        final recovered = <String>[];
        final sub = edgeSessionRecoveries.listen(recovered.add);
        addTearDown(sub.cancel);
        await alert().accepted('other.example.com');
        await Future<void>.delayed(Duration.zero);
        expect(recovered, ['other.example.com']);
      });
    });

    test('leaves another host\'s mark alone', () async {
      await timed((advance) async {
        final handler = alert();
        await handler.ended('other.example.com');
        final recovered = <String>[];
        final sub = edgeSessionRecoveries.listen(recovered.add);
        addTearDown(sub.cancel);
        advance(edgeAcceptedCheckEvery);
        await handler.accepted(host);
        await Future<void>.delayed(Duration.zero);
        expect(
          SettingsRepository(prefs).loadEdgeSessionEnded(),
          'other.example.com',
        );
        expect(
          recovered,
          isEmpty,
          reason: 'nothing of this host\'s to take down',
        );
      });
    });

    test(
      'tells the app also when another isolate already cleared it',
      () async {
        await timed((advance) async {
          final recovered = <String>[];
          final sub = edgeSessionRecoveries.listen(recovered.add);
          addTearDown(sub.cancel);
          await alert().accepted(host);
          await Future<void>.delayed(Duration.zero);
          expect(recovered, [host]);
        });
      },
    );

    test('the next refusal is told again', () async {
      await timed((advance) async {
        final handler = alert();
        await handler.ended(host);
        advance(edgeAcceptedCheckEvery);
        await handler.accepted(host);
        await handler.ended(host);
        expect(notifications.alerts, hasLength(2));
      });
    });

    test('is what the probe reaches once the isolate listens', () async {
      await timed((advance) async {
        alert().listen();
        await SettingsRepository(prefs).saveEdgeSessionEnded(host);
        EdgeSessionSignal.accepted(host);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(SettingsRepository(prefs).loadEdgeSessionEnded(), isNull);
      });
    });
  });

  test('a post that fails is tried again by the next request', () async {
    notifications.failWith = StateError('channel refused');
    await expectLater(
      alert().ended('printers.example.com'),
      throwsA(isA<StateError>()),
    );
    expect(SettingsRepository(prefs).loadEdgeSessionNotified(), isNull);

    notifications.failWith = null;
    await alert().ended('printers.example.com');
    // The refused attempt is recorded by the fake too.
    expect(notifications.alerts, hasLength(2));
    expect(
      SettingsRepository(prefs).loadEdgeSessionNotified(),
      'printers.example.com',
    );
  });

  test('the post is claimed before it is made', () async {
    // Another isolate looking at this moment must already see it as told.
    final watching = _Watching(prefs);
    await EdgeSessionAlert(
      settings: () => SettingsRepository(prefs).reloaded(),
      notifications: watching,
      l10n: () => en,
    ).ended('printers.example.com');
    expect(watching.seen, 'printers.example.com');
  });

  test(
    'is announced to the app, also when the mark was already there',
    () async {
      // Another isolate wrote it first while the app was open: the banner has to
      // hear it from this one, which is the only one it can hear.
      await SettingsRepository(
        prefs,
      ).saveEdgeSessionEnded('printers.example.com');
      final heard = <String>[];
      final sub = edgeSessionEndings.listen(heard.add);
      addTearDown(sub.cancel);
      await alert().ended('printers.example.com');
      expect(heard, ['printers.example.com']);
    },
  );

  test('a switched-off event counts as decided, not as pending', () async {
    await savePrefs(
      NotificationPrefs.defaults.withEvent(NotifEvent.edgeSessionEnded, false),
    );
    await alert().ended('printers.example.com');
    expect(
      SettingsRepository(prefs).loadEdgeSessionNotified(),
      'printers.example.com',
    );
  });
}

/// Reads what another isolate would, at the moment the alert is handed over.
class _Watching extends RecordingNotifications {
  _Watching(this._prefs);

  final SharedPreferences _prefs;
  String? seen;

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
    bool quiet = false,
    bool silent = false,
  }) {
    seen = SettingsRepository(_prefs).loadEdgeSessionNotified();
    return super.showAlert(
      event: event,
      printerId: printerId,
      id: id,
      title: title,
      body: body,
      payload: payload,
      actions: actions,
      picture: picture,
      quiet: quiet,
      silent: silent,
    );
  }
}
