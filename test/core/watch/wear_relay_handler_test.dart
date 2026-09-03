import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/core/watch/wear_relay_claim.dart';
import 'package:bambuddy_mobile/core/watch/wear_relay_handler.dart';
import 'package:bambuddy_mobile/core/watch/wear_rpc.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_watch_connectivity.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late FakeWatchConnectivity watch;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    watch = FakeWatchConnectivity();
  });

  /// Delivers [request] to the handler and returns its (single) reply.
  Future<WearRpcResponse> roundTrip(
    WearRelayHandler handler,
    WearRpcRequest request,
  ) async {
    await handler.start();
    watch.deliver(request.encode());
    await pumpEventQueue();
    expect(watch.sent, hasLength(1));
    return WearRpcResponse.decode(watch.sent.single)!;
  }

  test('getFleet: raw list + statuses pass through, correlated id', () async {
    adapter
      ..onGet('/api/v1/printers/',
          (s) => s.reply(200, [
                {'id': 1, 'name': 'X1C'},
                {'id': 2, 'name': 'P1S'},
              ]))
      ..onGet('/api/v1/printers/1/status',
          (s) => s.reply(200, {'id': 1, 'state': 'RUNNING'}))
      ..onGet('/api/v1/printers/2/status',
          (s) => s.reply(500, {'detail': 'offline'}));
    final handler = WearRelayHandler(watch: watch, dio: () => dio);

    final req = WearRpcRequest.create(WearRpcAction.getFleet);
    final res = await roundTrip(handler, req);

    expect(res.id, req.id);
    expect(res.ok, isTrue);
    final printers = res.data!['printers'] as List;
    expect(printers, hasLength(2));
    final first = printers[0] as Map<String, dynamic>;
    expect((first['status'] as Map<String, dynamic>)['state'], 'RUNNING');
    // Failed status fetch drops only that printer's status.
    final second = printers[1] as Map<String, dynamic>;
    expect(second.containsKey('status'), isFalse);
  });

  test('getFleet: queuePending counts only pending items (printing excluded)',
      () async {
    adapter
      ..onGet('/api/v1/printers/', (s) => s.reply(200, <dynamic>[]))
      ..onGet(
          '/api/v1/queue/',
          (s) => s.reply(200, [
                {'id': 1, 'position': 1, 'status': 'pending'},
                {'id': 2, 'position': 2, 'status': 'printing'},
                {'id': 3, 'position': 3, 'status': 'completed'},
                {'id': 4, 'position': 4, 'status': 'pending'},
              ]));
    final handler = WearRelayHandler(watch: watch, dio: () => dio);

    final res =
        await roundTrip(handler, WearRpcRequest.create(WearRpcAction.getFleet));

    expect(res.data!['queuePending'], 2);
  });

  test('getFleet: asks the server for pending only, not the whole history',
      () async {
    // Unfiltered, this endpoint answers with every print ever queued — 218 kB
    // on a real server — for a number the watch renders as one digit. The mock
    // matches only the filtered request, so dropping the filter fails here.
    adapter
      ..onGet('/api/v1/printers/', (s) => s.reply(200, <dynamic>[]))
      ..onGet(
        '/api/v1/queue/',
        (s) => s.reply(200, [
          {'id': 1, 'position': 1, 'status': 'pending'},
        ]),
        queryParameters: {'status': 'pending'},
      );
    final handler = WearRelayHandler(watch: watch, dio: () => dio);

    final res =
        await roundTrip(handler, WearRpcRequest.create(WearRpcAction.getFleet));

    expect(res.data!['queuePending'], 1);
  });

  test('getFleet: failed queue fetch omits queuePending (unknown, not zero)',
      () async {
    adapter.onGet('/api/v1/printers/', (s) => s.reply(200, <dynamic>[]));
    // /api/v1/queue/ is unmocked → the fetch fails → key absent.
    final handler = WearRelayHandler(watch: watch, dio: () => dio);

    final res =
        await roundTrip(handler, WearRpcRequest.create(WearRpcAction.getFleet));

    expect(res.ok, isTrue);
    expect(res.data!.containsKey('queuePending'), isFalse);
  });

  test('getFleet: liveStatus cache short-circuits the REST status fetch',
      () async {
    // Only the list route is mocked — a REST status fetch would 404 and the
    // status would be dropped, so a present status proves the cache was used.
    adapter.onGet('/api/v1/printers/',
        (s) => s.reply(200, [
              {'id': 7, 'name': 'X1C'},
            ]));
    final handler = WearRelayHandler(
      watch: watch,
      dio: () => dio,
      liveStatus: (id) => id == 7 ? {'id': 7, 'state': 'PAUSE'} : null,
    );

    final res =
        await roundTrip(handler, WearRpcRequest.create(WearRpcAction.getFleet));

    final printer =
        (res.data!['printers'] as List).single as Map<String, dynamic>;
    expect((printer['status'] as Map<String, dynamic>)['state'], 'PAUSE');
  });

  test('clear-plate lowers the gate in the cache the watch reads back',
      () async {
    // The printer this happens on is off (Auto Power Off), so the server has no
    // MQTT client for it and pushes no frame when the gate goes down. Without
    // this the watch's own refresh right after the tap would read the stale
    // `true` back out of the cache and draw the button again — and the second
    // tap gets a 400.
    adapter
      ..onPost('/api/v1/printers/7/clear-plate', (s) => s.reply(200, {'ok': true}))
      ..onGet('/api/v1/printers/',
          (s) => s.reply(200, [
                {'id': 7, 'name': 'X1C'},
              ]));
    final cached = <int, Map<String, dynamic>>{
      7: {'id': 7, 'connected': false, 'awaiting_plate_clear': true},
    };
    final handler = WearRelayHandler(
      watch: watch,
      dio: () => dio,
      liveStatus: (id) => cached[id],
      plateGateAcknowledged: (id) => cached[id]?['awaiting_plate_clear'] = false,
    );

    final ack = await roundTrip(
        handler, WearRpcRequest.create(WearRpcAction.clearPlate, printerId: 7));
    expect(ack.ok, isTrue);

    watch.sent.clear();
    final fleet =
        await roundTrip(handler, WearRpcRequest.create(WearRpcAction.getFleet));
    final printer =
        (fleet.data!['printers'] as List).single as Map<String, dynamic>;
    expect((printer['status'] as Map<String, dynamic>)['awaiting_plate_clear'],
        isFalse);
  });

  test('command executes the POST and replies ok', () async {
    adapter.onPost(
        '/api/v1/printers/3/print/pause', (s) => s.reply(200, {'ok': true}));
    final handler = WearRelayHandler(watch: watch, dio: () => dio);

    final res = await roundTrip(
        handler, WearRpcRequest.create(WearRpcAction.pause, printerId: 3));

    expect(res.ok, isTrue);
  });

  test('no profile → phone-unconfigured', () async {
    final handler = WearRelayHandler(watch: watch, dio: () => null);

    final res =
        await roundTrip(handler, WearRpcRequest.create(WearRpcAction.getFleet));

    expect(res.ok, isFalse);
    expect(res.error, 'phone-unconfigured');
  });

  test('command without printerId → bad-request', () async {
    final handler = WearRelayHandler(watch: watch, dio: () => dio);

    final res =
        await roundTrip(handler, WearRpcRequest.create(WearRpcAction.stop));

    expect(res.ok, isFalse);
    expect(res.error, 'bad-request');
  });

  test('server 403 → short error code, not a crash', () async {
    adapter.onPost(
        '/api/v1/printers/3/print/stop', (s) => s.reply(403, {'detail': 'no'}));
    final handler = WearRelayHandler(watch: watch, dio: () => dio);

    final res = await roundTrip(
        handler, WearRpcRequest.create(WearRpcAction.stop, printerId: 3));

    expect(res.ok, isFalse);
    expect(res.error, 'forbidden');
  });

  test('startNext on empty queue → empty-queue', () async {
    adapter.onGet('/api/v1/queue/', (s) => s.reply(200, <dynamic>[]));
    final handler = WearRelayHandler(watch: watch, dio: () => dio);

    final res = await roundTrip(
        handler, WearRpcRequest.create(WearRpcAction.startNext, printerId: 1));

    expect(res.ok, isFalse);
    expect(res.error, 'empty-queue');
  });

  test('hmsAction relays the fault verbatim to the server', () async {
    Map<String, dynamic>? body;
    adapter.onPost(
      '/api/v1/printers/3/hms/execute-action',
      (s) => s.reply(200, {'success': true}),
      data: Matchers.any,
    );
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (options.path.endsWith('hms/execute-action')) {
        body = options.data as Map<String, dynamic>;
      }
      handler.next(options);
    }));
    final handler = WearRelayHandler(watch: watch, dio: () => dio);

    final res = await roundTrip(
      handler,
      WearRpcRequest.create(
        WearRpcAction.hmsAction,
        printerId: 3,
        printError: '03008004',
        hmsAction: 'RESUME_PRINTING',
        jobId: '746795586',
      ),
    );

    expect(res.ok, isTrue);
    // The firmware matches on this code; a phone that rewrote it would have the
    // printer drop the command without a word.
    expect(body, {
      'print_error': '03008004',
      'action': 'RESUME_PRINTING',
      'job_id': '746795586',
    });
  });

  test('hmsClear needs nothing but the printer', () async {
    adapter.onPost(
        '/api/v1/printers/3/hms/clear', (s) => s.reply(200, {'success': true}));
    final handler = WearRelayHandler(watch: watch, dio: () => dio);

    final res = await roundTrip(
        handler, WearRpcRequest.create(WearRpcAction.hmsClear, printerId: 3));

    expect(res.ok, isTrue);
  });

  test('hmsAction without a code or action → bad-request, no call', () async {
    final handler = WearRelayHandler(watch: watch, dio: () => dio);

    final res = await roundTrip(
      handler,
      WearRpcRequest.create(WearRpcAction.hmsAction, printerId: 3),
    );

    expect(res.ok, isFalse);
    expect(res.error, 'bad-request');
  });

  test('the printer not answering an action surfaces as its own code',
      () async {
    // The route waits 2.5s for the printer and 502s when it stays silent —
    // "the command went out and nothing came back", which the watch words
    // differently from a refusal.
    adapter.onPost(
      '/api/v1/printers/3/hms/execute-action',
      (s) => s.reply(502, {'detail': 'Printer did not acknowledge HMS action'}),
      data: Matchers.any,
    );
    final handler = WearRelayHandler(watch: watch, dio: () => dio);

    final res = await roundTrip(
      handler,
      WearRpcRequest.create(
        WearRpcAction.hmsAction,
        printerId: 3,
        printError: '03008004',
        hmsAction: 'RESUME_PRINTING',
      ),
    );

    expect(res.ok, isFalse);
    expect(res.error, 'badResponse');
  });

  test('ignores non-request messages (no reply loop on own responses)',
      () async {
    await WearRelayHandler(watch: watch, dio: () => dio).start();
    watch.deliver(const WearRpcResponse.ok('x').encode());
    await pumpEventQueue();
    expect(watch.sent, isEmpty);
  });

  group('the claim', () {
    late SettingsRepository settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = SettingsRepository(await SharedPreferences.getInstance());
    });

    WearRelayHandler handlerWithClaim({String nonce = 'ui'}) => WearRelayHandler(
          watch: watch,
          dio: () => dio,
          // One process, because that is the case the nonce exists for: the
          // foreground service's isolate shares the app's.
          claim: WearRelayClaim(settings, processId: 4242, nonce: nonce),
        );

    test('taken while listening, released when it stops', () async {
      // The native listener service reads this to decide whether to wake an
      // engine of its own; a listener without a claim would be answered twice.
      final handler = handlerWithClaim();
      await handler.start();
      expect(settings.loadWearRelayClaim(), '4242:ui');

      await handler.stop();
      expect(settings.loadWearRelayClaim(), isNull);
    });

    test('the hand-over inside one process survives the outgoing release',
        () async {
      // Backgrounding starts the service's isolate and stops the app's
      // handler, both without waiting for the other. They share a pid, so only
      // the nonce keeps the leaving one from wiping the arriving one's claim —
      // and an unclaimed listener is answered by a woken engine as well.
      final leaving = handlerWithClaim();
      await leaving.start();
      await WearRelayClaim(settings, processId: 4242, nonce: 'fgs').take();

      await leaving.stop();

      expect(settings.loadWearRelayClaim(), '4242:fgs');
    });

    test('a claim another process has taken over is left alone', () async {
      final handler = handlerWithClaim();
      await handler.start();
      // The app was killed and restarted while this handler was shutting down.
      await settings.saveWearRelayClaim('99:other');

      await handler.stop();
      expect(settings.loadWearRelayClaim(), '99:other');
    });

    test('a start that arrives mid-stop still ends up listening', () async {
      // Pause then resume in quick succession. Read against a half-cancelled
      // subscription, `start` used to return believing it had nothing to do —
      // leaving no listener and no claim, and the phone answering nothing.
      final handler = handlerWithClaim();
      await handler.start();
      adapter.onPost(
          '/api/v1/printers/1/print/pause', (s) => s.reply(200, {'ok': true}));

      final stopping = handler.stop();
      final starting = handler.start();
      await Future.wait([stopping, starting]);

      expect(settings.loadWearRelayClaim(), '4242:ui');
      watch.deliver(
          WearRpcRequest.create(WearRpcAction.pause, printerId: 1).encode());
      await pumpEventQueue();
      expect(watch.sent, hasLength(1));
    });

    test('handlers without one still answer (nothing native to coordinate)',
        () async {
      adapter.onPost(
          '/api/v1/printers/1/print/pause', (s) => s.reply(200, {'ok': true}));
      final handler = WearRelayHandler(watch: watch, dio: () => dio);
      await handler.start();
      watch.deliver(WearRpcRequest.create(WearRpcAction.pause, printerId: 1)
          .encode());
      await pumpEventQueue();
      expect(settings.loadWearRelayClaim(), isNull);
      expect(WearRpcResponse.decode(watch.sent.single)!.ok, isTrue);
    });
  });
}
