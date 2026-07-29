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

/// Tolerant `DateTime?` parse: malformed or non-string timestamps yield
/// `null` instead of throwing.
DateTime? dateTimeFromJson(dynamic value) =>
    value is String ? DateTime.tryParse(value) : null;

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
