import 'package:bambuddy_mobile/core/notifications/background_api.dart';
import 'package:bambuddy_mobile/core/notifications/hms_stop_request.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Stop printing" from a notification is the one action that must not happen
/// on the tap that asked for it: it abandons a print, and the shade has nowhere
/// to ask "are you sure". So the handler parks it and the app shell confirms.
NotificationResponse _tap(String action, {String? payload}) =>
    NotificationResponse(
      notificationResponseType:
          NotificationResponseType.selectedNotificationAction,
      id: 8001,
      actionId: 'hms:$action',
      payload: payload ?? 'hms:3:03008004:746795586',
    );

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // No server profile → the handler cannot build a client and stops before
    // any network call. That is exactly the path under test here.
    SharedPreferences.setMockInitialValues({});
    takeHmsStop();
  });

  test('a stop tap is parked for the app instead of being sent', () async {
    await handleHmsAction(_tap('STOP_PRINTING'));

    final parked = takeHmsStop();
    expect(parked?.printerId, 3);
    expect(parked?.fullCode, '03008004');
    expect(parked?.jobId, '746795586');
  });

  test('the parked request is handed out once', () async {
    await handleHmsAction(_tap('STOP_PRINTING'));

    expect(takeHmsStop(), isNotNull);
    expect(takeHmsStop(), isNull, reason: 'one tap must not ask twice');
  });

  test('every other action goes straight through, parking nothing', () async {
    await handleHmsAction(_tap('RESUME_PRINTING'));
    expect(takeHmsStop(), isNull);
  });

  test('a tap whose payload names no fault is dropped', () async {
    await handleHmsAction(_tap('STOP_PRINTING', payload: 'printer:3'));
    expect(takeHmsStop(), isNull);
  });

  test('a maintenance tap is none of this handler\'s business', () async {
    await handleHmsAction(NotificationResponse(
      notificationResponseType:
          NotificationResponseType.selectedNotificationAction,
      id: 1,
      actionId: maintenancePerformActionId,
      payload: '4',
    ));
    expect(takeHmsStop(), isNull);
  });
}
