import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/printer_status.dart';
import 'ws_backoff.dart';
import 'ws_messages.dart';

/// Stan połączenia WS — źródło dla banera w UI.
///
/// `suspended` jest osobny od `disconnected`: oznacza świadome wstrzymanie
/// na czas tła aplikacji (zero prób reconnect), a nie awarię.
enum WsConnectionState {
  disconnected,
  connecting,
  connected,
  waitingRetry,
  suspended,
}

/// Minimalny kontrakt połączenia WS. Pozwala wstrzyknąć fake w testach bez
/// implementowania całego [WebSocketChannel]; produkcyjnie owija
/// [IOWebSocketChannel] (obsługuje nagłówki auth na handshake'u — czego
/// przeglądarkowy WebSocket nie potrafi).
abstract class WsConnection {
  /// Kończy się po udanym handshake'u; rzuca, gdy połączenie się nie uda
  /// (serwer down, 401/403 na upgrade).
  Future<void> get ready;
  Stream<dynamic> get stream;
  void send(String data);
  Future<void> close();
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
}

WsConnection _defaultConnect(Uri url, Map<String, String> headers) =>
    _IoWsConnection(IOWebSocketChannel.connect(url, headers: headers));

/// Klient WebSocketa bambuddy: jedno multipleksujące połączenie z
/// `/api/v1/ws`, składające strumień ramek `printer_status`.
///
/// Dwa wyjścia dla warstwy wyżej: [connectionStates] (baner) i [statuses]
/// (najnowszy stan per drukarka montuje provider). Niezawodność wg §3 planu:
/// backoff z jitterem ([WsBackoff]), heartbeat ping + watchdog na ciszę,
/// jawne [suspend]/[resume] pod cykl życia aplikacji.
///
/// Auth jest nagłówkowy (patrz pamięć ws-contract-m2) — brak mintowania
/// tokenu; przy zmianie/wygaśnięciu poświadczeń wystarcza reconnect z
/// nowymi nagłówkami (świeżo czytanymi z [authHeaders] przy każdej próbie).
class WsClient {
  WsClient({
    required Uri url,
    required Future<Map<String, String>> Function() authHeaders,
    WsConnector connect = _defaultConnect,
    WsBackoff? backoff,
    this.heartbeatInterval = const Duration(seconds: 25),
    this.idleTimeout = const Duration(seconds: 60),
    this.stableThreshold = const Duration(seconds: 30),
  })  :
        // Publiczne nazwy parametrów + prywatne pola: nazwana formalna
        // inicjalizująca nie może być prywatna, więc lint jest tu niespełnialny.
        // ignore: prefer_initializing_formals
        _url = url,
        // ignore: prefer_initializing_formals
        _authHeaders = authHeaders,
        // ignore: prefer_initializing_formals
        _connect = connect,
        _backoff = backoff ?? WsBackoff();

  final Uri _url;
  final Future<Map<String, String>> Function() _authHeaders;
  final WsConnector _connect;
  final WsBackoff _backoff;

  /// Odstęp między pingami heartbeat.
  final Duration heartbeatInterval;

  /// Brak JAKIEJKOLWIEK ramki przez ten czas → wymuszony reconnect
  /// (łapie półotwarte TCP po roamingu Wi-Fi).
  final Duration idleTimeout;

  /// Połączenie musi przeżyć tyle, by uznać je za stabilne i wyzerować
  /// backoff — inaczej flapping kasowałby narastanie opóźnień.
  final Duration stableThreshold;

  final _stateController = StreamController<WsConnectionState>.broadcast();
  final _statusController = StreamController<PrinterStatus>.broadcast();

  WsConnection? _conn;
  StreamSubscription<dynamic>? _sub;
  Timer? _heartbeat;
  Timer? _watchdog;
  Timer? _stable;
  Timer? _retry;

  var _state = WsConnectionState.disconnected;
  bool _running = false;
  bool _disposed = false;

  /// Rośnie przy każdej próbie połączenia; unieważnia spóźnione callbacki
  /// (ramki/zamknięcia) ze starego, już porzuconego socketa.
  int _generation = 0;

  WsConnectionState get state => _state;
  Stream<WsConnectionState> get connectionStates => _stateController.stream;
  Stream<PrinterStatus> get statuses => _statusController.stream;

  /// Rozpoczyna łączenie (idempotentne). Po [suspend] wznawiaj przez [resume].
  void start() {
    if (_disposed || _running) return;
    _running = true;
    _openConnection();
  }

  /// Aplikacja w tle: zamknij socket, stan `suspended`, żadnych reconnectów.
  void suspend() {
    if (_disposed || _state == WsConnectionState.suspended) return;
    _running = false;
    _retry?.cancel();
    _teardownConnection();
    _setState(WsConnectionState.suspended);
  }

  /// Powrót z tła. Wołający robi najpierw backfill REST, potem to.
  void resume() {
    if (_disposed || _running) return;
    _backoff.reset();
    start();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _running = false;
    _retry?.cancel();
    _teardownConnection();
    await _stateController.close();
    await _statusController.close();
  }

  Future<void> _openConnection() async {
    if (!_running || _disposed) return;
    final generation = ++_generation;
    _setState(WsConnectionState.connecting);

    // Nagłówki czytane przy KAŻDEJ próbie — łapie odświeżony JWT/klucz.
    Map<String, String> headers;
    try {
      headers = await _authHeaders();
    } catch (_) {
      headers = const {};
    }
    if (generation != _generation || !_running || _disposed) return;

    final WsConnection conn;
    try {
      conn = _connect(_url, headers);
      await conn.ready;
    } catch (_) {
      if (generation != _generation) return;
      _scheduleRetry();
      return;
    }
    // W trakcie handshake'u mogło przyjść suspend()/dispose() albo nowszy
    // generation — wtedy porzucamy świeże połączenie.
    if (generation != _generation || !_running || _disposed) {
      await conn.close();
      return;
    }

    _conn = conn;
    _setState(WsConnectionState.connected);
    _sub = conn.stream.listen(
      (data) => _onFrame(generation, data),
      onError: (_) => _onClosed(generation),
      onDone: () => _onClosed(generation),
      cancelOnError: true,
    );
    _startHeartbeat();
    _resetWatchdog(generation);
    _stable = Timer(stableThreshold, _backoff.reset);
  }

  void _onFrame(int generation, dynamic data) {
    if (generation != _generation) return;
    _resetWatchdog(generation); // każda ramka = żywy socket
    if (data is! String) return;
    final msg = parseWsMessage(data);
    if (msg is WsPrinterStatus && !_statusController.isClosed) {
      _statusController.add(msg.status);
    }
    // WsPong/WsUnknown/null: watchdog już zresetowany — nic więcej.
  }

  void _onClosed(int generation) {
    if (generation != _generation) return;
    _teardownConnection();
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (!_running || _disposed) return;
    _setState(WsConnectionState.waitingRetry);
    _retry?.cancel();
    _retry = Timer(_backoff.nextDelay(), _openConnection);
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(
      heartbeatInterval,
      (_) => _conn?.send(jsonEncode({'type': 'ping'})),
    );
  }

  void _resetWatchdog(int generation) {
    _watchdog?.cancel();
    _watchdog = Timer(idleTimeout, () => _onClosed(generation));
  }

  /// Zamyka bieżące połączenie i kasuje wszystkie z nim związane timery.
  /// NIE rusza `_retry` ani stanu — to robią wołający wedle kontekstu.
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
    if (!_stateController.isClosed) _stateController.add(next);
  }
}
