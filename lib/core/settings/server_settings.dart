import 'dart:convert';

import '../models/json_utils.dart';

/// Reading the server's `AppSettings` map, which four features were each doing
/// their own way.
///
/// Two of them compared `== true`, one coerced, one had a private
/// `double read(key, fallback)`. They disagree on exactly one input — the
/// string `"true"`, which `== true` reads as false — and today nothing sends
/// it, because `_build_settings_response` types every field. The point of one
/// reader is that the disagreement cannot come back the day something does.
extension ServerSettings on Map<String, dynamic> {
  /// A flag. Absent, unreadable, or anything falsy → [fallback].
  bool settingBool(String key, {bool fallback = false}) =>
      containsKey(key) ? toBoolOrFalse(this[key]) : fallback;

  /// A number the server may send as a string.
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

/// [ServerSettings.settingBlob] for a value already pulled out of the map.
///
/// Accepts an object as well as the string, because nothing stops a future
/// server from typing one of these fields properly and a client that only
/// understood the blob would then silently drop the configuration.
///
/// Goes through [asJsonRecord] rather than testing for `Map<String, dynamic>`:
/// a map that did not come straight out of `jsonDecode` — one relayed over a
/// platform channel, typed `Map<Object?, Object?>` — is an object all the same,
/// and the stricter test dropped it.
///
/// Never throws; a malformed blob costs the configuration, not the screen.
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
