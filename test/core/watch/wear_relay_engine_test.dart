import 'package:bambuddy_mobile/core/watch/wear_relay_engine.dart';
import 'package:bambuddy_mobile/core/watch/wear_rpc.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_watch_connectivity.dart';

import '../../helpers.dart';

void main() {
  // The engine reaches for prefs (a diagnostics session, the server profile)
  // before it answers anything.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Dio dio;
  late DioAdapter adapter;
  late FakeWatchConnectivity watch;
  late WearRelayEngine engine;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dio = testDio();
    adapter = DioAdapter(dio: dio);
    watch = FakeWatchConnectivity();
    engine = WearRelayEngine(watch: watch, openDio: () async => dio);
  });

  /// The map a watch on contract version [version] would send.
  Map<String, dynamic> request(WearRpcAction action, {int? version}) {
    final map = WearRpcRequest.create(action, printerId: 1).encode();
    if (version != null) map['v'] = version;
    return map;
  }

  test('answers a forwarded request with the phone\'s session', () async {
    adapter.onPost(
      '/api/v1/printers/1/print/pause',
      (s) => s.reply(200, {'ok': true}),
    );

    expect(await engine.handle(request(WearRpcAction.pause)), isTrue);
    expect(WearRpcResponse.decode(watch.sent.single)!.ok, isTrue);
  });

  test('a message that is not a request is not answered', () async {
    expect(
      await engine.handle(const WearRpcResponse.ok('x').encode()),
      isFalse,
    );
    expect(watch.sent, isEmpty);
  });

  test(
    'no server profile: answers phone-unconfigured, which means "yourself"',
    () async {
      final unconfigured = WearRelayEngine(
        watch: watch,
        openDio: () async => null,
      );

      expect(await unconfigured.handle(request(WearRpcAction.pause)), isTrue);
      expect(
        WearRpcResponse.decode(watch.sent.single)!.error,
        'phone-unconfigured',
      );
    },
  );

  group('the wake it was started for', () {
    test('runs a repeatable action from a watch that cannot wait', () async {
      // v1 has no idea the phone acked. It has given up by now, but pausing a
      // paused printer costs nothing and the state it wanted is reached.
      adapter.onPost(
        '/api/v1/printers/1/print/pause',
        (s) => s.reply(200, {'ok': true}),
      );

      expect(
        await engine.handle(request(WearRpcAction.pause, version: 1)),
        isTrue,
      );
      expect(watch.sent, hasLength(1));
    });

    test('refuses startNext from a watch that cannot wait', () async {
      // The watch timed out before this could answer, so its user's retry
      // would be the second start — and that one prints another plate.
      expect(
        await engine.handle(request(WearRpcAction.startNext, version: 1)),
        isFalse,
      );
      expect(watch.sent, isEmpty);
    });

    test('runs startNext from a watch that waits for the ack', () async {
      adapter.onGet('/api/v1/queue/', (s) => s.reply(200, []));

      // Reaches the queue (and fails there on an empty one), which is what
      // says the gate let it through rather than dropping it.
      expect(
        await engine.handle(
          request(WearRpcAction.startNext, version: wearRpcWakeAwareVersion),
        ),
        isTrue,
      );
      expect(WearRpcResponse.decode(watch.sent.single)!.error, 'empty-queue');
    });

    test(
      'gates only the first request — a warm engine answers every one',
      () async {
        adapter
          ..onPost(
            '/api/v1/printers/1/print/pause',
            (s) => s.reply(200, {'ok': true}),
          )
          ..onGet('/api/v1/queue/', (s) => s.reply(200, []));

        await engine.handle(request(WearRpcAction.pause, version: 1));
        // Same v1 watch, second tap: the engine is up and answers in
        // milliseconds, so there is nothing left to protect it from.
        expect(
          await engine.handle(request(WearRpcAction.startNext, version: 1)),
          isTrue,
        );
        expect(watch.sent, hasLength(2));
      },
    );
  });
}
