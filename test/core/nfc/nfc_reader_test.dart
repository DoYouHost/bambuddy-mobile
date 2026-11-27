import 'package:bambuddy_mobile/core/nfc/nfc_reader.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _method = MethodChannel('page.codeberg.morganmlgman.bambuddy/nfc');
const _tags = EventChannel('page.codeberg.morganmlgman.bambuddy/nfc_tags');

/// A phone with NFC on: the stream only starts after that answer.
void _nfcIsReady() => TestDefaultBinaryMessengerBinding
    .instance
    .defaultBinaryMessenger
    .setMockMethodCallHandler(_method, (_) async => 'ready');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(_method, null);
    messenger.setMockStreamHandler(_tags, null);
  });

  group('status', () {
    for (final (answer, expected) in [
      ('ready', NfcStatus.ready),
      ('disabled', NfcStatus.disabled),
      ('unsupported', NfcStatus.unsupported),
      ('something new', NfcStatus.unsupported),
    ]) {
      test('"$answer" reads as $expected', () async {
        messenger.setMockMethodCallHandler(_method, (call) async {
          expect(call.method, 'status');
          return answer;
        });

        expect(await ChannelNfcReader().status(), expected);
      });
    }

    test('no host for the channel is unsupported, not a crash', () async {
      expect(await ChannelNfcReader().status(), NfcStatus.unsupported);
    });

    test('a refusal from the host is unsupported too', () async {
      messenger.setMockMethodCallHandler(
        _method,
        (_) async => throw PlatformException(code: 'boom'),
      );

      expect(await ChannelNfcReader().status(), NfcStatus.unsupported);
    });

    test('a null answer is unsupported', () async {
      messenger.setMockMethodCallHandler(_method, (_) async => null);

      expect(await ChannelNfcReader().status(), NfcStatus.unsupported);
    });
  });

  test('the settings page is asked for, and a missing host is fine', () async {
    final asked = <String>[];
    messenger.setMockMethodCallHandler(_method, (call) async {
      asked.add(call.method);
      return null;
    });

    await ChannelNfcReader().openSettings();
    expect(asked, ['openSettings']);

    messenger.setMockMethodCallHandler(_method, null);
    await ChannelNfcReader().openSettings();
  });

  group('tags', () {
    test('each UID comes out as the server keys it', () async {
      _nfcIsReady();
      messenger.setMockStreamHandler(
        _tags,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events
              ..success('04a1b2c3d4e5f6')
              ..success('04:A1:B2:C3')
              ..success('00112233445566778899AABB')
              ..endOfStream();
          },
        ),
      );

      expect(await ChannelNfcReader().tags().toList(), [
        '04A1B2C3D4E5F6',
        '04A1B2C3',
        '445566778899AABB',
      ]);
    });

    test('an empty or non-hex UID is dropped, not sent on', () async {
      _nfcIsReady();
      messenger.setMockStreamHandler(
        _tags,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events
              ..success('')
              ..success('zz')
              ..success('A1')
              ..endOfStream();
          },
        ),
      );

      expect(await ChannelNfcReader().tags().toList(), ['A1']);
    });

    test('reading starts with the listener and stops with it', () async {
      _nfcIsReady();
      var listening = false;
      messenger.setMockStreamHandler(
        _tags,
        MockStreamHandler.inline(
          onListen: (arguments, events) => listening = true,
          onCancel: (arguments) => listening = false,
        ),
      );
      final reader = ChannelNfcReader();
      expect(listening, isFalse);

      final subscription = reader.tags().listen((_) {});
      await Future<void>.delayed(Duration.zero);
      expect(listening, isTrue);

      await subscription.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(listening, isFalse);
    });

    test('two listeners share one read, and it stops with the last', () async {
      _nfcIsReady();
      MockStreamHandlerEventSink? host;
      var cancels = 0;
      messenger.setMockStreamHandler(
        _tags,
        MockStreamHandler.inline(
          onListen: (arguments, events) => host = events,
          onCancel: (arguments) => cancels++,
        ),
      );
      final reader = ChannelNfcReader();
      final first = <String>[];
      final second = <String>[];
      Future<void> settle() => Future<void>.delayed(Duration.zero);

      final a = reader.tags().listen(first.add);
      final b = reader.tags().listen(second.add);
      await settle();
      await settle();
      host!.success('04AA');
      await settle();
      expect(first, ['04AA']);
      expect(second, ['04AA']);

      // The first one leaving must not take the second one's events with it.
      await a.cancel();
      await settle();
      expect(cancels, 0);
      host!.success('04BB');
      await settle();
      expect(second, ['04AA', '04BB']);
      expect(first, ['04AA']);

      await b.cancel();
      await settle();
      expect(cancels, 1);
    });

    test('NFC going off meanwhile is an error the listener can read', () async {
      _nfcIsReady();
      messenger.setMockStreamHandler(
        _tags,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events
              ..error(code: 'nfc_unavailable', message: 'NFC is off')
              ..endOfStream();
          },
        ),
      );

      await expectLater(
        ChannelNfcReader().tags(),
        emitsError(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'nfc_unavailable',
          ),
        ),
      );
    });

    test(
      'a build without the channel ends the stream, with no error',
      () async {
        expect(await ChannelNfcReader().tags().toList(), isEmpty);
      },
    );
  });
}
