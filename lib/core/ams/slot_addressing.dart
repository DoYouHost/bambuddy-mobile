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
/// printer calls the left nozzle extruder 1. Every conversion between these
/// columns belongs here — five sites used to spell one out inline, and the
/// Filament Track Switch bug was one of them being skipped.
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

/// Whether [amsId] names the external holder rather than an AMS unit.
bool isExternalHolder(int amsId) => amsId >= externalTrayIdBase;

/// Holder side (0 = Ext-L, 1 = Ext-R) for a global tray id, null for anything
/// that is not one of the two.
int? externalSideOf(int? global) {
  final side = global == null ? null : global - externalTrayIdBase;
  return (side == 0 || side == 1) ? side : null;
}

/// Global tray id of a holder side — the inverse of [externalSideOf].
int externalTrayIdOf(int side) => externalTrayIdBase + side;

/// The nozzle a holder side feeds: Ext-L is the left one, which the printer
/// numbers 1. Null for a side that is neither, rather than a guess.
int? extruderForExternalSide(int? side) =>
    (side == 0 || side == 1) ? 1 - side! : null;

/// The single number the firmware names a slot by — what `tray_now` reports,
/// what `ams_mapping` carries and what `POST /ams/load` takes.
///
/// Three encodings, mirroring `print_scheduler.py::_build_loaded_filaments` and
/// the `expected_tray` note in `schemas/printer.py`: the holder passes its side
/// through as 254/255, an **AMS-HT is its own unit id** (128–135, one tray
/// each), and every other AMS slot is `unit * 4 + slot`.
int globalTrayId({required int amsId, required int trayId}) {
  if (isExternalHolder(amsId)) return externalTrayIdBase + trayId;
  if (amsId >= amsHtUnitBase) return amsId;
  return amsId * 4 + trayId;
}

/// The local (unit, slot) pair behind a global number — the inverse of
/// [globalTrayId], for labelling a slot the user picked by its global id.
({int amsId, int trayId}) localSlotOf(int global) {
  final side = externalSideOf(global);
  if (side != null) return (amsId: externalHolderUnit, trayId: side);
  if (global >= amsHtUnitBase) return (amsId: global, trayId: 0);
  return (amsId: global ~/ 4, trayId: global % 4);
}
