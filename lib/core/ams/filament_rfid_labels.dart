/// Bambu RFID filament identifiers (`tray_info_idx`) and the short material
/// names used by the compact AMS tiles. The official Bambu Studio table is the
/// source for Bambu spools; generic identifiers below are the firmware's
/// fallback names for non-RFID or manually configured material.
library;

const _bambuFilamentLabels = <String, String>{
  'GFA00': 'PLA Basic',
  'GFA01': 'PLA Matte',
  'GFA02': 'PLA Metal',
  'GFA05': 'PLA Silk',
  'GFA06': 'PLA Silk+',
  'GFA07': 'PLA Marble',
  'GFA08': 'PLA Sparkle',
  'GFA09': 'PLA Tough',
  'GFA10': 'PLA Tough+',
  'GFA11': 'PLA Aero',
  'GFA12': 'PLA Glow',
  'GFA13': 'PLA Dynamic',
  'GFA15': 'PLA Galaxy',
  'GFA16': 'PLA Wood',
  'GFA17': 'PLA Translucent',
  'GFA18': 'PLA Lite',
  'GFA19': 'PLA Pure',
  'GFA20': 'PLA Palette',
  'GFA50': 'PLA-CF',
  'GFB00': 'ABS',
  'GFB01': 'ASA',
  'GFB02': 'ASA Aero',
  'GFB50': 'ABS-GF',
  'GFB51': 'ASA-CF',
  'GFC00': 'PC',
  'GFC01': 'PC FR',
  'GFG00': 'PETG Basic',
  'GFG01': 'PETG Translucent',
  'GFG02': 'PETG HF',
  'GFG03': 'PETG Matte',
  'GFG50': 'PETG-CF',
  'GFN04': 'PAHT-CF',
  'GFN05': 'PA6-CF',
  'GFN06': 'PPA-CF',
  'GFN08': 'PA6-GF',
  'GFS02': 'Support for PLA',
  'GFS03': 'Support for PA/PET',
  'GFS04': 'PVA',
  'GFS05': 'Support for PLA/PETG',
  'GFS06': 'Support for ABS',
  'GFT01': 'PET-CF',
  'GFT02': 'PPS-CF',
  'GFU00': 'TPU 95A HF',
  'GFU01': 'TPU 95A',
  'GFU02': 'TPU for AMS',
  'GFU03': 'TPU 90A',
  'GFU04': 'TPU 85A',
  'GFU06': 'TPU 75A (2.85mm)',
};

const _genericFilamentLabels = <String, String>{
  'GFL98': 'Generic PLA-CF',
  'GFL99': 'Generic PLA',
  'GFG99': 'Generic PETG',
  'GFC99': 'Generic PC',
  'GFN98': 'Generic PA-CF',
  'GFN99': 'Generic PA',
  'GFB98': 'Generic ASA',
  'GFB99': 'Generic ABS',
  'GFU99': 'Generic TPU',
  'GFS99': 'Generic PVA',
};

/// Returns the short material name for a Bambu RFID identifier, or null when
/// the identifier is absent/unknown.
String? filamentLabelFromRfid(String? rfid) {
  final id = rfid?.trim();
  if (id == null || id.isEmpty) return null;
  return _bambuFilamentLabels[id] ?? _genericFilamentLabels[id];
}
