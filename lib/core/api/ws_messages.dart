import 'dart:convert';

import '../models/printer_status.dart';

/// Sparsowana wiadomość ze strumienia WS `/api/v1/ws`.
///
/// Typ zapieczętowany → warstwa wyżej (menedżer WS) robi wyczerpujący
/// `switch`. Naczelna zasada: **nowy lub niekompletny typ ramki serwera
/// nigdy nie może wywalić klienta** — nieznane lądują w [WsUnknown],
/// całkowicie nieparsowalne dają `null` z [parseWsMessage].
sealed class WsMessage {
  const WsMessage();
}

/// Ramka `printer_status` — pełny stan jednej drukarki.
///
/// Serwer wysyła `{"type":"printer_status","printer_id":N,"data":{...}}`,
/// gdzie `data` ma kształt REST-owego statusu, ale **bez pola `id`**
/// (identyfikator jest tylko w `printer_id`). [status] ma już id wstrzyknięte.
class WsPrinterStatus extends WsMessage {
  const WsPrinterStatus(this.status);
  final PrinterStatus status;
}

/// Odpowiedź serwera na nasz heartbeat (`{"type":"pong"}`). Sam fakt
/// nadejścia JAKIEJKOLWIEK ramki resetuje watchdog; ten typ wyróżniamy,
/// by menedżer mógł odróżnić ruch sterujący od danych.
class WsPong extends WsMessage {
  const WsPong();
}

/// Każdy inny typ ramki (`bambuddy_print_progress`, `spoolbuddy_update`,
/// `firmware_upload_progress`, …) lub ramka `printer_status` bez kompletu
/// `printer_id`+`data`. Zachowujemy `type` do logów, nie interpretujemy.
class WsUnknown extends WsMessage {
  const WsUnknown(this.type);
  final String? type;
}

/// Parsuje surowy tekst ramki WS.
///
/// Zwraca `null` tylko gdy tekst nie jest obiektem JSON (nie-JSON albo
/// JSON nie-mapa) — wołający to loguje i ignoruje. Wszystko inne, łącznie
/// z niekompletnymi i nieznanymi typami, daje [WsMessage] (nigdy wyjątek).
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
        return WsUnknown(type); // niekompletna ramka — nie crashujemy
      }
      // `data` nie niesie `id`; wstrzykujemy z `printer_id`. Spread po
      // wstrzyknięciu znaczy, że gdyby serwer kiedyś dodał `id` do `data`,
      // to ono wygra — payload jest źródłem prawdy.
      final merged = <String, dynamic>{'id': printerId, ...data};
      return WsPrinterStatus(PrinterStatus.fromJson(merged));
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
