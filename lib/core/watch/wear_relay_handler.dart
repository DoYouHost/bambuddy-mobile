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
import '../models/queue_item.dart';
import 'wear_relay_claim.dart';
import 'wear_rpc.dart';

/// PHONE side of the watch relay (plan 05, M-R3 "app alive" variant): answers
/// [WearRpcRequest]s from the paired watch using the phone's authenticated
/// connection, so the watch doesn't need its own WiFi/server session.
///
/// Runs only while a Flutter engine hosts it: the app's own, the foreground
/// service's, or the headless one the native listener service starts when the
/// process was dead (`wear_relay_engine.dart`). Which of them may answer at any
/// moment is decided by [WearRelayClaim].
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
  /// [claim] tells the native listener service that this process is answering,
  /// so a request never reaches both a listener and a freshly woken engine.
  /// Null where there is nothing to coordinate with: tests, and the woken
  /// engine itself — that one never listens, the service hands it each request.
  WearRelayHandler({
    required WatchConnectivity watch,
    required Dio? Function() dio,
    Map<String, dynamic>? Function(int printerId)? liveStatus,
    WearRelayClaim? claim,
  })  : _watch = watch,
        _dio = dio,
        _liveStatus = liveStatus,
        _claim = claim;

  final WatchConnectivity _watch;
  final Dio? Function() _dio;
  final Map<String, dynamic>? Function(int printerId)? _liveStatus;
  final WearRelayClaim? _claim;

  StreamSubscription<Map<String, dynamic>>? _sub;

  /// The tail of the start/stop chain — see [_sequenced].
  Future<void> _pending = Future<void>.value();

  /// Idempotent. Requests are handled sequentially per message (each handled
  /// in its own async task; the stream isn't awaited) — fine for a watch that
  /// sends one request at a time per screen.
  ///
  /// Claim first, listener second — and the reverse in [stop]. Between those
  /// two acts the native service believes nobody is answering, and a request
  /// arriving then would be answered by a woken engine as well as by this
  /// listener. A claim that could not be written means no listener at all, for
  /// the same reason.
  Future<void> start() => _sequenced(() async {
        if (_sub != null) return;
        final claim = _claim;
        if (claim != null && !await claim.take()) return;
        _sub = _watch.messageStream.listen((map) {
          final req = WearRpcRequest.decode(map);
          if (req == null) return; // foreign message or our own response echo
          unawaited(handle(req));
        });
      });

  Future<void> stop() => _sequenced(() async {
        await _sub?.cancel();
        _sub = null;
        await _claim?.release();
      });

  /// Runs start/stop one at a time.
  ///
  /// Each of them is two steps — the claim and the subscription — and every
  /// caller is a lifecycle callback that fires them without awaiting, so the
  /// next one arrives while the previous is still in flight. Interleaved, they
  /// leave either a listener with no claim (a woken engine answers the same
  /// request) or a claim with no listener (nothing answers at all), and
  /// `start`'s own `_sub` check would read a subscription that `stop` is
  /// half-way through cancelling.
  Future<void> _sequenced(Future<void> Function() step) {
    final done = _pending.then((_) => step());
    // A step that failed must not wedge the ones queued behind it.
    _pending = done.catchError((_) {});
    return done;
  }

  /// Executes one request and sends the reply back to the watch.
  ///
  /// Public for the one caller that has no stream to receive from: the request
  /// that woke a dead process was consumed by the native listener service
  /// before this engine existed, so it is handed over directly.
  Future<void> handle(WearRpcRequest req) async {
    WearRpcResponse res;
    try {
      res = await _execute(req);
    } on StateError catch (e) {
      // startNext with nothing pending — a first-class outcome, not a crash.
      res = WearRpcResponse.failure(req.id, e.message);
    } on AppApiException catch (e) {
      // The code drives the watch's own wording; the detail is what the server
      // said, and on a 403 it is the only place the missing permission appears.
      res = WearRpcResponse.failure(req.id, e.code.name, reason: e.detail);
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
      case WearRpcAction.hmsClear:
        await commands.clearHmsErrors(printerId);
      case WearRpcAction.hmsAction:
        final printError = req.printError;
        final hmsAction = req.hmsAction;
        // Neither is recoverable here: the firmware matches on the code and the
        // route rejects anything that is not 8 or 16 hex digits, so a request
        // missing either was malformed before it left the watch.
        if (printError == null || hmsAction == null) {
          return WearRpcResponse.failure(req.id, 'bad-request');
        }
        await commands.executeHmsAction(printerId,
            printError: printError, action: hmsAction, jobId: req.jobId);
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
    // Waiting-to-print count for the watch's "start next" button. A failed
    // queue fetch just omits the key (unknown on the watch), same tolerance
    // as a failed status.
    int? queuePending;
    try {
      // Filtered server-side: a count is all the watch shows, and the
      // unfiltered endpoint answers with the entire print history.
      final items = await QueueRepository(dio).fetch(status: 'pending');
      // The filter is still applied here — a server that ignored the query
      // would otherwise turn the whole history into the watch's "waiting" count.
      queuePending = items
          .where((q) => q.statusKind == QueueItemStatusKind.pending)
          .length;
    } catch (_) {}
    return {
      'printers': [
        for (var i = 0; i < printers.length; i++)
          {
            'printer': printers[i],
            if (statuses[i] != null) 'status': statuses[i],
          },
      ],
      'queuePending': ?queuePending,
    };
  }
}
