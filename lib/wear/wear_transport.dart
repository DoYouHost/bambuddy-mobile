// Private fields are named constructor params (can't be initializing formals,
// which may not start with `_`), so assignment happens in the initializer list.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:watch_connectivity/watch_connectivity.dart';

import '../core/models/printer.dart';
import '../core/models/printer_status.dart';
import '../core/watch/wear_rpc.dart';
import '../data/printer_commands_repository.dart';
import '../data/printers_repository.dart';
import '../data/queue_repository.dart';

/// The phone is definitely NOT executing the request (not reachable, send
/// failed, or it replied "unconfigured") — safe to retry over REST.
class WearRelayUnreachable implements Exception {
  @override
  String toString() => 'Phone unreachable';
}

/// No response within the timeout. Ambiguous: the phone may have executed the
/// command and only the reply got lost — commands must NOT auto-retry.
class WearRelayTimeout implements Exception {
  @override
  String toString() => 'Phone did not respond';
}

/// The phone executed the request and the server (or the phone itself)
/// returned an error. Retrying over REST would just repeat it.
class WearRelayRemoteError implements Exception {
  WearRelayRemoteError(this.code);

  final String code;

  @override
  String toString() => code;
}

/// What the watch needs from "the other side", regardless of whether that's
/// the phone (relay) or the server directly (REST). Screens and [WearActions]
/// only ever talk to this.
abstract interface class WearTransport {
  Future<List<PrinterWithStatus>> getFleet();
  Future<void> pause(int printerId);
  Future<void> resume(int printerId);
  Future<void> stop(int printerId);
  Future<void> clearPlate(int printerId);
  Future<void> startNext(int printerId);
}

/// Relay over the Wear Data Layer: every call is one `sendMessage` to the
/// phone plus a correlated reply on the shared message stream. When the phone
/// is nearby the bridge rides Bluetooth/BLE — much cheaper than the watch
/// holding its own WiFi connection.
class RelayTransport implements WearTransport {
  RelayTransport(this._watch, {this.timeout = const Duration(seconds: 4)});

  final WatchConnectivity _watch;
  final Duration timeout;

  final _pending = <String, Completer<WearRpcResponse>>{};
  StreamSubscription<Map<String, dynamic>>? _sub;

  void _ensureListening() {
    _sub ??= _watch.messageStream.listen((map) {
      final res = WearRpcResponse.decode(map);
      if (res == null) return;
      // Unknown/duplicate id (late reply after timeout, or a second engine on
      // the phone answering too) — drop it.
      _pending.remove(res.id)?.complete(res);
    });
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  Future<Map<String, dynamic>?> _call(WearRpcAction action,
      {int? printerId}) async {
    _ensureListening();
    // Cheap local check (connected nodes) before paying the send + timeout.
    var reachable = false;
    try {
      reachable = await _watch.isReachable;
    } catch (_) {}
    if (!reachable) throw WearRelayUnreachable();

    final req = WearRpcRequest.create(action, printerId: printerId);
    final completer = Completer<WearRpcResponse>();
    _pending[req.id] = completer;
    try {
      await _watch.sendMessage(req.encode());
    } catch (_) {
      _pending.remove(req.id);
      throw WearRelayUnreachable();
    }
    final WearRpcResponse res;
    try {
      res = await completer.future.timeout(timeout);
    } on TimeoutException {
      throw WearRelayTimeout();
    } finally {
      _pending.remove(req.id);
    }
    if (!res.ok) {
      final code = res.error ?? 'unknown';
      // Phone has no server profile → it never touched the server.
      if (code == 'phone-unconfigured') throw WearRelayUnreachable();
      // Same shape the REST path throws, so the UI label stays "Queue empty".
      if (code == 'empty-queue') throw StateError('empty-queue');
      throw WearRelayRemoteError(code);
    }
    return res.data;
  }

  @override
  Future<List<PrinterWithStatus>> getFleet() async {
    final data = await _call(WearRpcAction.getFleet);
    final list = data?['printers'];
    if (list is! List) return const [];
    final out = <PrinterWithStatus>[];
    // Tolerant per-entry parsing, mirroring parseJsonList: one malformed
    // printer drops that entry, not the whole fleet.
    for (final entry in list) {
      if (entry is! Map<String, dynamic>) continue;
      final rawPrinter = entry['printer'];
      if (rawPrinter is! Map<String, dynamic>) continue;
      final Printer printer;
      try {
        printer = Printer.fromJson(rawPrinter);
      } on Object {
        continue;
      }
      final rawStatus = entry['status'];
      PrinterStatus? status;
      if (rawStatus is Map<String, dynamic>) {
        try {
          status = PrinterStatus.fromJson(rawStatus);
        } on Object {
          status = null;
        }
      }
      out.add(PrinterWithStatus(printer: printer, status: status));
    }
    return out;
  }

  @override
  Future<void> pause(int printerId) =>
      _call(WearRpcAction.pause, printerId: printerId);

  @override
  Future<void> resume(int printerId) =>
      _call(WearRpcAction.resume, printerId: printerId);

  @override
  Future<void> stop(int printerId) =>
      _call(WearRpcAction.stop, printerId: printerId);

  @override
  Future<void> clearPlate(int printerId) =>
      _call(WearRpcAction.clearPlate, printerId: printerId);

  @override
  Future<void> startNext(int printerId) =>
      _call(WearRpcAction.startNext, printerId: printerId);
}

/// Direct REST to the server — the pre-relay behavior, kept as the fallback
/// when the phone is out of reach. Requires a configured profile on the watch.
class RestTransport implements WearTransport {
  RestTransport({
    required PrintersRepository printers,
    required PrinterCommandsRepository commands,
    required QueueRepository queue,
  })  : _printers = printers,
        _commands = commands,
        _queue = queue;

  final PrintersRepository _printers;
  final PrinterCommandsRepository _commands;
  final QueueRepository _queue;

  @override
  Future<List<PrinterWithStatus>> getFleet() => _printers.fetchAll();

  @override
  Future<void> pause(int printerId) => _commands.pause(printerId);

  @override
  Future<void> resume(int printerId) => _commands.resume(printerId);

  @override
  Future<void> stop(int printerId) => _commands.stop(printerId);

  @override
  Future<void> clearPlate(int printerId) => _commands.clearPlate(printerId);

  @override
  Future<void> startNext(int printerId) => _queue.startNextPending(printerId);
}

/// Which side actually served the last successful call.
enum WearTransportMode { relay, rest }

/// Relay-first with REST fallback (the "hybrid" from plan 05).
///
/// Reads fall back on both [WearRelayUnreachable] and [WearRelayTimeout] —
/// re-reading is always safe. Commands fall back only on
/// [WearRelayUnreachable]: after a timeout the phone may have already executed
/// the command (e.g. startNext), and repeating it over REST could double it.
class HybridWearTransport implements WearTransport {
  HybridWearTransport({required WearTransport relay, WearTransport? rest})
      : _relay = relay,
        _rest = rest;

  final WearTransport _relay;

  /// Null when the watch has no server profile (relay is then the only path).
  final WearTransport? _rest;

  /// Exposed so the fleet poller can slow down when relaying (each poll wakes
  /// the phone over the bridge). Null until the first successful call.
  WearTransportMode? lastMode;

  Future<T> _run<T>(
    Future<T> Function(WearTransport t) op, {
    required bool fallbackOnTimeout,
  }) async {
    try {
      final result = await op(_relay);
      lastMode = WearTransportMode.relay;
      return result;
    } on Exception catch (e) {
      final canFallback = e is WearRelayUnreachable ||
          (fallbackOnTimeout && e is WearRelayTimeout);
      final rest = _rest;
      if (!canFallback || rest == null) rethrow;
      final result = await op(rest);
      lastMode = WearTransportMode.rest;
      return result;
    }
  }

  @override
  Future<List<PrinterWithStatus>> getFleet() =>
      _run((t) => t.getFleet(), fallbackOnTimeout: true);

  @override
  Future<void> pause(int printerId) =>
      _run((t) => t.pause(printerId), fallbackOnTimeout: false);

  @override
  Future<void> resume(int printerId) =>
      _run((t) => t.resume(printerId), fallbackOnTimeout: false);

  @override
  Future<void> stop(int printerId) =>
      _run((t) => t.stop(printerId), fallbackOnTimeout: false);

  @override
  Future<void> clearPlate(int printerId) =>
      _run((t) => t.clearPlate(printerId), fallbackOnTimeout: false);

  @override
  Future<void> startNext(int printerId) =>
      _run((t) => t.startNext(printerId), fallbackOnTimeout: false);
}
