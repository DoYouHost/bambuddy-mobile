import 'package:bambuddy_mobile/core/watch/wear_relay_handler.dart';
import 'package:bambuddy_mobile/core/watch/wear_rpc.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

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
    handler.start();
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

  test('ignores non-request messages (no reply loop on own responses)',
      () async {
    WearRelayHandler(watch: watch, dio: () => dio).start();
    watch.deliver(const WearRpcResponse.ok('x').encode());
    await pumpEventQueue();
    expect(watch.sent, isEmpty);
  });
}
