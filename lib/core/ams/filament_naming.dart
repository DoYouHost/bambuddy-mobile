/// Everything the AMS slot configuration has to read out of a preset's *name*.
///
/// The server computes none of it: `POST /slots/{ams}/{tray}/configure` takes a
/// material, a sub-brand, a filament id and a temperature range, and expects the
/// caller to have derived all four. Bambu's presets carry that information only
/// as text ("Bambu PLA Basic @BBL X1C"), so the parsing below is the whole
/// contract — ported from the web's `ConfigureAmsSlotModal`.
library;

/// Materials recognised inside a preset name, longest-prefix-first where two
/// could collide (`PETG` before `PET`, `PCTG` before `PC`). Order is load-
/// bearing: the first match in this list wins.
const filamentMaterials = <String>[
  'PLA',
  'PETG',
  'PCTG',
  'ABS',
  'ASA',
  'TPU',
  'PC',
  'PA',
  'NYLON',
  'PVA',
  'HIPS',
  'PP',
  'PET',
];

/// A preset name broken into the parts the configure call needs.
typedef ParsedPresetName = ({String material, String brand, String variant});

/// Strip the `@…` printer/nozzle suffix a slicer preset name ends with.
String presetNameWithoutPrinter(String name) =>
    name.replaceFirst(RegExp(r'@.+$'), '').trim();

/// Split a preset name into material, brand and variant.
///
/// The one shape worth naming is "X Support for Y": the filament is Y, not X,
/// so "PLA Support for PETG" is a PETG filament. Matching materials in list
/// order would call it PLA and send the printer a 190–230 °C range for a
/// material that needs 220–260.
ParsedPresetName parsePresetName(String name) {
  final withoutSuffix = presetNameWithoutPrinter(name);
  final upper = withoutSuffix.toUpperCase();

  final support = RegExp(r'\bSUPPORT\s+FOR\s+').firstMatch(upper);
  if (support != null) {
    final after = upper.substring(support.end);
    for (final material in filamentMaterials) {
      if (RegExp('\\b$material\\b').hasMatch(after)) {
        return (
          material: material,
          brand: withoutSuffix.substring(0, support.start).trim(),
          variant: 'Support',
        );
      }
    }
  }

  for (final material in filamentMaterials) {
    final pattern = RegExp('\\b$material\\b', caseSensitive: false);
    final match = pattern.firstMatch(upper);
    if (match == null) continue;
    // Split around the *first* occurrence only. Splitting on every one drops
    // the text between later repeats — "PETG eSUN PETG Basic" would lose
    // "Basic" — and the indices carry over from the upper-cased copy because
    // upper-casing does not change the length.
    return (
      material: material,
      brand: withoutSuffix.substring(0, match.start).trim(),
      variant: withoutSuffix.substring(match.end).trim(),
    );
  }

  // Nothing known in the name — assume the slicer's "<brand> <material> …"
  // convention rather than giving up, so an unknown material still reaches the
  // printer under its own name.
  final words = withoutSuffix.split(RegExp(r'\s+'));
  if (words.length >= 2) {
    return (
      material: words[1],
      brand: words.first,
      variant: words.skip(2).join(' '),
    );
  }
  return (material: withoutSuffix, brand: '', variant: '');
}

/// The filament id behind a cloud preset's `setting_id`.
///
/// Bambu's own presets differ by one letter — `GFSL05` is the setting, `GFL05`
/// the filament — and both carry a `_NN` version suffix the printer does not
/// want. A user preset (`PFUS…`, `PFSP…`) shares its base id with its filament,
/// so only the suffix comes off.
String filamentIdFromSettingId(String settingId) {
  final baseId = settingId.split('_').first;
  if (baseId.startsWith('GFS')) return 'GF${baseId.substring(3)}';
  return baseId;
}

/// Bambu's generic filament for a material, for presets that carry no Bambu id
/// of their own (everything imported from a slicer bundle).
///
/// The printer needs *something* here to recognise the material at all — drying,
/// HMS and colour matching all key off it — and the closest generic is the
/// honest answer. Empty when the material is not one Bambu has a generic for.
const genericFilamentIds = <String, String>{
  'PLA': 'GFL99',
  'PLA-CF': 'GFL98',
  'PLA SILK': 'GFL96',
  'PLA HIGH SPEED': 'GFL95',
  'PETG': 'GFG99',
  'PETG HF': 'GFG96',
  'PETG-CF': 'GFG98',
  'PCTG': 'GFG97',
  'ABS': 'GFB99',
  'ASA': 'GFB98',
  'PC': 'GFC99',
  'PA': 'GFN99',
  'PA-CF': 'GFN98',
  'NYLON': 'GFN99',
  'TPU': 'GFU99',
  'PVA': 'GFS99',
  'HIPS': 'GFS98',
  'PE': 'GFP99',
  'PP': 'GFP97',
};

/// [genericFilamentIds] for [material], retried against progressively plainer
/// forms of it — "PLA-CF+" is not in the table but "PLA" is, and a slot set to
/// generic PLA beats a slot the printer refuses to classify at all.
String genericFilamentId(String material) {
  final key = material.toUpperCase().trim();
  return genericFilamentIds[key] ??
      genericFilamentIds[key.replaceFirst(RegExp(r'[-\s]?CF$'), '')] ??
      genericFilamentIds[key.replaceFirst(RegExp(r'\+$'), '')] ??
      genericFilamentIds[key.split(RegExp(r'[-\s]')).first] ??
      '';
}

/// Nozzle temperature range for a material, in °C.
///
/// `nozzle_temp_min`/`max` are required by the configure call and nothing on
/// either side supplies them, so this table is the only source. Substring
/// matching on purpose: "PLA Silk" and "PLA-CF" print at PLA temperatures.
({int min, int max}) nozzleTemperaturesFor(String material) {
  final m = material.toUpperCase();
  if (m.contains('PLA')) return (min: 190, max: 230);
  if (m.contains('PETG')) return (min: 220, max: 260);
  if (m.contains('ABS')) return (min: 240, max: 280);
  if (m.contains('ASA')) return (min: 240, max: 280);
  if (m.contains('TPU')) return (min: 200, max: 240);
  // Before the PC rule, which "PCTG" would otherwise satisfy at 40 °C too hot.
  if (m == 'PCTG') return (min: 220, max: 260);
  if (m.contains('PC')) return (min: 260, max: 300);
  if (m.contains('PA') || m.contains('NYLON')) return (min: 250, max: 290);
  return (min: 190, max: 230);
}
