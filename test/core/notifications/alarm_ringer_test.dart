import 'package:bambuddy_mobile/core/notifications/alarm_ringer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('page.codeberg.morganmlgman.bambuddy/alarm');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('ring sends what the native side reads', () async {
    MethodCall? sent;
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent = call;
      return true;
    });
    final rang = await const AlarmRinger().ring(
      id: 42,
      title: 'T',
      body: 'B',
      stopLabel: 'Stop',
      minutes: 5,
    );
    expect(rang, isTrue);
    expect(sent!.method, 'ring');
    expect(sent!.arguments, {
      'id': 42,
      'title': 'T',
      'body': 'B',
      'stop': 'Stop',
      'minutes': 5,
    });
  });

  test(
    'with no host nothing rang, and there is no permission to ask',
    () async {
      expect(
        await const AlarmRinger().ring(
          id: 1,
          title: '',
          body: '',
          stopLabel: '',
          minutes: 1,
        ),
        isFalse,
      );
      expect(await const AlarmRinger().canFullScreen(), isTrue);
    },
  );

  test('a host that refuses reads as nothing rang', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'boom'),
    );
    expect(
      await const AlarmRinger().ring(
        id: 1,
        title: '',
        body: '',
        stopLabel: '',
        minutes: 1,
      ),
      isFalse,
    );
  });
}
