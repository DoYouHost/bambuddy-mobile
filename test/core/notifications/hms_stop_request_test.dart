import 'package:bambuddy_mobile/core/notifications/background_api.dart';
import 'package:bambuddy_mobile/core/notifications/hms_stop_request.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
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
      payload:
          payload ??
          hmsPayload(
            printerId: 3,
            fullCode: '03008004',
            jobId: '746795586',
            serverUrl: _server,
          ),
    );

/// Nothing listens there: a tap that got past the checks fails its request,
/// which the handler records and swallows.
const _server = 'http://127.0.0.1:9';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await SettingsRepository(await SharedPreferences.getInstance()).saveProfile(
      const ServerProfile(baseUrl: _server, authMode: AuthMode.none),
    );
    hmsStopRequests.take();
  });

  // The shell would confirm and send the stop to the server the app is on
  // now — where printer 3 is somebody else's.
  test('a stop tap from another server is not parked', () async {
    await handleHmsAction(
      _tap(
        'STOP_PRINTING',
        payload: hmsPayload(
          printerId: 3,
          fullCode: '03008004',
          serverUrl: 'http://other:8000',
        ),
      ),
    );

    expect(hmsStopRequests.take(), isNull);
  });

  test('a stop tap is parked for the app instead of being sent', () async {
    await handleHmsAction(_tap('STOP_PRINTING'));

    final parked = hmsStopRequests.take();
    expect(parked?.printerId, 3);
    expect(parked?.fullCode, '03008004');
    expect(parked?.jobId, '746795586');
  });

  test('the parked request is handed out once', () async {
    await handleHmsAction(_tap('STOP_PRINTING'));

    expect(hmsStopRequests.take(), isNotNull);
    expect(
      hmsStopRequests.take(),
      isNull,
      reason: 'one tap must not ask twice',
    );
  });

  test('every other action goes straight through, parking nothing', () async {
    await handleHmsAction(_tap('RESUME_PRINTING'));
    expect(hmsStopRequests.take(), isNull);
  });

  test('a tap whose payload names no fault is dropped', () async {
    await handleHmsAction(_tap('STOP_PRINTING', payload: 'printer:3'));
    expect(hmsStopRequests.take(), isNull);
  });

  test('a maintenance tap is none of this handler\'s business', () async {
    await handleHmsAction(
      NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        id: 1,
        actionId: maintenancePerformActionId,
        payload: '4',
      ),
    );
    expect(hmsStopRequests.take(), isNull);
  });
}
