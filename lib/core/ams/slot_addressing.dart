/// The three numberings one filament slot answers to, in one place.
///
/// A slot is *local* to its unit — an AMS id plus a slot within it — on every
/// route that takes ids in the path (`/slots/{ams}/{tray}/configure`, the RFID
/// re-read, the inventory assignment). The firmware, `tray_now` and every
/// `ams_mapping` instead use a single **global** number, and the external spool
/// holder gets a third numbering on top of that:
///
/// | holder side | local (unit, tray) | global id | extruder  |
/// |-------------|--------------------|-----------|-----------|
/// | Ext-L       | 255, 0             | 254       | 1 (left)  |
/// | Ext-R       | 255, 1             | 255       | 0 (right) |
///
/// The inversion in the last column is not a typo and not derivable: it was
/// verified on a live X2D, where the 254 spool sits physically left and the
/// printer calls the left nozzle extruder 1.
library;

/// Unit id the external holder answers to where ids are local. The inventory
/// backend has been seen using 254 for the same thing, so anything at or above
/// [externalTrayIdBase] counts as the holder — see [isExternalHolder].
const externalHolderUnit = 255;

/// Global id of Ext-L; Ext-R is one above it.
const externalTrayIdBase = 254;

/// First unit id of an AMS-HT. Those units are numbered from here and hold one
/// tray each, which is why they cannot fit the `unit * 4 + slot` encoding.
const amsHtUnitBase = 128;

bool isExternalHolder(int amsId) => amsId >= externalTrayIdBase;

/// Holder side (0 = Ext-L, 1 = Ext-R) for a global tray id.
int? externalSideOf(int? global) {
  final side = global == null ? null : global - externalTrayIdBase;
  return (side == 0 || side == 1) ? side : null;
}

int externalTrayIdOf(int side) => externalTrayIdBase + side;

int? extruderForExternalSide(int? side) =>
    (side == 0 || side == 1) ? 1 - side! : null;

/// The single number the firmware names a slot by — what `tray_now` reports,
/// what `ams_mapping` carries and what `POST /ams/load` takes. Three encodings,
/// mirroring `print_scheduler.py::_build_loaded_filaments` and the
/// `expected_tray` note in `schemas/printer.py`.
int globalTrayId({required int amsId, required int trayId}) {
  if (isExternalHolder(amsId)) return externalTrayIdBase + trayId;
  if (amsId >= amsHtUnitBase) return amsId;
  return amsId * 4 + trayId;
}

/// Unit id the backend gives an A2L's AMS Lite (its physical 16, normalised at
/// ingest). No regular AMS uses it.
const amsLiteUnit = 6;

/// The unit's name as the web names it (`amsHelpers.ts::getAmsLabel`): AMS-A,
/// AMS-B… by unit id, HT-A… for an AMS-HT. Product names, so not localised;
/// the external holder is the caller's to name.
String amsUnitName(int amsId) {
  assert(!isExternalHolder(amsId), 'the external holder has no unit name');
  if (amsId == amsLiteUnit) return 'AMS Lite';
  final ht = amsId >= amsHtUnitBase;
  final letter = String.fromCharCode(
    0x41 + (ht ? amsId - amsHtUnitBase : amsId),
  );
  return ht ? 'HT-$letter' : 'AMS-$letter';
}

/// "AMS-A · 2". An AMS-HT holds a single tray, so its unit name is the whole
/// label. [unit] overrides the generated name with the user's own.
String amsSlotName(int amsId, int trayId, {String? unit}) {
  unit ??= amsUnitName(amsId);
  return amsId >= amsHtUnitBase ? unit : '$unit · ${trayId + 1}';
}

/// `formatSlotLabel`, the slot names of the web's mapping dialog: `A1` for
/// AMS A slot 1, `HT-A` for an AMS-HT. The external holder is the caller's
/// to name (`Ext-L`/`Ext-R`/`External`).
String formatSlotLabel(int amsId, int trayId, {required bool isHt}) {
  final letter = String.fromCharCode(
    0x41 + (amsId >= amsHtUnitBase ? amsId - amsHtUnitBase : amsId),
  );
  return isHt ? 'HT-$letter' : '$letter${trayId + 1}';
}

/// The tag bambuddy links a spool without RFID to a slot by, in Spoolman's
/// `extra.tag`: a 32-bit FNV-1a of the serial, then the unit and the tray as
/// four hex digits each. Byte for byte `amsHelpers.ts::getFallbackSpoolTag`
/// and `spoolman_tracking.py::get_fallback_spool_tag_for_slot`, which must
/// agree for the web to find the spool. Null without a serial, as the server.
String? fallbackSpoolTag(String? serial, int amsId, int trayId) {
  final input = (serial ?? '').trim().toUpperCase();
  if (input.isEmpty) return null;
  var hash = 0x811c9dc5;
  for (final unit in input.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  String hex(int value, int width) =>
      value.toRadixString(16).toUpperCase().padLeft(width, '0');
  return '${hex(hash, 8)}${hex(amsId, 4)}${hex(trayId, 4)}';
}

/// The inverse of [globalTrayId], for labelling a slot picked by its global id.
({int amsId, int trayId}) localSlotOf(int global) {
  final side = externalSideOf(global);
  if (side != null) return (amsId: externalHolderUnit, trayId: side);
  if (global >= amsHtUnitBase) return (amsId: global, trayId: 0);
  return (amsId: global ~/ 4, trayId: global % 4);
}
