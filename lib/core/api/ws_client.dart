import 'dart:async';
import 'dart:convert';
import 'dart:io' show WebSocketException;

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../diagnostics/ws_probe.dart';
import '../models/printer_status.dart';
import 'ws_backoff.dart';
import 'ws_messages.dart';

/// `suspended` is separate from `disconnected` because it is deliberate — the
/// app went to the background and nothing is retrying — not a failure the
/// banner should alarm anyone about.
enum WsConnectionState {
  disconnected,
  connecting,
  connected,
  waitingRetry,
  suspended,
}

/// Lets a test inject a fake without implementing all of [WebSocketChannel].
/// Production wraps [IOWebSocketChannel], which can put auth headers on the
/// handshake where a browser WebSocket cannot.
abstract class WsConnection {
  /// Throws when the connection fails — server down, 401/403 on upgrade.
  Future<void> get ready;
  Stream<dynamic> get stream;
  void send(String data);
  Future<void> close();

  /// Filled in by the peer once the stream is done, `null` while live.
  /// Diagnostics only: 1000 (clean shutdown) and 1006 (lost without a close
  /// frame) are the same reconnect to us and a different report.
  int? get closeCode;

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

/// One multiplexing connection to `/api/v1/ws`, streaming every printer's
/// frames. Resilience is three things: jittered backoff ([WsBackoff]), a
/// heartbeat ping with an idle watchdog behind it, and explicit
/// [suspend]/[resume] tied to the app's lifecycle.
///
/// Credentials are re-read on every attempt, so a refreshed JWT or a changed
/// key needs nothing more than a reconnect.
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
        // An initializing formal cannot be private, so the lint cannot be
        // satisfied while the fields stay private.
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

  /// Silent unless a bug-report recording is running.
  final WsProbe _probe;

  /// Silent JWT re-login when the server rejects the handshake. `true` means
  /// fresh credentials, worth retrying at once; `null` in apiKey/none mode,
  /// where there is nothing to refresh.
  final Future<bool> Function()? _refreshAuth;

  /// GHSA-r2qv: the endpoint validates a query token before `accept()`, since
  /// the upgrade cannot carry headers in browsers. A `null` token means a
  /// server without the route, so we fall back to header auth.
  final Future<String?> Function()? _queryToken;

  /// Called when the server rejects the handshake, so the next attempt mints
  /// rather than re-sending a token the server has already refused.
  final void Function()? _invalidateQueryToken;

  final bool Function(Object error) _isAuthError;

  /// Re-login runs at most once per failure series, reset on a successful
  /// connection — otherwise a fresh token that is also rejected (an account
  /// needing reconfiguration) becomes a login→401→login loop.
  bool _authRefreshed = false;

  final Duration heartbeatInterval;

  /// No frame of *any* kind for this long forces a reconnect, which is what
  /// catches a half-open TCP after a Wi-Fi roam.
  final Duration idleTimeout;

  /// How long a connection must survive before the backoff resets; without it
  /// a flapping socket would keep the delay at its minimum forever.
  final Duration stableThreshold;

  final _stateController = StreamController<WsConnectionState>.broadcast();
  final _statusController = StreamController<WsPrinterStatus>.broadcast();
  final _plateController = StreamController<WsPlateNotEmpty>.broadcast();
  final _printController = StreamController<WsPrintEvent>.broadcast();
  final _archiveController = StreamController<WsArchiveUpdated>.broadcast();
  final _pipelineRunController =
      StreamController<WsPipelineRunUpdated>.broadcast();

  WsConnection? _conn;
  StreamSubscription<dynamic>? _sub;
  Timer? _heartbeat;
  Timer? _watchdog;
  Timer? _stable;
  Timer? _retry;

  var _state = WsConnectionState.disconnected;
  bool _running = false;
  bool _disposed = false;

  /// Invalidates frame and close callbacks still arriving from an abandoned
  /// socket.
  int _generation = 0;

  WsConnectionState get state => _state;
  Stream<WsConnectionState> get connectionStates => _stateController.stream;
  Stream<PrinterStatus> get statuses =>
      _statusController.stream.map((f) => f.status);

  /// Carries the raw server JSON too, for the watch relay, which forwards
  /// server-shaped data rather than re-serializing.
  Stream<WsPrinterStatus> get statusFrames => _statusController.stream;

  /// Its own stream rather than part of [statuses]: an event frame, not state.
  Stream<WsPlateNotEmpty> get plateAlerts => _plateController.stream;

  Stream<WsPrintEvent> get printEvents => _printController.stream;

  /// Archive changes that arrive after the print itself is over — the finish
  /// photo landing in the archive is the one this app listens for.
  Stream<WsArchiveUpdated> get archiveUpdates => _archiveController.stream;

  /// Pipeline runs the server routed to this session. Only the runs it started
  /// itself, unless authentication is off — see [WsPipelineRunUpdated].
  Stream<WsPipelineRunUpdated> get pipelineRunUpdates =>
      _pipelineRunController.stream;

  /// Idempotent. After [suspend] the way back is [resume].
  void start() {
    if (_disposed || _running) return;
    _running = true;
    _openConnection();
  }

  /// App went to the background: close the socket and stop reconnecting.
  void suspend() {
    if (_disposed || _state == WsConnectionState.suspended) return;
    _running = false;
    _retry?.cancel();
    _probe.disconnected(reason: WsDisconnectReason.suspend);
    _teardownConnection();
    _setState(WsConnectionState.suspended);
  }

  /// The caller backfills over REST first, then calls this.
  void resume() {
    if (_disposed || _running) return;
    _backoff.reset();
    // A fresh attempt series, so re-login is on the table again.
    _authRefreshed = false;
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
    await _archiveController.close();
    await _pipelineRunController.close();
  }

  Future<void> _openConnection() async {
    if (!_running || _disposed) return;
    final generation = ++_generation;
    _setState(WsConnectionState.connecting);

    // Read on *every* attempt, which is what picks up a refreshed JWT or key.
    Map<String, String> headers;
    try {
      headers = await _authHeaders();
    } catch (_) {
      headers = const {};
    }
    if (generation != _generation || !_running || _disposed) return;

    // A null token keeps the bare URL, so header auth still works on servers
    // without the mint route.
    var url = _url;
    var withToken = false;
    if (_queryToken != null) {
      String? token;
      try {
        token = await _queryToken();
      } catch (e) {
        // A missing route answers `null` rather than throwing, so anything
        // caught here is a transient mint failure. Retrying beats falling back
        // to header-only: on a server that *requires* the token, a header-only
        // handshake is a certain 401 that burns the one-shot re-login.
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
    // A suspend, a dispose or a newer attempt can land mid-handshake, and the
    // connection we just opened is then already obsolete.
    if (generation != _generation || !_running || _disposed) {
      await conn.close();
      return;
    }

    _conn = conn;
    _authRefreshed = false;
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
    // Any frame at all proves the socket is live.
    _resetWatchdog(generation);
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
    } else if (msg is WsArchiveUpdated && !_archiveController.isClosed) {
      _archiveController.add(msg);
    } else if (msg is WsPipelineRunUpdated &&
        !_pipelineRunController.isClosed) {
      _pipelineRunController.add(msg);
    }
    // A pong, an unknown type or unparseable text needs nothing beyond the
    // watchdog reset above.
  }

  /// On an auth rejection this tries a silent re-login once and reconnects at
  /// once if it worked; everything else falls through to backoff.
  Future<void> _handleConnectError(Object error, int generation) async {
    // The cached query token is the likely culprit, so drop it and let the next
    // attempt re-mint.
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
    // Before teardown: the close code lives on the connection about to be
    // dropped, and the peer only fills it in once the stream is done.
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

  /// A remote close can land between the last frame and `onDone`/`onError`
  /// firing. `_conn` stays non-null across that window, so a ping can hit a
  /// closed sink and throw straight out of the timer callback, uncaught. The
  /// reconnect still happens when the callback finally delivers.
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

  /// Leaves `_retry` and the state alone — what those should become depends on
  /// which caller got here.
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

/// `package:web_socket_channel` wraps the original in
/// `WebSocketChannelException.inner`, and the wrapper's type says nothing —
/// `HandshakeException` versus `SocketException` is "TLS refused" versus
/// "nothing listening there".
Object wsInnerError(Object error) {
  final inner = error is WebSocketChannelException ? error.inner : error;
  return inner ?? error;
}

/// What `dart:io` attaches whenever a response came back and was not a 101,
/// or null when the server never responded at all.
int? wsHandshakeStatus(Object error) {
  final inner = wsInnerError(error);
  return inner is WebSocketException ? inner.httpStatusCode : null;
}

/// An auth rejection is the server *responding* without upgrading, unlike a
/// connectivity failure where re-login helps nothing.
///
/// Anchored on the real status, **not** a substring match on `toString()`: a
/// connectivity failure's message can embed the target port — a server on
/// `host:8403` would false-match "403" and turn a network hiccup into a
/// spurious re-login.
bool _defaultIsAuthError(Object error) {
  final code = wsHandshakeStatus(error);
  return code == 401 || code == 403;
}
