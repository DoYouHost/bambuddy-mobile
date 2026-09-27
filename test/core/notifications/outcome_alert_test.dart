import 'dart:async';

import 'package:bambuddy_mobile/core/api/ws_messages.dart';
import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/notifications/background_api.dart';
import 'package:bambuddy_mobile/core/notifications/notification_prefs.dart';
import 'package:bambuddy_mobile/core/notifications/outcome_alert.dart';
import 'package:bambuddy_mobile/core/notifications/outcome_prompt.dart';
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
      expect(alert['payload'], outcomePayload(82));
      expect(alert['actionIds'], ['outcome:good', 'outcome:reject']);
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

  group('payload and action ids', () {
    test('round-trip, and refuse anything else', () {
      expect(parseOutcomePayload(outcomePayload(82)), 82);
      for (final other in [
        null,
        '',
        'printer:3',
        'outcome:',
        'outcome:x',
        'outcome:-1',
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
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      // No server profile: a button tap stops before any request.
      SharedPreferences.setMockInitialValues({});
      takeOutcomePrompt();
    });

    NotificationResponse response({String? actionId}) => NotificationResponse(
      notificationResponseType: actionId == null
          ? NotificationResponseType.selectedNotification
          : NotificationResponseType.selectedNotificationAction,
      id: outcomeAlertId(82),
      actionId: actionId,
      payload: outcomePayload(82),
    );

    test('on the body hands the question to the app', () async {
      await handleOutcomeAction(response());

      expect(takeOutcomePrompt(), 82);
    });

    test('on a button answers it where it was tapped', () async {
      await handleOutcomeAction(response(actionId: 'outcome:good'));

      expect(takeOutcomePrompt(), isNull);
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

        expect(takeOutcomePrompt(), isNull);
      },
    );
  });
}
