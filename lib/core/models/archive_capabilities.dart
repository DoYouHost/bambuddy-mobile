/// Archive viewing/slicing capabilities from
/// `GET /archives/{id}/capabilities`.
///
/// An archive can only be re-sliced when it still carries a parseable model
/// (`has_source` — the un-sliced project file the user sent) or an embedded
/// model (`has_model`). Plain `gcode.3mf` print outputs have neither and the
/// slicer rejects them with "input model file can not be parsed".
class ArchiveCapabilities {
  const ArchiveCapabilities({
    this.hasModel = false,
    this.hasGcode = false,
    this.hasSource = false,
  });

  factory ArchiveCapabilities.fromJson(Map<String, dynamic> json) =>
      ArchiveCapabilities(
        hasModel: json['has_model'] == true,
        hasGcode: json['has_gcode'] == true,
        hasSource: json['has_source'] == true,
      );

  final bool hasModel;
  final bool hasGcode;
  final bool hasSource;

  /// Whether the slice endpoint can actually produce output for this archive.
  bool get sliceable => hasSource || hasModel;
}
