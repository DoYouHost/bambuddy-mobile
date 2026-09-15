import 'server_settings.dart';

/// Which printer models have an auto-print G-code snippet configured on the
/// server (`AppSettings.gcode_snippets`).
///
/// The setting travels as a JSON **string**, keyed by `printer.model` exactly as
/// the printers report it: `{"A1 mini": {"start_gcode": "...", "end_gcode": ""}}`.
/// Read here only to decide whether the print form may offer `gcode_injection`,
/// which is a silent no-op without snippets.
///
/// Lenient by design — it gates a checkbox, so an unreadable setting means "no
/// snippets", never an exception on the print screen. [raw] is whatever
/// `/settings` put under the key, decoded or not.
Set<String> gcodeSnippetModels(Object? raw) {
  final decoded = decodeSettingBlob(raw);
  if (decoded == null) return const {};
  return {
    for (final e in decoded.entries)
      if (_hasSnippet(e.value)) e.key,
  };
}

bool _hasSnippet(Object? entry) {
  if (entry is! Map) return false;
  bool filled(Object? v) => v is String && v.trim().isNotEmpty;
  return filled(entry['start_gcode']) || filled(entry['end_gcode']);
}
