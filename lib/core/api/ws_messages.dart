import 'dart:convert';

import '../models/printer_status.dart';

/// Parsed message from WebSocket stream `/api/v1/ws`.
///
/// Sealed type → upper layer (WS manager) does exhaustive switch. Core rule:
/// **new or incomplete server frame type must never crash the client** —
/// unknown land in [WsUnknown], completely unparseable returns `null` from
/// [parseWsMessage].
sealed class WsMessage {
  const WsMessage();
}

/// `printer_status` frame — full state of one printer.
///
/// Server sends `{"type":"printer_status","printer_id":N,"data":{...}}`,
/// where `data` has shape of REST status, but **WITHOUT `id` field**
/// (identifier only in `printer_id`). [status] has id already injected.
class WsPrinterStatus extends WsMessage {
  const WsPrinterStatus(this.status, this.raw);
  final PrinterStatus status;

  /// The merged frame `data` as received (id injected), REST-status shaped.
  /// Kept so the watch relay can forward server JSON without re-serializing
  /// [status] (models are parse-only).
  final Map<String, dynamic> raw;
}

/// `plate_not_empty` frame — camera detection found objects on plate at
/// print start and bambuddy **paused** the print (analogous to
/// `on_plate_not_empty` push in backend). This is the ONLY true source of
/// "plate not empty" event — field `awaiting_plate_clear` from status is just
/// a queue gate raised on EVERY print end, so unsuitable as trigger.
///
/// Server sends `{"type":"plate_not_empty","printer_id":N,"printer_name":…,
/// "message":…}`.
class WsPlateNotEmpty extends WsMessage {
  const WsPlateNotEmpty(this.printerId, this.printerName, this.message);
  final int printerId;
  final String? printerName;
  final String? message;
}

/// Print lifecycle frame (`print_start` / `print_complete`). Carries only the
/// printer id — used purely as a trigger to refresh queue/maintenance, whose
/// state changes exactly at these moments (queue advances, maintenance counters
/// tick) but which the server does NOT push over WS directly.
class WsPrintEvent extends WsMessage {
  const WsPrintEvent(this.printerId, {required this.completed});
  final int printerId;

  /// `true` for `print_complete`, `false` for `print_start`.
  final bool completed;
}

/// Server response to our heartbeat (`{"type":"pong"}`). The mere arrival of
/// ANY frame resets the watchdog; we distinguish this type so the manager can
/// tell control traffic from data.
class WsPong extends WsMessage {
  const WsPong();
}

/// Any other frame type (`bambuddy_print_progress`, `spoolbuddy_update`,
/// `firmware_upload_progress`, …) or `printer_status` frame missing complete
/// `printer_id`+`data`. We keep `type` for logs, don't interpret.
class WsUnknown extends WsMessage {
  const WsUnknown(this.type);
  final String? type;
}

/// Parses raw WebSocket frame text.
///
/// Returns `null` only when text is not JSON object (non-JSON or
/// JSON non-map) — caller logs and ignores. Everything else, including
/// incomplete and unknown types, yields [WsMessage] (never throws).
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
        return WsUnknown(type); // incomplete frame — don't crash
      }
      // `data` doesn't carry `id`; we inject from `printer_id`. Spread after
      // injection means if server ever adds `id` to `data`, it wins — payload
      // is source of truth.
      final merged = <String, dynamic>{'id': printerId, ...data};
      return WsPrinterStatus(PrinterStatus.fromJson(merged), merged);
    case 'plate_not_empty':
      final printerId = _toIntOrNull(decoded['printer_id']);
      if (printerId == null) return WsUnknown(type); // without id, unclear whose
      return WsPlateNotEmpty(
        printerId,
        decoded['printer_name']?.toString(),
        decoded['message']?.toString(),
      );
    case 'print_start':
    case 'print_complete':
      final printerId = _toIntOrNull(decoded['printer_id']);
      if (printerId == null) return WsUnknown(type); // without id, unclear whose
      return WsPrintEvent(printerId, completed: type == 'print_complete');
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
