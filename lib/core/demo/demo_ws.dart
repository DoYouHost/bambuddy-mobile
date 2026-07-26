import 'dart:async';
import 'dart:convert';

import '../api/ws_client.dart';
import 'demo_backend.dart';

/// [WsConnector] for demo mode — plug into `WsClient(connect: ...)`.
WsConnection demoWsConnector(Uri url, Map<String, String> headers) =>
    DemoWsConnection();

/// Fake WebSocket fed from [DemoBackend]: emits a `printer_status` frame per
/// printer every few seconds (the simulated print advances on the wall clock)
/// and answers pings, keeping `WsClient`'s idle watchdog happy.
class DemoWsConnection implements WsConnection {
  DemoWsConnection() {
    _controller = StreamController<dynamic>(
      onListen: () {
        _emitAll();
        _timer = Timer.periodic(const Duration(seconds: 3), (_) => _emitAll());
      },
      onCancel: () => _timer?.cancel(),
    );
  }

  late final StreamController<dynamic> _controller;
  Timer? _timer;

  static const _printerIds = [1, 2];

  void _emitAll() {
    if (_controller.isClosed) return;
    for (final id in _printerIds) {
      _controller.add(jsonEncode({
        'type': 'printer_status',
        'printer_id': id,
        'data': DemoBackend.instance.statusData(id),
      }));
    }
  }

  @override
  Future<void> get ready => Future.value();

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  void send(String data) {
    if (_controller.isClosed) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException {
      return;
    }
    if (decoded is Map && decoded['type'] == 'ping') {
      _controller.add(jsonEncode(const {'type': 'pong'}));
    }
    if (decoded is Map && decoded['type'] == 'get_status') {
      _emitAll();
    }
  }

  @override
  Future<void> close() async {
    _timer?.cancel();
    await _controller.close();
  }

  /// Nothing on the other side to send one: the demo socket is a stream in this
  /// isolate, not a peer that can hang up with a code.
  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;
}
