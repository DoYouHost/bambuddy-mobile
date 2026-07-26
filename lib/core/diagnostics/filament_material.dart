/// The one piece of card content the diagnostic log is allowed to carry.
///
/// Everything a card shows — model names, file names, spool names — is the
/// user's own text, and the log ends up in a public, permanent issue, so the
/// probe records identifiers and never labels. Material is the deliberate
/// exception: "PETG in slot 3" explains a real share of AMS reports, and a
/// material name out of a fixed list identifies nobody.
///
/// **The closed list is the whole safety argument.** A spool's `material` is
/// free text the user typed into the form, so a value this file does not
/// recognise is dropped rather than logged. That is checked twice — when the
/// tag is built and again when the probe splits it apart — because the tag side
/// is a call site anyone can add to, and the probe side is what actually
/// writes.
class FilamentMaterial {
  /// Separates the identifier from the material it is showing:
  /// `inventory.spool@PETG`. Not a dot: dots are the identifier's own grammar,
  /// and a reader (or the summarising Action) has to be able to group by
  /// `inventory.spool` without knowing this vocabulary.
  static const separator = '@';

  /// Materials that may be logged. Bambu tray types plus what the community
  /// slicer profiles use; composites are listed in full rather than derived,
  /// so an unknown variant fails closed instead of being trimmed down to a base
  /// it may not be.
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

  /// The material as it may appear in a log, or null when [raw] is not one we
  /// know. Case and spacing vary by source — the printer reports `Support W`,
  /// the inventory form whatever the user typed — so both are normalised before
  /// the lookup.
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

  /// Takes an identifier apart again. Anything after the separator that is not
  /// a known material is dropped, and the identifier keeps its own part — a tag
  /// built by hand with the wrong value must not turn into a log field.
  static ({String id, String? material}) split(String identifier) {
    final at = identifier.indexOf(separator);
    if (at < 0) return (id: identifier, material: null);
    return (
      id: identifier.substring(0, at),
      material: canonical(identifier.substring(at + separator.length)),
    );
  }
}
