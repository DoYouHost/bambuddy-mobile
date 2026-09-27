import 'package:app_util/app_util.dart';

// bambuddy's own reading of a server instant. The tolerant coercion around it
// lives in `app_util`; this part is here because it encodes how bambuddy's
// server stores time, which lubelogger's does not share.

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
  if (_hasTimeOfDay.hasMatch(raw) && !_zoneSuffix.hasMatch(raw)) {
    raw = '${raw}Z';
  }
  return DateTime.tryParse(raw)?.toLocal();
}

/// An instant the server can compare against its own columns.
///
/// UTC but **without** the `Z`: the columns are naive UTC (`DateTime` with no
/// timezone), and a tz-aware bind param compares against those differently
/// depending on the database behind the server. Sending a bare `YYYY-MM-DD`
/// instead — as the web does — lands on UTC midnight and quietly shifts the
/// range for anyone not on UTC. `toIso8601String` would append the `Z` and the
/// milliseconds, so the string is built here.
String instantToJson(DateTime value) {
  final utc = value.toUtc();
  return '${calendarDateToJson(utc)}T'
      '${_pad(utc.hour, 2)}:${_pad(utc.minute, 2)}:${_pad(utc.second, 2)}';
}

String _pad(int value, int width) => value.toString().padLeft(width, '0');
