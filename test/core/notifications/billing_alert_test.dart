import 'dart:async';

import 'package:bambuddy_mobile/core/api/ws_messages.dart';
import 'package:bambuddy_mobile/core/notifications/billing_alert.dart';
import 'package:bambuddy_mobile/core/notifications/notification_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// What the foreground service says when the server reports a billing problem
/// on a printer: a print the kill switch stopped, or one it could not charge.
void main() {
  late StreamController<WsBillingAlert> frames;
  late RecordingNotifications notifications;

  setUp(() {
    frames = StreamController<WsBillingAlert>.broadcast();
    notifications = RecordingNotifications();
  });
  tearDown(() => frames.close());

  Future<void> send(
    WsBillingAlert alert, {
    NotificationPrefs prefs = NotificationPrefs.defaults,
  }) async {
    final sub = listenForBillingAlerts(
      frames.stream,
      notifications: notifications,
      prefs: prefs,
      l10n: () => en,
    );
    addTearDown(sub.cancel);
    frames.add(alert);
    await Future<void>.delayed(Duration.zero);
  }

  test('a stopped print names the printer and the file', () async {
    await send(
      const WsBillingAlert(BillingAlertKind.killSwitch, 2, 'P1S', 'Benchy.3mf'),
    );

    final alert = notifications.alerts.single;
    expect(alert['event'], NotifEvent.billingAlert);
    expect(alert['printerId'], 2);
    expect(alert['title'], en.notifBillingKillTitle);
    expect(alert['body'], en.notifBillingKillBody('P1S', 'Benchy.3mf'));
    expect(alert['payload'], 'printer:2');
  });

  test('a failed charge says so, and that the reservation was kept', () async {
    await send(
      const WsBillingAlert(
        BillingAlertKind.chargeFailed,
        2,
        'P1S',
        'Benchy.3mf',
        archiveId: 91,
      ),
    );

    final alert = notifications.alerts.single;
    expect(alert['title'], en.notifBillingChargeTitle);
    expect(alert['body'], en.notifBillingChargeBody('P1S', 'Benchy.3mf'));
    // The generated method takes the printer first but says the file first; the
    // line above would pass with the two swapped, this one would not.
    final body = alert['body']! as String;
    expect(body.indexOf('Benchy.3mf'), lessThan(body.indexOf('P1S')));
  });

  // `main.py` fills a missing file name with the English word, not with null.
  test('the server\'s own "Unknown" reads as a missing file name', () async {
    await send(
      const WsBillingAlert(BillingAlertKind.chargeFailed, 2, 'P1S', 'Unknown'),
    );

    expect(
      notifications.alerts.single['body'],
      en.notifBillingChargeBody('P1S', en.notifBillingUnknownFile),
    );
  });

  test('a frame with no names still reads as a sentence', () async {
    await send(const WsBillingAlert(BillingAlertKind.killSwitch, 2, ' ', null));

    expect(
      notifications.alerts.single['body'],
      en.notifBillingKillBody(en.printersTitle, en.notifBillingUnknownFile),
    );
  });

  // Two prints failing to charge on one printer are two problems; one printer
  // stopped twice is the same one.
  test('alert ids: a charge per archive, a kill per printer', () {
    int id(BillingAlertKind kind, int printer, {int? archive}) =>
        billingAlertId(
          WsBillingAlert(kind, printer, null, null, archiveId: archive),
        );

    expect(
      id(BillingAlertKind.chargeFailed, 2, archive: 91),
      isNot(id(BillingAlertKind.chargeFailed, 2, archive: 92)),
    );
    expect(
      billingAlertId(
        const WsBillingAlert(BillingAlertKind.killSwitch, 2, 'P1S', 'a.3mf'),
      ),
      billingAlertId(
        const WsBillingAlert(BillingAlertKind.killSwitch, 2, 'P1S', 'b.3mf'),
      ),
    );
    expect(
      id(BillingAlertKind.killSwitch, 2),
      isNot(id(BillingAlertKind.chargeFailed, 2, archive: 2)),
    );
  });

  test('switched off, nothing is posted', () async {
    await send(
      const WsBillingAlert(BillingAlertKind.killSwitch, 2, 'P1S', 'a.3mf'),
      prefs: NotificationPrefs.defaults.withEvent(
        NotifEvent.billingAlert,
        false,
      ),
    );

    expect(notifications.alerts, isEmpty);
  });

  test('alerts switched off as a whole silence it too', () async {
    await send(
      const WsBillingAlert(BillingAlertKind.chargeFailed, 2, 'P1S', 'a.3mf'),
      prefs: NotificationPrefs.defaults.copyWith(alertsEnabled: false),
    );

    expect(notifications.alerts, isEmpty);
  });

  // A new switch reaches an install that saved its choices before it existed
  // with the default it ships with, which is on.
  test('an install from before the switch gets it on', () {
    final saved = NotificationPrefs.decode(
      '{"enabled":["printFinished"],"known":["printFinished"]}',
    );
    expect(saved.isOn(NotifEvent.billingAlert), isTrue);
  });
}
