import 'dart:convert';

import '../models/printer_status.dart';

/// Parsed frame off `/api/v1/ws`. Sealed, so the WS manager switches
/// exhaustively. The rule everything here serves: **a new or incomplete server
/// frame must never crash the client** — unknown ones land in [WsUnknown], and
/// only genuinely unparseable text yields `null` from [parseWsMessage].
sealed class WsMessage {
  const WsMessage();
}

/// The frame's `data` is REST-status shaped but carries **no `id`** — the
/// identifier lives in `printer_id`, and [status] has it injected.
class WsPrinterStatus extends WsMessage {
  const WsPrinterStatus(this.status, this.raw);
  final PrinterStatus status;

  /// Kept so the watch relay can forward the server's JSON without
  /// re-serializing [status] — the models are parse-only.
  final Map<String, dynamic> raw;
}

/// Camera detection found objects on the plate at print start and bambuddy
/// **paused** the print. The only true source of this event: the status field
/// `awaiting_plate_clear` is a queue gate raised at *every* print end, so it
/// cannot serve as the trigger.
class WsPlateNotEmpty extends WsMessage {
  const WsPlateNotEmpty(this.printerId, this.printerName, this.message);
  final int printerId;
  final String? printerName;
  final String? message;
}

/// Purely a trigger to refresh queue and maintenance: their state changes
/// exactly at these moments — the queue advances, maintenance counters tick —
/// and the server pushes neither over WS.
class WsPrintEvent extends WsMessage {
  const WsPrintEvent(this.printerId, {required this.completed});
  final int printerId;
  final bool completed;
}

/// An archive gained something after the print was already over. The only part
/// read here is the finish photo the server captures off the camera once the
/// toolhead parks — it lands seconds to minutes after the print-complete frame,
/// and this is the announcement that it is there ([photoAdded] is its filename).
///
/// The same frame carries other updates (a timelapse attached, metadata edited);
/// those leave [photoAdded] null and the listener ignores them.
class WsArchiveUpdated extends WsMessage {
  const WsArchiveUpdated(this.archiveId, {this.photoAdded});
  final int archiveId;
  final String? photoAdded;
}

/// One pipeline run changed — sliced, dispatched, a copy finished, cancelled.
/// The frame carries the whole materialised run, so the dashboard replaces its
/// row rather than re-reading the page.
///
/// **Not a substitute for the poll.** The server routes this with
/// `broadcast_to_user(run.created_by, …)`, so a JWT session hears only about
/// runs it started itself; an auth-disabled install has no `created_by` and
/// falls back to a global broadcast. A dashboard showing a colleague's run gets
/// nothing here, which is why the timer stays.
class WsPipelineRunUpdated extends WsMessage {
  const WsPipelineRunUpdated(this.run);

  /// The run as `PipelineRunResponse` serialises it — parsed by the feature
  /// that cares, so `core/api` keeps no dependency on the run model.
  final Map<String, dynamic> run;
}

/// Any arriving frame resets the watchdog; this one is told apart so the
/// manager can separate control traffic from data.
class WsPong extends WsMessage {
  const WsPong();
}

/// Any other frame type, or a `printer_status` missing its `printer_id`/`data`.
/// `type` is kept for the log and not interpreted.
class WsUnknown extends WsMessage {
  const WsUnknown(this.type);
  final String? type;
}

/// `null` only for text that is not a JSON object, which the caller logs and
/// ignores. Everything else — incomplete and unknown types included — yields a
/// [WsMessage], and this never throws.
WsMessage? parseWsMessage(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;

  final type = decoded['type']?.toString();
  switch (type) {
    case 'printer_status':
      final data = decoded['data'];
      final printerId = _toIntOrNull(decoded['printer_id']);
      if (data is! Map<String, dynamic> || printerId == null) {
        return WsUnknown(type);
      }
      // Spread *after* the injection, so if the server ever starts sending `id`
      // inside `data` the payload wins.
      final merged = <String, dynamic>{'id': printerId, ...data};
      return WsPrinterStatus(PrinterStatus.fromJson(merged), merged);
    case 'plate_not_empty':
      final printerId = _toIntOrNull(decoded['printer_id']);
      if (printerId == null) return WsUnknown(type);
      return WsPlateNotEmpty(
        printerId,
        decoded['printer_name']?.toString(),
        decoded['message']?.toString(),
      );
    case 'print_start':
    case 'print_complete':
      final printerId = _toIntOrNull(decoded['printer_id']);
      if (printerId == null) return WsUnknown(type);
      return WsPrintEvent(printerId, completed: type == 'print_complete');
    case 'archive_updated':
      // Unlike the frames above, the id lives inside `data` — the server sends
      // the changed archive, not a printer-scoped event.
      final data = decoded['data'];
      if (data is! Map<String, dynamic>) return WsUnknown(type);
      final archiveId = _toIntOrNull(data['id']);
      if (archiveId == null) return WsUnknown(type);
      final photo = data['photo_added'];
      return WsArchiveUpdated(
        archiveId,
        photoAdded: photo is String && photo.isNotEmpty ? photo : null,
      );
    case 'pipeline_run_updated':
      // The run sits under `run`, not `data` — a third shape, alongside the
      // printer-scoped frames and `archive_updated`'s `data`.
      final run = decoded['run'];
      if (run is! Map<String, dynamic>) return WsUnknown(type);
      if (_toIntOrNull(run['id']) == null) return WsUnknown(type);
      return WsPipelineRunUpdated(run);
    case 'pong':
      return const WsPong();
    default:
      return WsUnknown(type);
  }
}

int? _toIntOrNull(Object? value) => switch (value) {
      num n => n.toInt(),
      String s => int.tryParse(s),
      _ => null,
    };
