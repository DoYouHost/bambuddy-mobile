import 'dart:async';
import 'dart:convert';
import 'dart:io' show WebSocketException;

import 'package:bambuddy_mobile/core/api/ws_backoff.dart';
import 'package:bambuddy_mobile/core/api/ws_client.dart';
import 'package:bambuddy_mobile/core/diagnostics/diagnostic_recorder.dart';
import 'package:bambuddy_mobile/core/diagnostics/session_facts.dart';
import 'package:bambuddy_mobile/core/diagnostics/ws_probe.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// Mirrors what `dart:io`'s `WebSocket.connect` actually throws when the
/// server responds but doesn't upgrade — the real anchor `_defaultIsAuthError`
/// keys off (`WebSocketException.httpStatusCode`), not a substring match.
WebSocketException _rejected(int httpStatusCode) =>
    WebSocketException('not upgraded to websocket', httpStatusCode);

/// A controllable fake connection: tests manually close the handshake, push
/// frames and simulate the server closing it.
class FakeConn implements WsConnection {
  final _ready = Completer<void>();
  final _frames = StreamController<dynamic>();
  final List<String> sent = [];
  bool closed = false;

  @override
  int? closeCode;
  @override
  String? closeReason;

  void connectOk() => _ready.complete();
  void connectFail([Object e = 'handshake failed']) => _ready.completeError(e);
  void push(String data) => _frames.add(data);
  void serverClose({int? code, String? reason}) {
    closeCode = code;
    closeReason = reason;
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
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Builds the client + a list of created connections (one per attempt).
  ({WsClient client, List<FakeConn> conns}) build({
    WsBackoff? backoff,
    Future<bool> Function()? refreshAuth,
    Future<String?> Function()? queryToken,
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
      queryToken: queryToken,
    );
    return (client: client, conns: conns);
  }

  test(
    'happy path: connecting → connected, frame → status, ping after 25s',
    () {
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
    },
  );

  test('closed by server → waitingRetry → reconnect after backoff', () {
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
      expect(conns, hasLength(1)); // hasn't resumed yet

      // Connection was alive <30s → backoff not reset; attempt 0, rand=1 → 1s.
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(conns, hasLength(2));
      expect(client.state, WsConnectionState.connecting);

      client.dispose();
      async.flushMicrotasks();
    });
  });

  test('silence > idleTimeout: watchdog forces reconnect', () {
    fakeAsync((async) {
      final (:client, :conns) = build();
      client.start();
      async.flushMicrotasks();
      conns[0].connectOk();
      async.flushMicrotasks();

      // No frame for 60s → watchdog. Pings along the way (25s, 50s).
      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();
      expect(client.state, WsConnectionState.waitingRetry);
      expect(conns[0].sent.length, greaterThanOrEqualTo(2));

      client.dispose();
      async.flushMicrotasks();
    });
  });

  test('failed handshake → waitingRetry → next attempt', () {
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

  test('suspend closes the socket without reconnect; resume resumes', () {
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

      // No attempts in the background, even after a long time.
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

  group('JWT re-login on a rejected handshake', () {
    test('auth rejection + successful re-login → immediate reconnect', () {
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
        // After a successful re-login it connects RIGHT AWAY, without waiting for backoff.
        expect(conns, hasLength(2));
        expect(client.state, WsConnectionState.connecting);

        conns[1].connectOk();
        async.flushMicrotasks();
        expect(client.state, WsConnectionState.connected);

        client.dispose();
        async.flushMicrotasks();
      });
    });

    test('auth rejection + failed re-login → regular backoff', () {
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
        expect(
          conns,
          hasLength(1),
        ); // waits for backoff, doesn't connect right away

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(conns, hasLength(2));

        client.dispose();
        async.flushMicrotasks();
      });
    });

    test('a non-auth error (no connectivity) does not trigger re-login', () {
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

    test(
      'a port containing "403" in a connectivity error does not trigger re-login',
      () {
        // Regression: a server on port 8403 makes a regular SocketException
        // (the address in the message) contain the substring "403" — the
        // classifier MUST look at the type/code, not a bare `toString()` substring.
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
      },
    );

    test('re-login happens at most once per failure streak', () {
      fakeAsync((async) {
        var refreshCalls = 0;
        final (:client, :conns) = build(
          refreshAuth: () async {
            refreshCalls++;
            return true; // "refreshed", but the server keeps rejecting anyway
          },
        );
        client.start();
        async.flushMicrotasks();

        conns[0].connectFail(_rejected(401));
        async.flushMicrotasks();
        expect(refreshCalls, 1);
        expect(conns, hasLength(2)); // re-login → reconnect

        // Second attempt also rejected — re-login does NOT repeat (guard).
        conns[1].connectFail(_rejected(401));
        async.flushMicrotasks();
        expect(refreshCalls, 1);
        expect(client.state, WsConnectionState.waitingRetry);

        client.dispose();
        async.flushMicrotasks();
      });
    });
  });

  group('query token (?token=) on handshake', () {
    test('appends the minted token to the connection URL', () {
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

    test('token null → URL without the parameter (header-only fallback)', () {
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

    test('a token mint error (thrown, not null) → backoff and retry, '
        'NOT header-only fallback', () {
      // WsTokenService.token() returns null ONLY on 404 (old server);
      // a thrown exception is a transient mint failure (5xx/network) — it must
      // not be flattened to a header-only connection (on a server requiring
      // ?token= such a connection would get 401 anyway).
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

        expect(urls, isEmpty); // no header-only connection attempt
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

    test(
      'a rejected handshake (401) invalidates the token before retrying',
      () {
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
      },
    );
  });

  /// Wiring [WsProbe] into the client: what it does is tested separately in
  /// `ws_probe_test.dart`; here only that the client actually calls it is
  /// checked — and that part quietly rots when the client changes.
  group('diagnostic log', () {
    late DiagnosticRecorder recorder;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      recorder = DiagnosticRecorder(
        settings: SettingsRepository(await SharedPreferences.getInstance()),
        loadFacts: () async =>
            const SessionFacts(app: '1.0+1', flavor: 'mobile'),
        resolveDirectory: () async => null,
      );
      // Recording starts OUTSIDE `fakeAsync`: `start()` waits on prefs via
      // a platform channel that the fake event loop won't finish.
      await recorder.start();
      addTearDown(recorder.discard);
    });

    Future<List<Map<String, dynamic>>> wsRecords() async {
      final jsonl = await recorder.stop();
      return [
        for (final line in const LineSplitter().convert(jsonl))
          if (jsonDecode(line) case final Map<String, dynamic> row
              when row['src'] == 'ws')
            row,
      ];
    }

    test(
      'connection lifetime: connect → open → frame → disconnect → retry',
      () async {
        fakeAsync((async) {
          final (:client, :conns) = build(queryToken: () async => 'tok');
          client.start();
          async.flushMicrotasks();
          conns[0].connectOk();
          async.flushMicrotasks();

          conns[0].push(readFixtureString('ws_printer_status.json'));
          async.flushMicrotasks();
          conns[0].serverClose(code: 1006, reason: 'no close frame');
          async.flushMicrotasks();

          client.dispose();
          async.flushMicrotasks();
        });

        final records = await wsRecords();
        expect(
          records.map((r) => r['evt']),
          containsAllInOrder([
            'connect',
            'open',
            'frame',
            'disconnect',
            'retry',
          ]),
        );
        expect(records.first['via'], 'token');
        // The frame went through the client's parser, so the record carries its content.
        final frame = records.firstWhere((r) => r['evt'] == 'frame');
        expect(frame['type'], 'printer_status');
        expect(frame['printer_id'], 1);
        final close = records.firstWhere((r) => r['evt'] == 'disconnect');
        expect(close['reason'], 'remote');
        expect(close['code'], 1006);
        expect(close['close_reason'], 'no close frame');
      },
    );

    test(
      'the client reports its state to the probe, so the snapshot knows it',
      () async {
        fakeAsync((async) {
          final (:client, :conns) = build();
          client.start();
          async.flushMicrotasks();
          conns[0].connectOk();
          async.flushMicrotasks();

          // Same as the recorder does when recording starts — except here
          // recording is already running, so the snapshot is called directly.
          WsProbe.openSession();
          async.flushMicrotasks();

          client.dispose();
          async.flushMicrotasks();
        });

        final snapshot = (await wsRecords()).firstWhere(
          (r) => r['evt'] == 'state',
        );
        expect(snapshot['state'], 'connected');
      },
    );

    test('a rejected handshake comes down with an HTTP status', () async {
      fakeAsync((async) {
        final (:client, :conns) = build();
        client.start();
        async.flushMicrotasks();
        conns[0].connectFail(_rejected(401));
        async.flushMicrotasks();

        client.dispose();
        async.flushMicrotasks();
      });

      final error = (await wsRecords()).firstWhere(
        (r) => r['evt'] == 'connect_error',
      );
      expect(error['phase'], 'handshake');
      expect(error['status'], 401);
      expect(error['cause'], 'WebSocketException');
    });

    test(
      'silence longer than the watchdog is a disconnect with reason idle',
      () async {
        fakeAsync((async) {
          final (:client, :conns) = build();
          client.start();
          async.flushMicrotasks();
          conns[0].connectOk();
          async.flushMicrotasks();

          async.elapse(const Duration(seconds: 60));
          async.flushMicrotasks();

          client.dispose();
          async.flushMicrotasks();
        });

        expect(
          (await wsRecords()).firstWhere(
            (r) => r['evt'] == 'disconnect',
          )['reason'],
          'idle',
        );
      },
    );

    test(
      'going to the background says outright why the socket went quiet',
      () async {
        fakeAsync((async) {
          final (:client, :conns) = build();
          client.start();
          async.flushMicrotasks();
          conns[0].connectOk();
          async.flushMicrotasks();

          client.suspend();
          async.flushMicrotasks();

          client.dispose();
          async.flushMicrotasks();
        });

        final records = await wsRecords();
        expect(
          records.firstWhere((r) => r['evt'] == 'disconnect')['reason'],
          'suspend',
        );
        // Suspending does not schedule a retry — otherwise the log would promise
        // a comeback that won't happen until `resume()`.
        expect(records.map((r) => r['evt']), isNot(contains('retry')));
      },
    );
  });
}
