import 'dart:async';

import 'package:bambuddy_mobile/core/api/ws_backoff.dart';
import 'package:bambuddy_mobile/core/api/ws_client.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Sterowalny fake połączenia: testy ręcznie domykają handshake, wpychają
/// ramki i symulują zamknięcie przez serwer.
class FakeConn implements WsConnection {
  final _ready = Completer<void>();
  final _frames = StreamController<dynamic>();
  final List<String> sent = [];
  bool closed = false;

  void connectOk() => _ready.complete();
  void connectFail([Object e = 'handshake failed']) => _ready.completeError(e);
  void push(String data) => _frames.add(data);
  void serverClose() {
    if (!_frames.isClosed) _frames.close();
  }

  @override
  Future<void> get ready => _ready.future;
  @override
  Stream<dynamic> get stream => _frames.stream;
  @override
  void send(String data) => sent.add(data);
  @override
  Future<void> close() async {
    closed = true;
    if (!_frames.isClosed) await _frames.close();
  }
}

void main() {
  /// Buduje klienta + listę utworzonych połączeń (jedno per próba).
  ({WsClient client, List<FakeConn> conns}) build({WsBackoff? backoff}) {
    final conns = <FakeConn>[];
    final client = WsClient(
      url: Uri.parse('wss://example/api/v1/ws'),
      authHeaders: () async => const {'X-API-Key': 'k'},
      connect: (_, _) {
        final c = FakeConn();
        conns.add(c);
        return c;
      },
      backoff: backoff ?? WsBackoff(random: () => 1.0),
    );
    return (client: client, conns: conns);
  }

  test('happy path: connecting → connected, ramka → status, ping po 25 s', () {
    fakeAsync((async) {
      final (:client, :conns) = build();
      final statuses = [];
      client.statuses.listen(statuses.add);

      client.start();
      async.flushMicrotasks();
      expect(conns, hasLength(1));
      expect(client.state, WsConnectionState.connecting);

      conns[0].connectOk();
      async.flushMicrotasks();
      expect(client.state, WsConnectionState.connected);

      conns[0].push(readFixtureString('ws_printer_status.json'));
      async.flushMicrotasks();
      expect(statuses, hasLength(1));
      expect(statuses.first.id, 1);
      expect(statuses.first.name, 'X2D-3DP');

      async.elapse(const Duration(seconds: 25));
      expect(conns[0].sent, contains('{"type":"ping"}'));

      client.dispose();
      async.flushMicrotasks();
    });
  });

  test('zamknięcie przez serwer → waitingRetry → reconnect po backoffie', () {
    fakeAsync((async) {
      final (:client, :conns) = build();
      client.start();
      async.flushMicrotasks();
      conns[0].connectOk();
      async.flushMicrotasks();
      expect(client.state, WsConnectionState.connected);

      conns[0].serverClose();
      async.flushMicrotasks();
      expect(client.state, WsConnectionState.waitingRetry);
      expect(conns, hasLength(1)); // jeszcze nie wznowił

      // Połączenie żyło <30 s → backoff niewyzerowany; próba 0, rand=1 → 1 s.
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(conns, hasLength(2));
      expect(client.state, WsConnectionState.connecting);

      client.dispose();
      async.flushMicrotasks();
    });
  });

  test('cisza > idleTimeout: watchdog wymusza reconnect', () {
    fakeAsync((async) {
      final (:client, :conns) = build();
      client.start();
      async.flushMicrotasks();
      conns[0].connectOk();
      async.flushMicrotasks();

      // Żadnej ramki przez 60 s → watchdog. Po drodze pingi (25 s, 50 s).
      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();
      expect(client.state, WsConnectionState.waitingRetry);
      expect(conns[0].sent.length, greaterThanOrEqualTo(2));

      client.dispose();
      async.flushMicrotasks();
    });
  });

  test('nieudany handshake → waitingRetry → kolejna próba', () {
    fakeAsync((async) {
      final (:client, :conns) = build();
      client.start();
      async.flushMicrotasks();
      conns[0].connectFail('401');
      async.flushMicrotasks();
      expect(client.state, WsConnectionState.waitingRetry);

      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(conns, hasLength(2));

      client.dispose();
      async.flushMicrotasks();
    });
  });

  test('suspend zamyka socket bez reconnectu; resume wznawia', () {
    fakeAsync((async) {
      final (:client, :conns) = build();
      client.start();
      async.flushMicrotasks();
      conns[0].connectOk();
      async.flushMicrotasks();
      expect(client.state, WsConnectionState.connected);

      client.suspend();
      expect(client.state, WsConnectionState.suspended);
      expect(conns[0].closed, isTrue);

      // Brak prób w tle, nawet po długim czasie.
      async.elapse(const Duration(minutes: 5));
      async.flushMicrotasks();
      expect(conns, hasLength(1));

      client.resume();
      async.flushMicrotasks();
      expect(conns, hasLength(2));
      expect(client.state, WsConnectionState.connecting);
      conns[1].connectOk();
      async.flushMicrotasks();
      expect(client.state, WsConnectionState.connected);

      client.dispose();
      async.flushMicrotasks();
    });
  });
}
