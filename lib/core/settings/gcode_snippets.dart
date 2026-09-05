import 'server_settings.dart';

/// Which printer models have an auto-print G-code snippet configured on the
/// server (`AppSettings.gcode_snippets`).
///
/// The setting travels as a JSON **string**, keyed by `printer.model` exactly as
/// the printers report it: `{"A1 mini": {"start_gcode": "...", "end_gcode": ""}}`.
/// It is edited on the web (Settings → Workflow) and read here only to decide
/// whether the print form may offer `gcode_injection` at all — the web hides the
/// checkbox the same way, because the flag is a silent no-op without snippets.
///
/// A model counts as configured when at least one of its two snippets holds
/// something: the web deletes an entry once both are blanked, but a hand-written
/// setting (or an older build) can leave `{"X1C": {"start_gcode": ""}}` behind,
/// and offering injection for that would promise an empty injection.
///
/// Lenient by design — this gates a checkbox, so an unreadable setting means
/// "no snippets", never an exception on the print screen. Accepts an already
/// decoded map as well: [raw] is whatever `/settings` put under the key, and a
/// server sending an object instead of a string should not cost the feature.
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
