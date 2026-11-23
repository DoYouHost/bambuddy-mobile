import 'package:bambuddy_mobile/core/notifications/notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

// What reaches the platform when the app takes an alert back: the plugin's own
// `cancel` for that id, and nothing else.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    // The plugin picks its Android half by platform, and only that half talks
    // over the channel.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('cancelAlert cancels that notification id', () async {
    await LocalNotificationService().cancelAlert(19 * alertBandWidth);

    final cancels = calls.where((c) => c.method == 'cancel').toList();
    expect(cancels, hasLength(1));
    expect((cancels.single.arguments as Map)['id'], 19 * alertBandWidth);
  });
}
