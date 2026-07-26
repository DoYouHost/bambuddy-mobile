import 'dart:async';
import 'dart:convert';
import 'dart:io' show WebSocketException;

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../diagnostics/ws_probe.dart';
import '../models/printer_status.dart';
import 'ws_backoff.dart';
import 'ws_messages.dart';

/// WebSocket connection state — source for UI banner.
///
/// `suspended` is separate from `disconnected`: it means intentional pausing
/// while app is in background (zero reconnect attempts), not a failure.
enum WsConnectionState {
  disconnected,
  connecting,
  connected,
  waitingRetry,
  suspended,
}

/// Minimal WebSocket connection contract. Allows injecting a fake in tests
/// without implementing full [WebSocketChannel]; in production wraps
/// [IOWebSocketChannel] (supports auth headers on handshake — which browser
/// WebSocket cannot do).
abstract class WsConnection {
  /// Completes after successful handshake; throws if connection fails
  /// (server down, 401/403 on upgrade).
  Future<void> get ready;
  Stream<dynamic> get stream;
  void send(String data);
  Future<void> close();

  /// Close code the peer sent, once the stream is done — `null` while the
  /// socket is live, or when the transport reports none. Diagnostics only:
  /// 1000 (server shutting down cleanly) and 1006 (connection lost without a
  /// close frame) are the same reconnect to the client and a different report.
  int? get closeCode;

  /// Text the peer attached to the close, when it sent any.
  String? get closeReason;
}

typedef WsConnector = WsConnection Function(
  Uri url,
  Map<String, String> headers,
);

class _IoWsConnection implements WsConnection {
  _IoWsConnection(this._channel);
  final WebSocketChannel _channel;

  @override
  Future<void> get ready => _channel.ready;
  @override
  Stream<dynamic> get stream => _channel.stream;
  @override
  void send(String data) => _channel.sink.add(data);
  @override
  Future<void> close() => _channel.sink.close();
  @override
  int? get closeCode => _channel.closeCode;
  @override
  String? get closeReason => _channel.closeReason;
}

WsConnection _defaultConnect(Uri url, Map<String, String> headers) =>
    _IoWsConnection(IOWebSocketChannel.connect(url, headers: headers));

/// Bambuddy WebSocket client: single multiplexing connection to `/api/v1/ws`,
/// streaming `printer_status` frames.
///
/// Two outputs for upper layer: [connectionStates] (banner) and [statuses]
/// (latest status per printer mounted by provider). Resilience per plan §3:
/// backoff with jitter ([WsBackoff]), heartbeat ping + idle watchdog,
/// explicit [suspend]/[resume] for app lifecycle.
///
/// Auth is header-based (see ws-contract-m2 memory) — no token minting;
/// on credential change/expiry, reconnect with fresh headers (read from
/// [authHeaders] at each attempt).
class WsClient {
  WsClient({
    required Uri url,
    required Future<Map<String, String>> Function() authHeaders,
    WsConnector connect = _defaultConnect,
    WsBackoff? backoff,
    Future<bool> Function()? refreshAuth,
    Future<String?> Function()? queryToken,
    void Function()? invalidateQueryToken,
    bool Function(Object error)? isAuthError,
    WsProbe? probe,
    this.heartbeatInterval = const Duration(seconds: 25),
    this.idleTimeout = const Duration(seconds: 60),
    this.stableThreshold = const Duration(seconds: 30),
  })  :
        // Public parameter names + private fields: initializing formal
        // cannot be private, so lint is unsatisfiable here.
        // ignore: prefer_initializing_formals
        _url = url,
        // ignore: prefer_initializing_formals
        _authHeaders = authHeaders,
        // ignore: prefer_initializing_formals
        _connect = connect,
        // ignore: prefer_initializing_formals
        _refreshAuth = refreshAuth,
        // ignore: prefer_initializing_formals
        _queryToken = queryToken,
        // ignore: prefer_initializing_formals
        _invalidateQueryToken = invalidateQueryToken,
        _isAuthError = isAuthError ?? _defaultIsAuthError,
        _probe = probe ?? WsProbe(),
        _backoff = backoff ?? WsBackoff();

  final Uri _url;
  final Future<Map<String, String>> Function() _authHeaders;
  final WsConnector _connect;
  final WsBackoff _backoff;

  /// Diagnostic log of the connection's life — attempts, closes, frame rates.
  /// Silent unless a bug-report recording is running.
  final WsProbe _probe;

  /// Attempt to refresh credentials (silent JWT re-login) when server rejects
  /// handshake. `true` = got fresh credentials, worth retrying immediately.
  /// `null` (apiKey/none mode) → nothing to refresh, normal backoff.
  final Future<bool> Function()? _refreshAuth;

  /// Mints the short-lived `?token=` value for the handshake (GHSA-r2qv:
  /// the WS endpoint validates a query token before `accept()`, since the
  /// upgrade can't carry `Authorization`/`X-API-Key` headers in browsers).
  /// `null` token (or a server without `/auth/ws-token`) → connect without
  /// the param, falling back to header auth for older servers.
  final Future<String?> Function()? _queryToken;

  /// Drops the cached query token so the next attempt mints a fresh one
  /// (called when the server rejects the handshake as unauthorized).
  final void Function()? _invalidateQueryToken;

  /// Whether handshake error is auth rejection (not connectivity failure).
  final bool Function(Object error) _isAuthError;

  /// Re-login attempted at most once per failure series — reset after
  /// successful connection. Protects against login→401→login loop when fresh
  /// token is also rejected (e.g., account requires reconfiguration).
  bool _authRefreshed = false;

  /// Interval between heartbeat pings.
  final Duration heartbeatInterval;

  /// No frame of ANY kind for this duration → force reconnect
  /// (catches half-open TCP after Wi-Fi roam).
  final Duration idleTimeout;

  /// Connection must survive this long to be considered stable and reset
  /// backoff — otherwise flapping would prevent backoff growth.
  final Duration stableThreshold;

  final _stateController = StreamController<WsConnectionState>.broadcast();
  final _statusController = StreamController<WsPrinterStatus>.broadcast();
  final _plateController = StreamController<WsPlateNotEmpty>.broadcast();
  final _printController = StreamController<WsPrintEvent>.broadcast();

  WsConnection? _conn;
  StreamSubscription<dynamic>? _sub;
  Timer? _heartbeat;
  Timer? _watchdog;
  Timer? _stable;
  Timer? _retry;

  var _state = WsConnectionState.disconnected;
  bool _running = false;
  bool _disposed = false;

  /// Increments on each connection attempt; invalidates stale callbacks
  /// (frames/close) from old, abandoned socket.
  int _generation = 0;

  WsConnectionState get state => _state;
  Stream<WsConnectionState> get connectionStates => _stateController.stream;
  Stream<PrinterStatus> get statuses =>
      _statusController.stream.map((f) => f.status);

  /// Full status frames including the raw server JSON — for consumers that
  /// must forward server-shaped data (watch relay) without re-serializing.
  Stream<WsPrinterStatus> get statusFrames => _statusController.stream;

  /// "Plate not empty" events (suspended print) — separate stream from
  /// [statuses] because it's an event frame, not full printer state.
  Stream<WsPlateNotEmpty> get plateAlerts => _plateController.stream;

  /// Print lifecycle events (`print_start`/`print_complete`) — a trigger to
  /// refresh queue/maintenance, which aren't pushed over WS themselves.
  Stream<WsPrintEvent> get printEvents => _printController.stream;

  /// Start connecting (idempotent). After [suspend], resume via [resume].
  void start() {
    if (_disposed || _running) return;
    _running = true;
    _openConnection();
  }

  /// App in background: close socket, set state to `suspended`, no reconnects.
  void suspend() {
    if (_disposed || _state == WsConnectionState.suspended) return;
    _running = false;
    _retry?.cancel();
    _probe.disconnected(reason: WsDisconnectReason.suspend);
    _teardownConnection();
    _setState(WsConnectionState.suspended);
  }

  /// Resume from background. Caller should do REST backfill first, then this.
  void resume() {
    if (_disposed || _running) return;
    _backoff.reset();
    _authRefreshed = false; // fresh attempt series — can retry re-login again
    start();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _running = false;
    _retry?.cancel();
    _probe.disconnected(reason: WsDisconnectReason.dispose);
    _probe.dispose();
    _teardownConnection();
    await _stateController.close();
    await _statusController.close();
    await _plateController.close();
    await _printController.close();
  }

  Future<void> _openConnection() async {
    if (!_running || _disposed) return;
    final generation = ++_generation;
    _setState(WsConnectionState.connecting);

    // Headers read on EVERY attempt — catches refreshed JWT/key.
    Map<String, String> headers;
    try {
      headers = await _authHeaders();
    } catch (_) {
      headers = const {};
    }
    if (generation != _generation || !_running || _disposed) return;

    // Append the freshly-minted `?token=` when available (new server); on a
    // null token keep the bare URL so header auth still works on old servers.
    var url = _url;
    var withToken = false;
    if (_queryToken != null) {
      String? token;
      try {
        token = await _queryToken();
      } catch (e) {
        // `_queryToken` (WsTokenService.token) returns `null` — no throw —
        // specifically for "server lacks this endpoint" (404); anything it
        // actually throws is a genuine transient mint failure (network blip,
        // 5xx). Treat that like any other connect failure (backoff + retry,
        // re-minting fresh next attempt) instead of silently falling back to
        // header-only: on a server that REQUIRES `?token=`, a header-only
        // handshake is certain to 401 and burns the one-shot re-login for
        // nothing.
        if (generation != _generation) return;
        _probe.connectError(wsInnerError(e), phase: 'token');
        await _handleConnectError(e, generation);
        return;
      }
      if (generation != _generation || !_running || _disposed) return;
      if (token != null && token.isNotEmpty) {
        withToken = true;
        url = _url.replace(
          queryParameters: {..._url.queryParameters, 'token': token},
        );
      }
    }

    final WsConnection conn;
    _probe.connecting(queryToken: withToken);
    try {
      conn = _connect(url, headers);
      await conn.ready;
    } catch (e) {
      if (generation != _generation) return;
      _probe.connectError(
        wsInnerError(e),
        phase: 'handshake',
        status: wsHandshakeStatus(e),
      );
      await _handleConnectError(e, generation);
      return;
    }
    // During handshake, suspend()/dispose() or newer generation could arrive
    // — then discard fresh connection.
    if (generation != _generation || !_running || _disposed) {
      await conn.close();
      return;
    }

    _conn = conn;
    _authRefreshed = false; // successful connection → can retry re-login again
    _probe.opened();
    _setState(WsConnectionState.connected);
    _sub = conn.stream.listen(
      (data) => _onFrame(generation, data),
      onError: (e) => _onClosed(generation, WsDisconnectReason.error, error: e),
      onDone: () => _onClosed(generation, WsDisconnectReason.remote),
      cancelOnError: true,
    );
    _startHeartbeat();
    _resetWatchdog(generation);
    _stable = Timer(stableThreshold, _backoff.reset);
  }

  void _onFrame(int generation, dynamic data) {
    if (generation != _generation) return;
    _resetWatchdog(generation); // any frame = live socket
    if (data is! String) {
      _probe.binaryFrame();
      return;
    }
    final msg = parseWsMessage(data);
    _probe.frame(msg);
    if (msg is WsPrinterStatus && !_statusController.isClosed) {
      _statusController.add(msg);
    } else if (msg is WsPlateNotEmpty && !_plateController.isClosed) {
      _plateController.add(msg);
    } else if (msg is WsPrintEvent && !_printController.isClosed) {
      _printController.add(msg);
    }
    // WsPong/WsUnknown/null: watchdog already reset — nothing more.
  }

  /// Handshake error. If server rejected auth and we can refresh (JWT), try
  /// silent re-login once — on success, reconnect immediately with new token.
  /// Otherwise normal backoff.
  Future<void> _handleConnectError(Object error, int generation) async {
    // Unauthorized handshake → the cached query token is likely stale; drop it
    // so the next attempt (immediate after re-login, or after backoff) re-mints.
    if (_isAuthError(error)) _invalidateQueryToken?.call();
    if (_running &&
        !_disposed &&
        _refreshAuth != null &&
        !_authRefreshed &&
        _isAuthError(error)) {
      _authRefreshed = true;
      final refreshed = await _refreshAuth();
      if (generation != _generation || !_running || _disposed) return;
      if (refreshed) {
        _backoff.reset();
        unawaited(_openConnection());
        return;
      }
    }
    _scheduleRetry();
  }

  void _onClosed(
    int generation,
    WsDisconnectReason reason, {
    Object? error,
  }) {
    if (generation != _generation) return;
    // Before teardown: the close code lives on the connection we are about to
    // drop, and the peer only fills it in once the stream is done.
    _probe.disconnected(
      reason: reason,
      code: _conn?.closeCode,
      closeReason: _conn?.closeReason,
      error: error,
    );
    _teardownConnection();
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (!_running || _disposed) return;
    _setState(WsConnectionState.waitingRetry);
    _retry?.cancel();
    // Attempt read before the delay, which increments it.
    final attempt = _backoff.attempt;
    final delay = _backoff.nextDelay();
    _probe.retryScheduled(delay: delay, attempt: attempt);
    _retry = Timer(delay, _openConnection);
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(heartbeatInterval, (_) => _sendHeartbeat());
  }

  /// A remote close can land between the last frame and the stream's
  /// `onDone`/`onError` callback actually firing — `_conn` stays non-null for
  /// that window, so a ping can hit an already-closed sink and throw
  /// straight out of the timer callback (uncaught, no recovery). Swallow it;
  /// `_onClosed` runs once onDone/onError actually delivers and reconnects.
  void _sendHeartbeat() {
    final conn = _conn;
    if (conn == null) return;
    try {
      conn.send(jsonEncode({'type': 'ping'}));
    } on Object {
      // Ignore — teardown/reconnect is already in flight.
    }
  }

  void _resetWatchdog(int generation) {
    _watchdog?.cancel();
    _watchdog = Timer(
      idleTimeout,
      () => _onClosed(generation, WsDisconnectReason.idle),
    );
  }

  /// Close current connection and cancel all associated timers.
  /// Does NOT touch `_retry` or state — callers handle per context.
  void _teardownConnection() {
    _heartbeat?.cancel();
    _watchdog?.cancel();
    _stable?.cancel();
    _heartbeat = _watchdog = _stable = null;
    _sub?.cancel();
    _sub = null;
    final conn = _conn;
    _conn = null;
    conn?.close();
  }

  void _setState(WsConnectionState next) {
    if (_state == next) return;
    _state = next;
    // No record of its own — the probe writes it only when a recording opens
    // mid-connection, where the transitions themselves are already history.
    _probe.trackState(next.name);
    if (!_stateController.isClosed) _stateController.add(next);
  }
}

/// What actually went wrong: `package:web_socket_channel` wraps the original
/// exception in `WebSocketChannelException.inner`, and the wrapper's type says
/// nothing — `HandshakeException` versus `SocketException` is the difference
/// between "TLS refused" and "nothing listening there".
Object wsInnerError(Object error) {
  final inner = error is WebSocketChannelException ? error.inner : error;
  return inner ?? error;
}

/// HTTP status `dart:io`'s `WebSocket.connect` attaches to the thrown
/// `WebSocketException` (`response.statusCode` whenever a response came back but
/// wasn't a 101 upgrade), or null when the server never responded at all.
int? wsHandshakeStatus(Object error) {
  final inner = wsInnerError(error);
  return inner is WebSocketException ? inner.httpStatusCode : null;
}

/// Default classifier: handshake error is auth rejection when server
/// RESPONDED but didn't upgrade (401/403) — unlike connectivity failure
/// (SocketException, timeout) where re-login won't help.
///
/// Anchored on the real HTTP status ([wsHandshakeStatus]) — NOT a substring
/// match on `error.toString()`. A plain connectivity failure's message can embed
/// the target host/port (e.g. a server on `host:8403`), which would otherwise
/// false-match "403" and misclassify a routine network hiccup as an auth
/// rejection.
bool _defaultIsAuthError(Object error) {
  final code = wsHandshakeStatus(error);
  return code == 401 || code == 403;
}
