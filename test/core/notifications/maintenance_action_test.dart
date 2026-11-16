import 'package:bambuddy_mobile/core/app_context.dart';
import 'package:bambuddy_mobile/core/notifications/background_api.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Mark Done" on a maintenance alert: the payload names item ids, which mean
/// something only on the server that posted the alert.
void main() {
  group('the payload', () {
    test('round-trips the items and the server', () {
      final parsed = parseMaintenancePayload(
        maintenancePayload([10, 12], serverUrl: _other),
      );
      expect(parsed.itemIds, [10, 12]);
      expect(parsed.server, serverTag(_other));
    });

    test('a bare id list from an older build names no server', () {
      final parsed = parseMaintenancePayload('10, 12');
      expect(parsed.itemIds, [10, 12]);
      expect(parsed.server, isNull);
    });

    test('anything else names no items', () {
      for (final other in [
        null,
        '',
        'printer:3',
        'maint:',
        'maint:10',
        'maint:10:',
        'maint:10:ab:cd',
        'maint:x:ab',
        'hms:1:0300:5:ab',
      ]) {
        expect(
          parseMaintenancePayload(other).itemIds,
          isEmpty,
          reason: '$other',
        );
      }
    });
  });

  // The demo profile answers from the in-process backend, so a reset that goes
  // out is one that lands, and the flag it leaves says which taps were sent.
  group('a tap on Mark Done', () {
    late SettingsRepository settings;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      settings = SettingsRepository(await SharedPreferences.getInstance());
      await settings.saveProfile(
        const ServerProfile(
          baseUrl: DemoConfig.baseUrl,
          authMode: AuthMode.none,
        ),
      );
      await settings.saveNotifiedMaintenanceDueIds({10});
    });

    NotificationResponse tap(String payload) => NotificationResponse(
      notificationResponseType:
          NotificationResponseType.selectedNotificationAction,
      id: 1,
      actionId: maintenancePerformActionId,
      payload: payload,
    );

    test('resets the item on the server that posted the alert', () async {
      await handleMaintenanceAction(
        tap(maintenancePayload([10], serverUrl: DemoConfig.baseUrl)),
      );

      expect(settings.maintenanceDirty(), isTrue);
      expect(settings.loadNotifiedMaintenanceDueIds(), isEmpty);
    });

    // The alert outlived a switch to another server, where item 10 is
    // somebody else's counter.
    test('posted by another server resets nothing here', () async {
      await handleMaintenanceAction(
        tap(maintenancePayload([10], serverUrl: _other)),
      );

      expect(settings.maintenanceDirty(), isFalse);
      expect(settings.loadNotifiedMaintenanceDueIds(), {10});
    });

    test('on an alert from an older build still resets the item', () async {
      await handleMaintenanceAction(tap('10'));

      expect(settings.maintenanceDirty(), isTrue);
    });
  });
}

const _other = 'http://192.168.1.10:8000';
