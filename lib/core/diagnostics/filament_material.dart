/// The one piece of card content the diagnostic log is allowed to carry — see
/// `docs/diagnostics-log.md` for why this exception is safe.
///
/// **The closed list is the whole safety argument**, and it is checked on both
/// sides because [join] is a call site anyone can add to while [split] is what
/// actually writes.
class FilamentMaterial {
  /// Not a dot: dots are the identifier's own grammar, and the summarising
  /// Action has to group by `inventory.spool` without knowing this vocabulary.
  static const separator = '@';

  /// Composites are listed in full rather than derived, so an unknown variant
  /// fails closed instead of being trimmed down to a base it may not be.
  static const known = {
    'PLA', 'PLA-CF', 'PLA-GF', 'PLA-AERO', 'PLA-S',
    'PETG', 'PETG-CF', 'PETG-GF', 'PET', 'PET-CF',
    'ABS', 'ABS-CF', 'ABS-GF',
    'ASA', 'ASA-CF', 'ASA-GF', 'ASA-AERO',
    'TPU', 'TPU-AMS',
    'PA', 'PA-CF', 'PA-GF', 'PA6-CF', 'PA6-GF', 'PAHT-CF',
    'PPA-CF', 'PPA-GF', 'PPS', 'PPS-CF',
    'PC', 'PC-CF', 'PC-FR',
    'PP', 'PP-CF', 'PP-GF',
    'PE', 'PE-CF',
    'PVA', 'PVB', 'HIPS', 'BVOH', 'EVA', 'PHA',
    'SUPPORT', 'SUPPORT-W', 'SUPPORT-G',
  };

  /// Null when [raw] is unknown. Case and spacing vary by source — the printer
  /// reports `Support W` — so both are normalised first.
  static String? canonical(String? raw) {
    if (raw == null) return null;
    final normalised =
        raw.trim().toUpperCase().replaceAll(RegExp(r'[\s_]+'), '-');
    return known.contains(normalised) ? normalised : null;
  }

  /// Identifier carrying [material], or the plain [id] when the material is
  /// unknown or absent.
  static String join(String id, String? material) {
    final mat = canonical(material);
    return mat == null ? id : '$id$separator$mat';
  }

  /// An unknown material is dropped while the identifier keeps its own part: a
  /// hand-built tag with the wrong value must not turn into a log field.
  static ({String id, String? material}) split(String identifier) {
    final at = identifier.indexOf(separator);
    if (at < 0) return (id: identifier, material: null);
    return (
      id: identifier.substring(0, at),
      material: canonical(identifier.substring(at + separator.length)),
    );
  }
}
