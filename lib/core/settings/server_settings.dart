import 'dart:convert';

import 'package:app_util/app_util.dart';

/// Reading the server's `AppSettings` map. `_build_settings_response` types
/// every field today, so the readers only disagree on a string `"true"` — one
/// reader is what keeps that from mattering the day something sends one.
extension ServerSettings on Map<String, dynamic> {
  /// A flag. Absent or null → [fallback]; anything else is coerced, so an
  /// unreadable value is `false` — a flag has a natural off, where a threshold
  /// has no natural zero and keeps falling back.
  bool settingBool(String key, {bool fallback = false}) {
    final value = this[key];
    return value == null ? fallback : toBoolOrFalse(value);
  }

  /// A number the server may send as a string. Absent, null or unreadable →
  /// [fallback].
  double settingDouble(String key, double fallback) =>
      toDoubleOrNull(this[key]) ?? fallback;

  /// A non-empty string, or null.
  String? settingString(String key) => toStringOrNull(this[key]);

  /// A field that holds **JSON inside a string** — how bambuddy stores the maps
  /// that have no schema of their own (`gcode_snippets`, `drying_presets`,
  /// `ams_humidity_thresholds`). Empty means "nothing configured", which every
  /// caller reads as its own defaults.
  Map<String, dynamic>? settingBlob(String key) => decodeSettingBlob(this[key]);
}

/// [ServerSettings.settingBlob] for a value already pulled out of the map, and
/// an object as readily as the string: a future server typing one of these
/// fields properly must not cost a client the configuration.
///
/// Goes through [asJsonRecord] rather than testing for `Map<String, dynamic>`,
/// which dropped a map relayed over a platform channel as `Map<Object?,
/// Object?>`. Never throws.
Map<String, dynamic>? decodeSettingBlob(dynamic value) {
  if (value is Map) {
    final record = asJsonRecord(value);
    return record.isEmpty ? null : record;
  }
  if (value is! String || value.trim().isEmpty) return null;
  try {
    final parsed = jsonDecode(value);
    if (parsed is! Map) return null;
    final record = asJsonRecord(parsed);
    return record.isEmpty ? null : record;
  } on FormatException {
    return null;
  }
}
