import 'package:bambuddy_mobile/core/watch/wear_text_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel =
      MethodChannel('page.codeberg.morganmlgman.bambuddy/wear_input');
  final calls = <MethodCall>[];

  void mockChannel(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('isSupported', () {
    test('reports what the platform says', () async {
      mockChannel((_) async => true);
      expect(await WearTextInput().isSupported(), isTrue);

      mockChannel((_) async => false);
      expect(await WearTextInput().isSupported(), isFalse);
    });

    test('is false where the channel does not exist', () async {
      // No handler registered: a phone build of the tests, or any host platform.
      expect(await WearTextInput().isSupported(), isFalse);
    });
  });

  group('request', () {
    test('passes the label through and returns what was entered', () async {
      mockChannel((_) async => 'http://printer.local:8000');

      final text = await WearTextInput().request(label: 'Server URL');

      expect(text, 'http://printer.local:8000');
      expect(calls.single.method, 'requestText');
      expect(calls.single.arguments, {'label': 'Server URL'});
    });

    test('returns null when the user backs out', () async {
      mockChannel((_) async => null);
      expect(await WearTextInput().request(label: 'Server URL'), isNull);
    });

    test('returns null when a request is already open', () async {
      mockChannel((_) async => throw PlatformException(code: 'busy'));
      expect(await WearTextInput().request(label: 'Server URL'), isNull);
    });

    test('signals unavailable so the caller can fall back', () async {
      mockChannel((_) async => throw PlatformException(code: 'unavailable'));
      expect(
        WearTextInput().request(label: 'Server URL'),
        throwsA(isA<WearTextInputUnavailable>()),
      );
    });

    test('signals unavailable when the channel is missing entirely', () async {
      expect(
        WearTextInput().request(label: 'Server URL'),
        throwsA(isA<WearTextInputUnavailable>()),
      );
    });
  });
}
