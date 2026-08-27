import 'package:bambuddy_mobile/core/platform/platform_query.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The policy three wrappers used to each have their own version of: what an
/// absent or refusing platform means to a caller that only wanted an answer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('bambuddy/test_platform_query');
  const query = PlatformQuery(channel);
  final calls = <MethodCall>[];

  void answer(Future<Object?> Function(MethodCall call) handler) {
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

  group('ask', () {
    test('gives back what the platform said', () async {
      answer((_) async => true);

      expect(await query.ask('isSomething', fallback: false), isTrue);
      expect(calls.single.method, 'isSomething');
    });

    test('passes arguments through', () async {
      answer((_) async => 'entered');

      final result = await query.ask<String>('read',
          fallback: '', arguments: {'label': 'Server URL'});

      expect(result, 'entered');
      expect(calls.single.arguments, {'label': 'Server URL'});
    });

    test('falls back on an answer of null', () async {
      answer((_) async => null);

      expect(await query.ask('isSomething', fallback: true), isTrue);
    });

    test('falls back where the channel does not exist', () async {
      // No handler registered: another platform, or a test process.
      expect(await query.ask('isSomething', fallback: true), isTrue);
      expect(await query.ask('isSomething', fallback: false), isFalse);
    });

    test('falls back when the host refuses', () async {
      answer((_) async => throw PlatformException(code: 'no-activity'));

      expect(await query.ask('isSomething', fallback: false), isFalse);
    });
  });

  group('tell', () {
    test('reaches the platform', () async {
      answer((_) async => null);

      await query.tell('doSomething', arguments: {'enabled': true});

      expect(calls.single.method, 'doSomething');
      expect(calls.single.arguments, {'enabled': true});
    });

    test('is quiet when there is nobody to tell', () async {
      // Nothing registered, so this would throw MissingPluginException raw.
      await expectLater(query.tell('doSomething'), completes);
    });

    test('is quiet when the host refuses', () async {
      answer((_) async => throw PlatformException(code: 'denied'));

      await expectLater(query.tell('doSomething'), completes);
    });
  });
}
