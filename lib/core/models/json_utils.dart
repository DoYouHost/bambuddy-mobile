// Shared tolerant JSON coercion helpers for `@JsonKey(fromJson: ...)`.
//
// Call-sites across the data layer wrap per-item list parsing in
// catch-and-skip (`if (item is! Map) continue;` / `on Object { continue; }`)
// so one malformed server record only drops that one entry instead of the
// whole response. The plain generated casts (`e as Map<String, dynamic>`,
// `DateTime.parse(x as String)`) don't have that tolerance built in — a bad
// element throws straight through `fromJson`, past that per-item guard,
// silently discarding the entire parent list/record instead of just the
// one bad leaf.

/// Tolerant `DateTime?` parse: malformed or non-string timestamps yield
/// `null` instead of throwing.
DateTime? dateTimeFromJson(dynamic value) =>
    value is String ? DateTime.tryParse(value) : null;

/// Tolerant list parse: skips elements that aren't the expected shape
/// instead of throwing and losing the whole list.
List<T> parseJsonList<T>(
  dynamic value,
  T Function(Map<String, dynamic>) fromJson,
) {
  if (value is! List) return const [];
  final out = <T>[];
  for (final item in value) {
    if (item is Map<String, dynamic>) out.add(fromJson(item));
  }
  return out;
}
