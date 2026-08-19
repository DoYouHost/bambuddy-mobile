/// From `…/plates`: the presets a 3MF names in its own
/// `Metadata/project_settings.config`, and whether this server can slice from it.
class EmbeddedSettings {
  const EmbeddedSettings({
    required this.printer,
    required this.process,
    required this.serverSupportsAsDesigned,
  });

  /// Verbatim preset name (`Bambu Lab X1 Carbon 0.4 nozzle`); null for an STL or
  /// a plain-model 3MF.
  final String? printer;

  final String? process;

  /// Whether `use_embedded_settings` does anything here. Observed, not
  /// versioned: it (#2611) and the `design_overrides` key (#2622) both landed
  /// mid-1.2.6, where every daily reports `1.2.6b1`. #2622 came second, so the
  /// key proves both; `embedded_printer` predates them and proves nothing.
  final bool serverSupportsAsDesigned;

  factory EmbeddedSettings.fromJson(Map<String, dynamic> json) =>
      EmbeddedSettings(
        printer: _nonEmpty(json['embedded_printer']),
        process: _nonEmpty(json['embedded_process']),
        // Presence, not contents: a design that changed nothing answers `[]`.
        serverSupportsAsDesigned: json.containsKey('design_overrides'),
      );

  static const none = EmbeddedSettings(
    printer: null,
    process: null,
    serverSupportsAsDesigned: false,
  );

  bool get isAvailable =>
      serverSupportsAsDesigned && printer != null && process != null;

  /// Whether [presetName] is the printer this design was prepared for — embedded
  /// settings lay the model out for their own bed and this path re-targets nothing.
  bool matchesPrinter(String? presetName) {
    if (!isAvailable || presetName == null) return false;
    return _normalise(presetName) == _normalise(printer!);
  }

  /// Both names come off the same preset namespace; `#` marks a modified preset.
  static String _normalise(String name) {
    final stripped = name.startsWith('#') ? name.substring(1) : name;
    return stripped.trim().toLowerCase();
  }

  static String? _nonEmpty(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
