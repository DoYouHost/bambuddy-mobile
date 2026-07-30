import '../diagnostics/diagnostic_recorder.dart';
import '../diagnostics/log_event.dart';

// Shared tolerant JSON coercion helpers for `@JsonKey(fromJson: ...)` and
// hand-written `fromJson` factories across the model layer.
//
// Call-sites across the data layer wrap per-item list parsing in
// catch-and-skip (`if (item is! Map) continue;` / `on Object { continue; }`)
// so one malformed server record only drops that one entry instead of the
// whole response. The plain generated casts (`e as Map<String, dynamic>`,
// `DateTime.parse(x as String)`) don't have that tolerance built in — a bad
// element throws straight through `fromJson`, past that per-item guard,
// silently discarding the entire parent list/record instead of just the
// one bad leaf. Numeric/string coercion below was independently
// reimplemented (`_int`/`_toInt`, `_double`/`_toDouble`, `_str`) across many
// model files with the same shape — centralized here.

/// A trailing zone marker: `Z`, `+02:00`, `-0500`.
final _zoneSuffix = RegExp(r'(?:[Zz]|[+-]\d{2}:?\d{2})$');

/// An offset immediately followed by `Z` — the server's own malformed output.
final _offsetThenZ = RegExp(r'[+-]\d{2}:?\d{2}[Zz]$');

/// Whether the value carries a time of day, so appending a zone marker means
/// something. A bare `2026-07-30` is a calendar date and gets left alone.
final _hasTimeOfDay = RegExp(r'\d{2}:\d{2}');

/// Tolerant parse of a server **instant**, returned in the device's local time.
/// Malformed or non-string values yield `null` instead of throwing.
///
/// Three things this has to get right, each learned from a real payload rather
/// than from the schema:
///
/// 1. **A zoneless timestamp means UTC.** bambuddy keeps UTC in naive columns
///    (`DateTime` + `server_default=func.now()`) and only some schemas add the
///    `Z` on the way out — one queue record carries
///    `created_at: "…T11:42:09.451817Z"` while an archive carries
///    `started_at: "…T06:15:10.233878"`, the same kind of value in two
///    spellings. Dart reads a zoneless string as **local**, so taking the server
///    at its word put every archive date and every statistics bucket off by the
///    device's offset. Confirmed against a live server: `last_checked:
///    "11:45:22.746336"` arrived 1.4 s before a request logged at `11:45:24Z`.
/// 2. **`+00:00Z` happens.** `serialize_utc_datetime` appends `Z` to a value
///    whose `isoformat()` already produced `+00:00`, so a `PATCH /queue/{id}`
///    answers `scheduled_time: "2026-07-30T16:00:00+00:00Z"` — which no ISO-8601
///    parser accepts, `DateTime.tryParse` included. The same field is well formed
///    on the next `GET`, once it has been round-tripped through the database.
///    Nothing reads that response body today, so the redundant `Z` is dropped
///    here to keep it that way when something eventually does.
/// 3. **Local, not UTC.** Every consumer formats the fields directly
///    (`d.hour`, `d.day`) or buckets on them, and only three sites in the app
///    remembered to call `toLocal()` first. Converting once, here, is what makes
///    the other sites correct by default instead of correct by vigilance.
///
/// For a calendar date — a value the user picked as a date and not as a moment —
/// use [calendarDateFromJson] instead: converting those across zones is what
/// moves a due date to the previous day.
DateTime? dateTimeFromJson(dynamic value) {
  if (value is! String) return null;
  var raw = value.trim();
  if (raw.isEmpty) return null;
  if (_offsetThenZ.hasMatch(raw)) raw = raw.substring(0, raw.length - 1);
  if (_hasTimeOfDay.hasMatch(raw) && !_zoneSuffix.hasMatch(raw)) raw = '${raw}Z';
  return DateTime.tryParse(raw)?.toLocal();
}

/// Tolerant parse of a **calendar date**, kept as the date the server wrote.
///
/// A project's `due_date` is picked as a date and sent back as `YYYY-MM-DD`
/// (`project_form_screen`), but the server stores it in a datetime column and
/// answers with midnight. Through [dateTimeFromJson] that midnight would cross a
/// day boundary for every device west of UTC — a project due on the 5th would
/// read as the 4th — so the calendar fields are taken as written and rebuilt as
/// a local midnight. No zone conversion, because a due date is not an instant.
DateTime? calendarDateFromJson(dynamic value) {
  if (value is! String) return null;
  final parsed = DateTime.tryParse(value.trim());
  return parsed == null
      ? null
      : DateTime(parsed.year, parsed.month, parsed.day);
}

/// Tolerant list parse: skips elements that aren't the expected shape, and
/// skips (rather than propagates) any element [fromJson] itself fails to
/// parse — one malformed record drops just that entry instead of the whole
/// list/parent.
/// Every skip is also recorded while a diagnostic recording runs. Tolerance is
/// what keeps one bad record from emptying a screen, and it is also what makes
/// a whole screen go empty in silence when the server changes a field the
/// generated casts insist on — that shows up as a 200 with nothing on screen,
/// which is indistinguishable from "there was nothing to show" unless the drop
/// says so itself.
List<T> parseJsonList<T>(
  dynamic value,
  T Function(Map<String, dynamic>) fromJson,
) {
  if (value is! List) return const [];
  final out = <T>[];
  var dropped = 0;
  String? cause;
  for (final item in value) {
    if (item is! Map<String, dynamic>) {
      dropped++;
      cause ??= 'not an object: ${item.runtimeType}';
      continue;
    }
    try {
      out.add(fromJson(item));
    } on Object catch (e) {
      dropped++;
      // The first failure only: a field the server renamed fails the same way
      // on every record, and one copy of the message names the field.
      cause ??= e.toString();
      continue;
    }
  }
  if (dropped > 0) {
    DiagnosticRecorder.active?.add(
      LogSource.app,
      'parse_drop',
      lvl: LogLevel.warn,
      fields: {
        'type': T.toString(),
        'n': dropped,
        'of': value.length,
        'cause': cause,
      },
    );
  }
  return out;
}

/// Tolerant `int?` coercion: accepts `int`, other `num` (truncated), or a
/// parseable `String`; anything else (including non-numeric strings) → `null`.
int? toIntOrNull(dynamic value) => switch (value) {
      int n => n,
      num n => n.toInt(),
      String s => int.tryParse(s),
      _ => null,
    };

/// [toIntOrNull] with a `0` fallback — for fields the server always sends,
/// where coercion failure should read as "0" rather than propagate `null`.
int toInt(dynamic value) => toIntOrNull(value) ?? 0;

/// Tolerant `double?` coercion: accepts any `num` or a parseable `String`.
double? toDoubleOrNull(dynamic value) => switch (value) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };

/// [toDoubleOrNull] with a `0` fallback.
double toDouble(dynamic value) => toDoubleOrNull(value) ?? 0;

/// Tolerant non-empty `String?`: non-strings, blank, or whitespace-only → `null`.
String? toStringOrNull(dynamic value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Tolerant `Map<String, int>` coercion — server aggregates keyed by a
/// stringified id (e.g. `prints_by_printer`).
Map<String, int> toIntMap(dynamic value) {
  if (value is! Map) return const {};
  final out = <String, int>{};
  value.forEach((key, v) => out['$key'] = toInt(v));
  return out;
}

/// Tolerant `Map<String, double>` coercion, see [toIntMap].
Map<String, double> toDoubleMap(dynamic value) {
  if (value is! Map) return const {};
  final out = <String, double>{};
  value.forEach((key, v) => out['$key'] = toDouble(v));
  return out;
}

/// Tolerant `List<String>` coercion: keeps only string elements.
List<String> toStringList(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList();
}
