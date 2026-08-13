/// Conversion between the settings screen's editing values and the string forms
/// OrcaSlicer writes into a process preset JSON.
///
/// The slicer CLI validates far more strictly than any GUI — `20` is not `20%`,
/// a bare `true` is not `"1"` — and the server does not refuse a badly typed
/// value, it drops the key with a log line (`services/process_overrides.py`), so
/// the print succeeds with one setting missing. Hence: serialise through the
/// option schema, never from the Dart type.
///
/// Ported from the server's `frontend/src/lib/slicerSettings.ts`, with one
/// deliberate deviation at [_stringify].
library;

import '../models/process_option.dart';

/// A value being edited: `String`, `num`, `bool`, or a `List` of those for the
/// per-extruder vector options.
typedef SettingValue = Object;

/// Leading numeric prefix, matching JavaScript's `parseFloat` — the bounds this
/// runs on were written for it.
final _leadingNumber =
    RegExp(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?');

/// Renders one scalar the way a process preset stores it.
///
/// Booleans become `1`/`0` everywhere — the deviation. Upstream renders a scalar
/// bool as `1` but one *inside a vector* as `true`; that reaches only the two
/// `coBools` options, and the server states the spelling outright ("a process
/// JSON spells booleans "1"/"0", never "True"/"False"",
/// `services/process_overrides.py`), so the inconsistency reads as an oversight.
String _stringify(Object? value) {
  if (value == null) return '';
  if (value is bool) return value ? '1' : '0';
  if (value is double) return _doubleToString(value);
  return value.toString();
}

/// `2.0` renders as `2`. Dart keeps the trailing `.0` where JavaScript drops it,
/// and a server reporting `2.0` for a field showing `2` would otherwise mark the
/// row as user-modified and send back a value nobody typed.
String _doubleToString(double value) {
  if (!value.isFinite) return value.toString();
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  return value.toString();
}

/// A numeric bound for an input, or null when the schema's entry is not one —
/// `standby_temperature_delta` is bounded by `-max_temp`/`max_temp`, and a NaN
/// reaching a field's min/max makes it unfillable.
double? numericBound(Object? bound) {
  if (bound is num) return bound.isFinite ? bound.toDouble() : null;
  if (bound is! String) return null;
  final match = _leadingNumber.firstMatch(bound.trim());
  if (match == null) return null;
  var text = match[0]!;
  // C++ literal artefacts the generator left in a few entries: `0.` and `.5`
  // are numbers to parseFloat but not to Dart.
  if (text.endsWith('.')) text = '${text}0';
  text = text.replaceFirstMapped(RegExp(r'^([+-]?)\.'), (m) => '${m[1]}0.');
  return double.tryParse(text);
}

/// The unit to show after a field. Null for the few entries carrying an
/// unresolved C++ reference — `def_x->sidetext` on screen is worse than no unit.
String? displaySidetext(ProcessOption option) {
  final text = option.sidetext;
  if (text == null || text.trim().isEmpty) return null;
  if (text.contains('->') || text.contains('::')) return null;
  return text;
}

/// What an untouched field shows: the preset's own value when the server could
/// report one, else the compiled-in default. `line_width` is 0 in OrcaSlicer's
/// C++ ("derive from the nozzle") and 0.42 in any real preset, so the difference
/// is user-visible.
String baselineForDisplay(ProcessOption option, [Object? presetValue]) {
  final baseline = presetValue ?? option.defaultValue;
  if (baseline == null) return '';
  if (baseline is List) return baseline.map(_stringify).join(', ');
  return _stringify(baseline);
}

/// Serialises one edited value into its process-JSON form: a `String`, or a
/// `List<String>` for the per-extruder vector options, which the config stores
/// as arrays.
Object serializeSetting(ProcessOption option, SettingValue value) {
  if (option.type.isVector) {
    final parts = value is List
        ? value.map(_stringify)
        : _stringify(value).split(',');
    return [
      for (final part in parts)
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }

  if (option.type == OptionType.coBool) {
    if (value is bool) return value ? '1' : '0';
    // A control may hand back the string form it was seeded with.
    return (value == '1' || value == 'true' || value == 1) ? '1' : '0';
  }

  final raw = _stringify(value).trim();
  // The config spells percents with the sign; the field edits the bare number.
  if (option.type == OptionType.coPercent) {
    return raw.endsWith('%') ? raw : '$raw%';
  }
  return raw;
}

/// Whether [value] differs from the baseline this slice would otherwise use —
/// the "modified" marker, and the test for what is worth sending at all.
///
/// The baseline is the preset's value when known. Comparing against the schema
/// default would flag every field the preset moved off the C++ default as
/// user-changed.
bool isModified(ProcessOption option, Object? value, [Object? presetValue]) {
  if (value == null || value == '') return false;

  // Both sides through the same serialiser, so `20` and `20%` compare equal.
  String flatten(Object v) {
    final serialized =
        serializeSetting(option, v is List ? v.map(_stringify).join(', ') : v);
    return serialized is List ? serialized.join(', ') : serialized as String;
  }

  final asString = flatten(value);
  final baseline = presetValue ?? option.defaultValue;
  if (baseline == null) return asString.isNotEmpty;
  return asString != flatten(baseline);
}

/// The `process_overrides` map for a slice request: only the options the user
/// actually moved, each serialised through its schema entry.
///
/// An untouched screen yields an empty map, which the caller then drops from the
/// request — that is what keeps a slice with this feature unused identical to one
/// from before it existed. A key with no schema entry is skipped rather than sent
/// raw; the server would drop it with nothing pointing back here.
Map<String, Object> buildProcessOverrides({
  required Map<String, SettingValue> values,
  required Map<String, ProcessOption> schema,
  Map<String, dynamic> presetValues = const {},
}) {
  final out = <String, Object>{};
  for (final entry in values.entries) {
    final option = schema[entry.key];
    if (option == null) continue;
    if (!isModified(option, entry.value, presetValues[entry.key])) continue;
    out[entry.key] = serializeSetting(option, entry.value);
  }
  return out;
}
