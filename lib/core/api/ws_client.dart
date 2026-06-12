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
    Future<bool> Function()? refreshAuth,
    bool Function(Object error)? isAuthError,
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
        // ignore: prefer_initializing_formals
        _refreshAuth = refreshAuth,
        _isAuthError = isAuthError ?? _defaultIsAuthError,
        _backoff = backoff ?? WsBackoff();

  final Uri _url;
  final Future<Map<String, String>> Function() _authHeaders;
  final WsConnector _connect;
  final WsBackoff _backoff;

  /// Próba odświeżenia poświadczeń (cichy re-login JWT) gdy serwer odrzuci
  /// handshake. `true` = zdobyto świeże poświadczenia, warto spróbować od
  /// razu. `null` (tryb apiKey/none) → nie ma czego odświeżać, zwykły backoff.
  final Future<bool> Function()? _refreshAuth;

  /// Czy błąd handshake'u to odrzucenie auth (a nie brak łączności).
  final bool Function(Object error) _isAuthError;

  /// Re-login podejmujemy najwyżej raz na serię niepowodzeń — zerowane po
  /// udanym połączeniu. Chroni przed pętlą login→401→login, gdy świeży token
  /// też jest odrzucany (np. konto wymaga ponownej konfiguracji).
  bool _authRefreshed = false;

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
    _authRefreshed = false; // świeża seria prób — wolno znów spróbować re-login
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
    } catch (e) {
      if (generation != _generation) return;
      await _handleConnectError(e, generation);
      return;
    }
    // W trakcie handshake'u mogło przyjść suspend()/dispose() albo nowszy
    // generation — wtedy porzucamy świeże połączenie.
    if (generation != _generation || !_running || _disposed) {
      await conn.close();
      return;
    }

    _conn = conn;
    _authRefreshed = false; // udane połączenie → wolno znów spróbować re-login
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

  /// Błąd handshake'u. Jeśli serwer odrzucił auth, a mamy czym odświeżyć
  /// (JWT), próbujemy raz cichego re-loginu i — przy sukcesie — łączymy od
  /// razu z nowym tokenem. W przeciwnym razie zwykły backoff.
  Future<void> _handleConnectError(Object error, int generation) async {
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

/// Domyślny klasyfikator: błąd handshake'u to odrzucenie auth, gdy serwer
/// ODPOWIEDZIAŁ, ale nie zrobił upgrade'u (401/403, „not upgraded") — w
/// odróżnieniu od braku łączności (SocketException, timeout), gdzie re-login
/// nic nie da. `dart:io` przy 401 nie wystawia czystego kodu, więc łapiemy też
/// komunikat „not upgraded to websocket".
bool _defaultIsAuthError(Object error) {
  final s = error.toString().toLowerCase();
  return s.contains('401') ||
      s.contains('403') ||
      s.contains('unauthorized') ||
      s.contains('forbidden') ||
      s.contains('not upgraded');
}
