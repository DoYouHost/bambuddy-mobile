import 'dart:async';

import 'package:bambuddy_mobile/core/api/ws_messages.dart';
import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/notifications/background_api.dart';
import 'package:bambuddy_mobile/core/notifications/finish_alert_memory.dart';
import 'package:bambuddy_mobile/core/notifications/notification_prefs.dart';
import 'package:bambuddy_mobile/core/notifications/notification_service.dart';
import 'package:bambuddy_mobile/core/notifications/outcome_alert.dart';
import 'package:bambuddy_mobile/core/notifications/outcome_prompt.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/l10n/app_localizations_en.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// The outcome question from the foreground service (#1898): one notification
/// per request, Good and Reject answered from the shade, the body handed to
/// the app's sheet.
void main() {
  final l10n = AppLocalizationsEn();

  group('the notification', () {
    late StreamController<WsPrintConfirmRequest> frames;
    late RecordingNotifications notifications;

    setUp(() {
      frames = StreamController<WsPrintConfirmRequest>.broadcast();
      notifications = RecordingNotifications();
    });
    tearDown(() => frames.close());

    Future<void> send(
      WsPrintConfirmRequest request, {
      NotificationPrefs prefs = NotificationPrefs.defaults,
    }) async {
      final sub = listenForOutcomeRequests(
        frames.stream,
        notifications: notifications,
        prefs: prefs,
        serverUrl: _server,
        l10n: () => l10n,
      );
      addTearDown(sub.cancel);
      frames.add(request);
      await Future<void>.delayed(Duration.zero);
    }

    test('asks about the print by name, with both answers on it', () async {
      await send(const WsPrintConfirmRequest(3, 82, 'Benchy'));

      final alert = notifications.alerts.single;
      expect(alert['event'], NotifEvent.outcomeRequest);
      expect(alert['printerId'], 3);
      expect(alert['id'], outcomeAlertId(82));
      expect(alert['title'], l10n.outcomeNotifTitle('Benchy'));
      expect(alert['payload'], outcomePayload(82, _server));
      expect(alert['actionIds'], ['outcome:good', 'outcome:reject']);
    });

    test(
      'a finished alert still on screen takes the question instead',
      () async {
        final sub = listenForOutcomeRequests(
          frames.stream,
          notifications: notifications,
          prefs: NotificationPrefs.defaults,
          serverUrl: _server,
          addToFinished:
              ({
                required archiveId,
                required printerId,
                required payload,
                required actions,
              }) async => true,
          l10n: () => l10n,
        );
        addTearDown(sub.cancel);
        frames.add(const WsPrintConfirmRequest(3, 82, 'Benchy'));
        await Future<void>.delayed(Duration.zero);

        expect(notifications.alerts, isEmpty);
      },
    );

    // The server asks once; a tap that failed must leave something to tap.
    test('the buttons do not take the notification away themselves', () async {
      await send(const WsPrintConfirmRequest(3, 82, 'Benchy'));

      final actions =
          notifications.alerts.single['actions']! as List<NotificationAction>;
      expect(actions.map((a) => a.dismisses), everyElement(isFalse));
    });

    test('a print with no name still gets a question', () async {
      await send(const WsPrintConfirmRequest(3, 82, null));

      expect(notifications.alerts.single['title'], l10n.outcomeTitle);
    });

    test('switched off, nothing is posted', () async {
      await send(
        const WsPrintConfirmRequest(3, 82, 'Benchy'),
        prefs: NotificationPrefs.defaults.withEvent(
          NotifEvent.outcomeRequest,
          false,
        ),
      );

      expect(notifications.alerts, isEmpty);
    });

    // A new switch reaches an install that saved its choices before it
    // existed with the default it ships with, which is on.
    test('an install from before the switch gets it on', () {
      final saved = NotificationPrefs.decode(
        '{"enabled":["printFinished"],"known":["printFinished"]}',
      );
      expect(saved.isOn(NotifEvent.outcomeRequest), isTrue);
    });
  });

  // Answered in the app or by a button: the entry goes, or a photo landing
  // later would bring the answered notification back. Here the plugin is
  // missing and every cancel throws, which must not stop the forgetting.
  test(
    'an answer forgets the finished alert that carried the buttons',
    () async {
      SharedPreferences.setMockInitialValues({});
      final memory = FinishAlertMemory(await SharedPreferences.getInstance());
      await memory.remember(
        PostedAlert(
          event: NotifEvent.printFinished,
          printerId: 3,
          id: 1000003,
          title: 't',
          body: 'b',
          payload: outcomePayload(82, _server),
          postedAt: DateTime.now(),
        ),
      );

      await cancelOutcomeAlert(82, memory: memory);

      expect(await memory.entries(), isEmpty);
    },
  );

  group('payload and action ids', () {
    test('round-trip, and refuse anything else', () {
      expect(parseOutcomePayload(outcomePayload(82, _server)), (
        archiveId: 82,
        server: outcomeServerTag(_server),
      ));
      for (final other in [
        null,
        '',
        'printer:3',
        'outcome:',
        'outcome:82',
        'outcome:x:ab',
        'outcome:-1:ab',
        'outcome:82:',
      ]) {
        expect(parseOutcomePayload(other), isNull, reason: '$other');
      }
      expect(outcomeActionVerdict('outcome:good'), PrintVerdict.good);
      expect(outcomeActionVerdict('outcome:reject'), PrintVerdict.reject);
      expect(outcomeActionVerdict('outcome:meh'), isNull);
      expect(outcomeActionVerdict('hms:RESUME_PRINTING'), isNull);
      expect(outcomeActionVerdict(null), isNull);
    });

    // Its own band: an id shared with another alert would replace it.
    test('the id stays inside its band', () {
      expect(outcomeAlertId(82), 14000082);
      expect(outcomeAlertId(1000082), 14000082);
    });
  });

  group('a tap', () {
    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      // A server nothing listens on: a button tap fails its request, which
      // the handler records and swallows.
      await SettingsRepository(
        await SharedPreferences.getInstance(),
      ).saveProfile(
        const ServerProfile(baseUrl: _server, authMode: AuthMode.none),
      );
      outcomePrompts.take();
    });

    NotificationResponse response({
      String? actionId,
      String server = _server,
    }) => NotificationResponse(
      notificationResponseType: actionId == null
          ? NotificationResponseType.selectedNotification
          : NotificationResponseType.selectedNotificationAction,
      id: outcomeAlertId(82),
      actionId: actionId,
      payload: outcomePayload(82, server),
    );

    // The notification outlived a switch to another server, where archive 82
    // is somebody else's print.
    test('asked by another server, it asks nothing here', () async {
      await handleOutcomeAction(response(server: 'http://other:8000'));

      expect(outcomePrompts.take(), isNull);
    });

    test('on the body hands the question to the app', () async {
      await handleOutcomeAction(response());

      expect(outcomePrompts.take(), 82);
    });

    test('on a button answers it where it was tapped', () async {
      await handleOutcomeAction(response(actionId: 'outcome:good'));

      expect(outcomePrompts.take(), isNull);
    });

    test(
      'on another notification is none of this handler\'s business',
      () async {
        await handleOutcomeAction(
          NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            id: 1,
            payload: 'printer:3',
          ),
        );

        expect(outcomePrompts.take(), isNull);
      },
    );
  });
}

const _server = 'http://127.0.0.1:9';
