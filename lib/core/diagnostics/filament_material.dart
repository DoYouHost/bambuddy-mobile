import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/widgets.dart';
export 'package:app_diagnostics/app_diagnostics.dart' show logTag, LogTagged;

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
    'PLA',
    'PLA-CF',
    'PLA-GF',
    'PLA-AERO',
    'PLA-S',
    'PETG',
    'PETG-CF',
    'PETG-GF',
    'PET',
    'PET-CF',
    'ABS',
    'ABS-CF',
    'ABS-GF',
    'ASA',
    'ASA-CF',
    'ASA-GF',
    'ASA-AERO',
    'TPU',
    'TPU-AMS',
    'PA',
    'PA-CF',
    'PA-GF',
    'PA6-CF',
    'PA6-GF',
    'PAHT-CF',
    'PPA-CF',
    'PPA-GF',
    'PPS',
    'PPS-CF',
    'PC',
    'PC-CF',
    'PC-FR',
    'PP',
    'PP-CF',
    'PP-GF',
    'PE',
    'PE-CF',
    'PVA',
    'PVB',
    'HIPS',
    'BVOH',
    'EVA',
    'PHA',
    'SUPPORT',
    'SUPPORT-W',
    'SUPPORT-G',
  };

  /// Null when [raw] is unknown. Case and spacing vary by source — the printer
  /// reports `Support W` — so both are normalised first.
  static String? canonical(String? raw) {
    if (raw == null) return null;
    final normalised = raw.trim().toUpperCase().replaceAll(
      RegExp(r'[\s_]+'),
      '-',
    );
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

/// Names a control and the filament material it shows — the one exception to
/// the rule that the log carries identifiers and never content.
///
/// The material rides *inside* the identifier because semantics is the only
/// channel the probe has, and `InteractionProbe.decompose` splits it back out.
/// Why that is safe: `FilamentMaterial`'s closed list, and
/// `docs/diagnostics-log.md`.
Widget logTagMaterial(String id, String? material, Widget child) =>
    logTag(FilamentMaterial.join(id, material), child);

extension LogTaggedMaterial on Widget {
  Widget taggedMaterial(String id, String? material) =>
      logTagMaterial(id, material, this);
}
