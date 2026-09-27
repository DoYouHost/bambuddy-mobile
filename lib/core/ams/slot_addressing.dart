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

/// The inverse of [globalTrayId], for labelling a slot picked by its global id.
({int amsId, int trayId}) localSlotOf(int global) {
  final side = externalSideOf(global);
  if (side != null) return (amsId: externalHolderUnit, trayId: side);
  if (global >= amsHtUnitBase) return (amsId: global, trayId: 0);
  return (amsId: global ~/ 4, trayId: global % 4);
}
