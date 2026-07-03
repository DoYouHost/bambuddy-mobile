import 'dart:async';
import 'dart:io' show WebSocketException;

import 'package:bambuddy_mobile/core/api/ws_backoff.dart';
import 'package:bambuddy_mobile/core/api/ws_client.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Mirrors what `dart:io`'s `WebSocket.connect` actually throws when the
/// server responds but doesn't upgrade — the real anchor `_defaultIsAuthError`
/// keys off (`WebSocketException.httpStatusCode`), not a substring match.
WebSocketException _rejected(int httpStatusCode) =>
    WebSocketException('not upgraded to websocket', httpStatusCode);

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
  ({WsClient client, List<FakeConn> conns}) build({
    WsBackoff? backoff,
    Future<bool> Function()? refreshAuth,
  }) {
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
      refreshAuth: refreshAuth,
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
      conns[0].connectFail(_rejected(401));
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

  group('re-login JWT przy odrzuconym handshake\'u', () {
    test('odrzucenie auth + udany re-login → natychmiastowy reconnect', () {
      fakeAsync((async) {
        var refreshCalls = 0;
        final (:client, :conns) = build(
          refreshAuth: () async {
            refreshCalls++;
            return true;
          },
        );
        client.start();
        async.flushMicrotasks();

        conns[0].connectFail(_rejected(401));
        async.flushMicrotasks();

        expect(refreshCalls, 1);
        // Po udanym re-loginie łączy OD RAZU, bez czekania na backoff.
        expect(conns, hasLength(2));
        expect(client.state, WsConnectionState.connecting);

        conns[1].connectOk();
        async.flushMicrotasks();
        expect(client.state, WsConnectionState.connected);

        client.dispose();
        async.flushMicrotasks();
      });
    });

    test('odrzucenie auth + nieudany re-login → zwykły backoff', () {
      fakeAsync((async) {
        var refreshCalls = 0;
        final (:client, :conns) = build(
          refreshAuth: () async {
            refreshCalls++;
            return false;
          },
        );
        client.start();
        async.flushMicrotasks();

        conns[0].connectFail(_rejected(401));
        async.flushMicrotasks();

        expect(refreshCalls, 1);
        expect(client.state, WsConnectionState.waitingRetry);
        expect(conns, hasLength(1)); // czeka na backoff, nie łączy od razu

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(conns, hasLength(2));

        client.dispose();
        async.flushMicrotasks();
      });
    });

    test('błąd nie-auth (brak łączności) nie wyzwala re-loginu', () {
      fakeAsync((async) {
        var refreshCalls = 0;
        final (:client, :conns) = build(
          refreshAuth: () async {
            refreshCalls++;
            return true;
          },
        );
        client.start();
        async.flushMicrotasks();

        conns[0].connectFail('SocketException: Connection refused');
        async.flushMicrotasks();

        expect(refreshCalls, 0);
        expect(client.state, WsConnectionState.waitingRetry);

        client.dispose();
        async.flushMicrotasks();
      });
    });

    test('port zawierający „403" w błędzie łączności nie wyzwala re-loginu', () {
      // Regresja: serwer na porcie 8403 sprawia, że zwykły SocketException
      // (adres w komunikacie) zawiera podciąg „403" — klasyfikator MUSI
      // patrzeć na typ/kod, nie na goły substring `toString()`.
      fakeAsync((async) {
        var refreshCalls = 0;
        final (:client, :conns) = build(
          refreshAuth: () async {
            refreshCalls++;
            return true;
          },
        );
        client.start();
        async.flushMicrotasks();

        conns[0].connectFail(
          'SocketException: Connection refused (host:8403)',
        );
        async.flushMicrotasks();

        expect(refreshCalls, 0);
        expect(client.state, WsConnectionState.waitingRetry);

        client.dispose();
        async.flushMicrotasks();
      });
    });

    test('re-login najwyżej raz na serię niepowodzeń', () {
      fakeAsync((async) {
        var refreshCalls = 0;
        final (:client, :conns) = build(
          refreshAuth: () async {
            refreshCalls++;
            return true; // „odświeżony", ale serwer i tak dalej odrzuca
          },
        );
        client.start();
        async.flushMicrotasks();

        conns[0].connectFail(_rejected(401));
        async.flushMicrotasks();
        expect(refreshCalls, 1);
        expect(conns, hasLength(2)); // re-login → reconnect

        // Druga próba też odrzucona — re-login się NIE powtarza (guard).
        conns[1].connectFail(_rejected(401));
        async.flushMicrotasks();
        expect(refreshCalls, 1);
        expect(client.state, WsConnectionState.waitingRetry);

        client.dispose();
        async.flushMicrotasks();
      });
    });
  });

  group('token zapytania (?token=) na handshake', () {
    test('dołącza zmielony token do URL połączenia', () {
      fakeAsync((async) {
        final urls = <Uri>[];
        final client = WsClient(
          url: Uri.parse('wss://example/api/v1/ws'),
          authHeaders: () async => const {},
          queryToken: () async => 'tok123',
          connect: (url, _) {
            urls.add(url);
            return FakeConn()..connectOk();
          },
        );
        client.start();
        async.flushMicrotasks();

        expect(urls, hasLength(1));
        expect(urls.first.queryParameters['token'], 'tok123');

        client.dispose();
        async.flushMicrotasks();
      });
    });

    test('token null → URL bez parametru (fallback header-only)', () {
      fakeAsync((async) {
        final urls = <Uri>[];
        final client = WsClient(
          url: Uri.parse('wss://example/api/v1/ws'),
          authHeaders: () async => const {},
          queryToken: () async => null,
          connect: (url, _) {
            urls.add(url);
            return FakeConn()..connectOk();
          },
        );
        client.start();
        async.flushMicrotasks();

        expect(urls.first.queryParameters.containsKey('token'), isFalse);

        client.dispose();
        async.flushMicrotasks();
      });
    });

    test(
        'błąd mintu tokenu (rzucony, nie null) → backoff i retry, '
        'NIE fallback header-only', () {
      // WsTokenService.token() zwraca null TYLKO na 404 (stary serwer);
      // rzucony wyjątek to przejściowa awaria mintu (5xx/sieć) — nie może
      // być spłaszczony do połączenia header-only (na serwerze wymagającym
      // ?token= takie połączenie i tak dostanie 401).
      fakeAsync((async) {
        var mintCalls = 0;
        final urls = <Uri>[];
        final client = WsClient(
          url: Uri.parse('wss://example/api/v1/ws'),
          authHeaders: () async => const {},
          queryToken: () async {
            mintCalls++;
            if (mintCalls == 1) throw Exception('mint failed (5xx)');
            return 'tok-fresh';
          },
          backoff: WsBackoff(random: () => 1.0),
          connect: (url, _) {
            urls.add(url);
            return FakeConn()..connectOk();
          },
        );
        client.start();
        async.flushMicrotasks();

        expect(urls, isEmpty); // brak próby połączenia header-only
        expect(client.state, WsConnectionState.waitingRetry);
        expect(mintCalls, 1);

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(urls, hasLength(1));
        expect(urls.first.queryParameters['token'], 'tok-fresh');
        expect(client.state, WsConnectionState.connected);

        client.dispose();
        async.flushMicrotasks();
      });
    });

    test('odrzucony handshake (401) unieważnia token przed ponowieniem', () {
      fakeAsync((async) {
        var invalidated = 0;
        final conns = <FakeConn>[];
        final client = WsClient(
          url: Uri.parse('wss://example/api/v1/ws'),
          authHeaders: () async => const {},
          queryToken: () async => 'tok',
          invalidateQueryToken: () => invalidated++,
          backoff: WsBackoff(random: () => 1.0),
          connect: (_, _) {
            final c = FakeConn();
            conns.add(c);
            return c;
          },
        );
        client.start();
        async.flushMicrotasks();

        conns[0].connectFail(_rejected(401));
        async.flushMicrotasks();
        expect(invalidated, 1);

        client.dispose();
        async.flushMicrotasks();
      });
    });
  });
}
