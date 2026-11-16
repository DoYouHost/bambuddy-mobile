import 'dart:io';

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
      await settings.saveNotifiedMaintenanceDueIds({
        10,
      }, serverUrl: DemoConfig.baseUrl);
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

  // The reset is a request, and the app can be switched to another server
  // while it is in the air. What the handler does to the dedup set afterwards
  // would be done to the new server's set.
  group('a server change while Mark Done is in flight', () {
    late HttpServer server;
    late SettingsRepository settings;
    late String url;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      // The binding answers every request with a 400 of its own.
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      settings = SettingsRepository(await SharedPreferences.getInstance());
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      url = 'http://127.0.0.1:${server.port}';
      await settings.saveProfile(
        ServerProfile(baseUrl: url, authMode: AuthMode.none),
      );
      server.listen((request) async {
        // The other server's own announced items, written as the UI would.
        await settings.saveProfile(
          const ServerProfile(baseUrl: _other, authMode: AuthMode.none),
        );
        await settings.saveNotifiedMaintenanceDueIds({
          10,
          12,
        }, serverUrl: _other);
        request.response.headers.contentType = ContentType.json;
        request.response.write('{}');
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('leaves the new server\'s dedup set alone', () async {
      await handleMaintenanceAction(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          id: 1,
          actionId: maintenancePerformActionId,
          payload: maintenancePayload([10], serverUrl: url),
        ),
      );

      expect(settings.loadNotifiedMaintenanceDueIds(), {10, 12});
    });
  });
}

const _other = 'http://192.168.1.10:8000';
