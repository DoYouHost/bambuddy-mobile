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
///
/// A rack printer (the H3C) has nine external inputs instead, 247-255, input
/// `v` feeding hotend `255 - v`, and its AMS 3H numbers its slots 28-36. The
/// port of `utils/trayIds.ts` (server `utils/tray_ids.py`) is [unitAmsType]
/// and [TrayLayout].
library;

/// Bambu Studio's AMS type (`DevAmsType`), the server's `ams_type`.
abstract final class AmsType {
  static const ams = 1;
  static const amsLite = 2;
  static const n3f = 3; // AMS 2 Pro
  static const n3s = 4; // AMS-HT
  static const amsLiteMixed = 5; // the A2L's AMS Lite
  static const zmultiA = 6; // AMS 3H
  static const zmultiB = 7; // AMS-B
}

/// One rack AMS slot per hotend of the H3C's rack.
const rackSlotCount = 9;

/// The H3C reports its AMS 3H as this unit; read only when `ams_type` is not.
const ams3hUnit = 32;

const _rackTrayBase = {AmsType.zmultiA: 28, AmsType.zmultiB: 37};
const _amsLiteMixedTrayBase = 24;

/// First external input of a rack printer; 247-253 feed hotends 8-2.
const rackExternalFirst = 247;

bool isRackAms(int type) => _rackTrayBase.containsKey(type);

bool isAmsHtId(int amsId) => amsId >= amsHtUnitBase && amsId <= 135;

/// Unit [amsId]'s AMS type: [explicit] when the server sent one, else from the
/// id (128+ AMS-HT, [ams3hUnit] AMS 3H, anything else a regular AMS).
int unitAmsType(int amsId, [int? explicit]) {
  if (isAmsHtId(amsId)) return AmsType.n3s;
  if (explicit != null && explicit > 0 && explicit <= AmsType.zmultiB) {
    return explicit;
  }
  if (amsId >= amsHtUnitBase) return AmsType.n3s;
  if (amsId == ams3hUnit) return AmsType.zmultiA;
  return AmsType.ams;
}

/// A global id that names an external input: 254/255, and on a [rack] printer
/// also 247-253.
bool isExternalTray(int? global, {bool rack = false}) {
  if (global == externalTrayIdBase || global == externalTrayIdBase + 1) {
    return true;
  }
  return rack && global != null && global >= rackExternalFirst && global < 256;
}

/// The hotend (0-8) a rack printer's external input [global] feeds.
int externalHotend(int global) => 255 - global;

/// The tray id an external input is stored under: 254 -> 0, 255 -> 1,
/// 247-253 -> 2-8.
int externalSlotIndex(int global) => global >= externalTrayIdBase
    ? global - externalTrayIdBase
    : global - rackExternalFirst + 2;

/// The inverse of [externalSlotIndex].
int externalTrayId(int slotIndex) => slotIndex < 2
    ? externalTrayIdBase + slotIndex
    : rackExternalFirst + slotIndex - 2;

/// A rack printer's external input as Bambu Studio names it: "Ext-n" feeds
/// hotend n.
String rackExternalLabel(int global) => 'Ext-${externalHotend(global) + 1}';

/// How one printer numbers its trays: its units' types, and whether it is a
/// rack printer — it has a rack AMS or reports an external input 247-253
/// (`trayLayoutOf`).
class TrayLayout {
  TrayLayout.of(
    Iterable<({int id, int? amsType})> units, [
    Iterable<int?> externalIds = const [],
  ]) : units = {for (final u in units) u.id: unitAmsType(u.id, u.amsType)} {
    rack =
        this.units.values.any(isRackAms) ||
        externalIds.any(
          (id) =>
              id != null && id >= rackExternalFirst && id < externalTrayIdBase,
        );
  }

  /// Unit id → AMS type.
  final Map<int, int> units;
  late final bool rack;

  int amsTypeOf(int amsId) => units[amsId] ?? unitAmsType(amsId);

  int globalTrayIdOf(int amsId, int trayId) =>
      globalTrayId(amsId: amsId, trayId: trayId, amsType: amsTypeOf(amsId));

  /// `locateTray`: the (unit, slot) an AMS slot's global id is stored under,
  /// null for an external input or no tray. Unless a rack AMS or a unit 7 is
  /// listed, 28-36 are the AMS 3H's, as in Bambu Studio.
  ({int amsId, int trayId})? locate(int global) {
    if (global < 0 || isExternalTray(global, rack: true)) return null;
    if (global >= amsHtUnitBase) return (amsId: global, trayId: 0);
    final racks = units.entries.where((e) => isRackAms(e.value)).toList();
    for (final MapEntry(key: id, value: type) in racks) {
      final base = _rackTrayBase[type]!;
      if (global >= base && global < base + rackSlotCount) {
        return (amsId: id, trayId: global - base);
      }
    }
    final ams3hBase = _rackTrayBase[AmsType.zmultiA]!;
    if (racks.isEmpty &&
        !units.containsKey(7) &&
        global >= ams3hBase &&
        global < ams3hBase + rackSlotCount) {
      return (amsId: ams3hUnit, trayId: global - ams3hBase);
    }
    return (amsId: global ~/ 4, trayId: global % 4);
  }
}

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
/// what `ams_mapping` carries and what `POST /ams/load` takes
/// (`utils/tray_ids.py::global_tray_id`). [amsType] is the unit's `ams_type`;
/// without it the id decides ([unitAmsType]).
int globalTrayId({required int amsId, required int trayId, int? amsType}) {
  if (isExternalHolder(amsId)) return externalTrayId(trayId);
  final kind = unitAmsType(amsId, amsType);
  if (kind == AmsType.n3s) return amsId;
  if (kind == AmsType.amsLiteMixed) return _amsLiteMixedTrayBase + trayId;
  final rackBase = _rackTrayBase[kind];
  if (rackBase != null) return rackBase + trayId;
  return amsId * 4 + trayId;
}

/// The slot (local tray id) of the tray at [position] in a unit's report, given
/// the ids of all its trays: `amsHelpers.ts::trayForSlot` read the other way.
/// An AMS can report only some of its trays, so a position is not the slot;
/// only when the ids do not tell the trays apart (a firmware that sends none,
/// so they all read 0 or nothing) does the position decide.
int slotOfTray(List<int?> trayIds, int position) {
  final ids = trayIds.toSet();
  final usable = !ids.contains(null) && ids.length == trayIds.length;
  return usable ? trayIds[position]! : position;
}

/// Unit id the backend gives an A2L's AMS Lite (its physical 16, normalised at
/// ingest). No regular AMS uses it.
const amsLiteUnit = 6;

/// The unit's name as the web names it (`amsHelpers.ts::getAmsLabel`): AMS-A,
/// AMS-B… by unit id, HT-A… for an AMS-HT, AMS 3H for the H3C's. Product
/// names, so not localised; the external holder is the caller's to name.
String amsUnitName(int amsId, {int? amsType}) {
  assert(!isExternalHolder(amsId), 'the external holder has no unit name');
  if (amsId == amsLiteUnit) return 'AMS Lite';
  if (unitAmsType(amsId, amsType) == AmsType.zmultiA) return 'AMS 3H';
  final ht = amsId >= amsHtUnitBase;
  final letter = String.fromCharCode(
    0x41 + (ht ? amsId - amsHtUnitBase : amsId),
  );
  return ht ? 'HT-$letter' : 'AMS-$letter';
}

/// "AMS-A · 2". An AMS-HT holds a single tray, so its unit name is the whole
/// label. [unit] overrides the generated name with the user's own.
String amsSlotName(int amsId, int trayId, {String? unit, int? amsType}) {
  unit ??= amsUnitName(amsId, amsType: amsType);
  return amsId >= amsHtUnitBase ? unit : '$unit · ${trayId + 1}';
}

/// `formatSlotLabel`, the slot names of the web's mapping dialog: `A1` for
/// AMS A slot 1, `HT-A` for an AMS-HT, `3H-7` for the AMS 3H. The external
/// holder is the caller's to name (`Ext-L`/`Ext-R`/`External`).
String formatSlotLabel(
  int amsId,
  int trayId, {
  required bool isHt,
  int? amsType,
}) {
  if (!isHt && unitAmsType(amsId, amsType) == AmsType.zmultiA) {
    return '3H-${trayId + 1}';
  }
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

/// The inverse of [globalTrayId], for labelling a slot picked by its global id
/// (`TrayLayout.slot_key`): 247-255 are only ever external inputs.
({int amsId, int trayId}) localSlotOf(int global, [TrayLayout? layout]) {
  if (isExternalTray(global, rack: true)) {
    return (amsId: externalHolderUnit, trayId: externalSlotIndex(global));
  }
  return (layout ?? TrayLayout.of(const [])).locate(global) ??
      (amsId: global ~/ 4, trayId: global % 4);
}
