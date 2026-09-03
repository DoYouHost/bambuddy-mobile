import 'dart:convert';

import '../models/json_utils.dart';

/// Recommended drying temperature and duration for one filament type, in both
/// module flavours: `n3f` is the regular AMS 2 Pro, `n3s` the high-temperature
/// AMS-HT. Picked apart by [AmsUnit.isHtDryModule].
typedef DryPreset = ({int temp, int htTemp, int hours, int htHours});

/// What the server uses when nobody has configured anything — the table
/// `services/print_scheduler.py::_get_drying_presets` falls back to (its
/// `DEFAULT_DRYING_PRESETS`), taken from BambuStudio's filament profiles.
///
/// Kept as a fallback rather than as the truth: it is what the drying sheet
/// offers before the server's settings have arrived, and on a session that may
/// not read them.
const defaultDryingPresets = <String, DryPreset>{
  'PLA': (temp: 45, htTemp: 45, hours: 12, htHours: 12),
  'PETG': (temp: 65, htTemp: 65, hours: 12, htHours: 12),
  'TPU': (temp: 65, htTemp: 75, hours: 12, htHours: 18),
  'ABS': (temp: 65, htTemp: 80, hours: 12, htHours: 8),
  'ASA': (temp: 65, htTemp: 80, hours: 12, htHours: 8),
  'PA': (temp: 65, htTemp: 85, hours: 12, htHours: 12),
  'PC': (temp: 65, htTemp: 80, hours: 12, htHours: 8),
  'PVA': (temp: 65, htTemp: 85, hours: 12, htHours: 18),
};

/// The table the server actually dries with, from the `drying_presets` setting.
///
/// The setting is a **JSON string**, not an object: the server stores it as a
/// blob (`AppSettings.drying_presets`, default `""`) and parses it in
/// `PrintScheduler._get_drying_presets`. Each row is
/// `{"n3f": °C, "n3s": °C, "n3f_hours": h, "n3s_hours": h}`.
///
/// **Replaces the table rather than merging into it**, which is what the server
/// does: a blob that parses to a non-empty object is used whole, and anything
/// else falls back to the built-in defaults. Merging would let the phone offer
/// a filament the server's own auto-drying has never heard of.
///
/// Never throws — this runs on a value a server handed us, and a malformed one
/// only costs the customisation, not the sheet.
Map<String, DryPreset> dryingPresetsFrom(dynamic value) {
  final decoded = _decode(value);
  if (decoded == null) return defaultDryingPresets;

  final presets = <String, DryPreset>{};
  for (final entry in decoded.entries) {
    final row = entry.value;
    if (row is! Map) continue;
    final record = asJsonRecord(row);
    // A row missing a field is not a row: reading a temperature and inventing
    // the duration would dry someone's spool for a made-up length of time.
    final temp = toIntOrNull(record['n3f']);
    final htTemp = toIntOrNull(record['n3s']);
    final hours = toIntOrNull(record['n3f_hours']);
    final htHours = toIntOrNull(record['n3s_hours']);
    if (temp == null || htTemp == null || hours == null || htHours == null) {
      continue;
    }
    presets[entry.key] = (
      temp: temp,
      htTemp: htTemp,
      hours: hours,
      htHours: htHours,
    );
  }
  // Every row was unusable, so the blob says nothing: the server would be
  // drying by its own defaults and the sheet should offer the same.
  return presets.isEmpty ? defaultDryingPresets : presets;
}

/// The blob as an object, or null when there is nothing usable in it.
///
/// A `Map` is accepted alongside the string because nothing stops a future
/// server from typing the field properly, and a client that only understood the
/// blob would then silently drop the customisation.
Map<String, dynamic>? _decode(dynamic value) {
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

/// Which of the server's own drying automations are switched on.
///
/// Read-only on purpose. Writing them is `settings:update`, which an API key
/// can never hold: the permission is absent from the key's scope allowlist and
/// named administrative in `core/auth.py::_APIKEY_DENIED_PERMISSIONS`, because
/// rewriting settings reaches the SMTP/LDAP/MQTT credentials. Nothing in the
/// app offers to change them; the sheet only says what is already happening, so
/// a drying cycle nobody started stops looking like a fault.
typedef AutoDrying = ({
  /// `queue_drying_enabled` — dry between queued prints.
  bool betweenPrints,

  /// `ambient_drying_enabled` — dry an idle printer over the humidity
  /// threshold, queue or no queue.
  bool whenIdle,

  /// `print_drying_enabled` — keep drying during a print, on hardware that
  /// supports it. A modifier on the two above rather than a mode of its own.
  bool whilePrinting,
});

const noAutoDrying =
    (betweenPrints: false, whenIdle: false, whilePrinting: false);

AutoDrying autoDryingFrom(Map<String, dynamic> settings) => (
      betweenPrints: toBoolOrFalse(settings['queue_drying_enabled']),
      whenIdle: toBoolOrFalse(settings['ambient_drying_enabled']),
      whilePrinting: toBoolOrFalse(settings['print_drying_enabled']),
    );
