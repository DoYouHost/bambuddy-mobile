// Private fields are named constructor params (can't be initializing formals,
// which may not start with `_`), so assignment happens in the initializer list.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

import '../../data/printer_commands_repository.dart';
import '../../data/queue_repository.dart';
import '../api/api_exceptions.dart';
import '../api/endpoints.dart';
import '../models/json_utils.dart';
import 'wear_rpc.dart';

/// PHONE side of the watch relay (plan 05, M-R3 "app alive" variant): answers
/// [WearRpcRequest]s from the paired watch using the phone's authenticated
/// connection, so the watch doesn't need its own WiFi/server session.
///
/// Runs only while a Flutter engine hosts it (started from the phone app's
/// root widget). With the app fully dead nothing answers and the watch falls
/// back to direct REST — waking the phone without a live engine is M-R4.
///
/// Fleet statuses are fetched as raw JSON (models are parse-only, no toJson)
/// and passed through untouched; the watch parses them with the same
/// `fromJson`s it uses for direct REST.
class WearRelayHandler {
  /// [dio] returns the current authenticated client, or null when no server
  /// profile is configured (the watch is then told `phone-unconfigured`).
  ///
  /// [liveStatus] (FGS isolate only) returns the raw last-known WS status
  /// frame for a printer, or null when there's nothing trustworthy (WS down /
  /// printer never seen) — the handler then falls back to a REST status fetch
  /// for that printer.
  WearRelayHandler({
    required WatchConnectivity watch,
    required Dio? Function() dio,
    Map<String, dynamic>? Function(int printerId)? liveStatus,
  })  : _watch = watch,
        _dio = dio,
        _liveStatus = liveStatus;

  final WatchConnectivity _watch;
  final Dio? Function() _dio;
  final Map<String, dynamic>? Function(int printerId)? _liveStatus;

  StreamSubscription<Map<String, dynamic>>? _sub;

  /// Idempotent. Requests are handled sequentially per message (each handled
  /// in its own async task; the stream isn't awaited) — fine for a watch that
  /// sends one request at a time per screen.
  void start() {
    _sub ??= _watch.messageStream.listen((map) {
      final req = WearRpcRequest.decode(map);
      if (req == null) return; // foreign message or our own response echo
      unawaited(_handle(req));
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _handle(WearRpcRequest req) async {
    WearRpcResponse res;
    try {
      res = await _execute(req);
    } on StateError catch (e) {
      // startNext with nothing pending — a first-class outcome, not a crash.
      res = WearRpcResponse.failure(req.id, e.message);
    } on AppApiException catch (e) {
      // Short machine-readable code; the watch shows it as-is.
      res = WearRpcResponse.failure(req.id, e.code.name);
    } catch (_) {
      res = WearRpcResponse.failure(req.id, 'phone-error');
    }
    try {
      await _watch.sendMessage(res.encode());
    } catch (_) {
      // Watch went out of reach mid-request; its timeout handles the rest.
    }
  }

  Future<WearRpcResponse> _execute(WearRpcRequest req) async {
    final dio = _dio();
    if (dio == null) {
      return WearRpcResponse.failure(req.id, 'phone-unconfigured');
    }
    if (req.action == WearRpcAction.getFleet) {
      return WearRpcResponse.ok(req.id, await _fleet(dio));
    }
    final printerId = req.printerId;
    if (printerId == null) {
      return WearRpcResponse.failure(req.id, 'bad-request');
    }
    final commands = PrinterCommandsRepository(dio);
    switch (req.action) {
      case WearRpcAction.pause:
        await commands.pause(printerId);
      case WearRpcAction.resume:
        await commands.resume(printerId);
      case WearRpcAction.stop:
        await commands.stop(printerId);
      case WearRpcAction.clearPlate:
        await commands.clearPlate(printerId);
      case WearRpcAction.startNext:
        await QueueRepository(dio).startNextPending(printerId);
      case WearRpcAction.getFleet:
        throw StateError('unreachable'); // handled above
    }
    return WearRpcResponse.ok(req.id);
  }

  /// Raw printers + statuses, same parallel fan-out as
  /// `PrintersRepository.fetchAll` but without parsing into models. A failed
  /// status fetch drops just that printer's status (offline card on the
  /// watch), never the whole fleet. Statuses come from the live WS cache when
  /// [_liveStatus] provides them — then a getFleet costs one REST call (the
  /// printer list) instead of 1+N.
  Future<Map<String, dynamic>> _fleet(Dio dio) async {
    final res = await guard(() => dio.get<List<dynamic>>(Endpoints.printers));
    final printers =
        (res.data ?? const []).whereType<Map<String, dynamic>>().toList();
    final statuses = await Future.wait(printers.map((p) async {
      final id = toIntOrNull(p['id']);
      if (id == null) return null;
      final live = _liveStatus?.call(id);
      if (live != null) return live;
      try {
        final s =
            await dio.get<Map<String, dynamic>>(Endpoints.printerStatus(id));
        return s.data;
      } catch (_) {
        return null;
      }
    }));
    return {
      'printers': [
        for (var i = 0; i < printers.length; i++)
          {
            'printer': printers[i],
            if (statuses[i] != null) 'status': statuses[i],
          },
      ],
    };
  }
}
