/// The H2C's nozzle rack: what sits in each position, and which position a
/// sliced filament group may print from.
///
/// Ports the two decisions `backend/app/services/bambu_mqtt.py` makes at
/// dispatch (`_rack_by_position`, `_rack_slot_is_eligible`) so the print form
/// can offer the same choice the scheduler will re-check. Getting either wrong
/// is not cosmetic: the server refuses to dispatch a pick that no longer fits,
/// and a pick that fits the wrong nozzle prints a 0.4 extrusion through a 0.2
/// orifice.
library;

import '../models/printer_status.dart';

/// Positions as the operator, the printer's screen and Bambu Studio all count
/// them. Six is the H2C's rack; the count is the length of the physical-id
/// range the firmware reports (16–21), not a guess.
const rackPositions = [1, 2, 3, 4, 5, 6];

/// Physical nozzle id of rack position 1, minus one — position `n` reports
/// `_rackPositionBase + n`. Measured server-side: a plate dispatched picking
/// R1 and R3 sent 16 and 18.
const _rackPositionBase = 15;

/// The nozzle currently picked up onto the rack carriage reports this id
/// instead of its dock's. Physical id 1 is the fixed hotend, so the carriage's
/// own entry is 0.
const _carriageNozzleId = 0;

/// Live rack contents keyed by 1-based position, the mounted nozzle included.
///
/// While a nozzle is picked up onto the carriage the firmware omits its dock id
/// altogether rather than sending an empty placeholder. Taken at face value
/// that rules the nozzle out of the very print that wants it — and it is the
/// likeliest position to be picked, being the one the last print left mounted.
/// The gap is only recoverable when exactly one id is missing; two or more are
/// genuinely ambiguous (an operator with four nozzles in six docks looks the
/// same), and those stay absent.
Map<int, NozzleRackSlot> rackByPosition(List<NozzleRackSlot>? slots) {
  final byPosition = <int, NozzleRackSlot>{};
  NozzleRackSlot? carriage;
  for (final slot in slots ?? const <NozzleRackSlot>[]) {
    final id = slot.id;
    if (id == null) continue;
    if (id == _carriageNozzleId) {
      carriage = slot;
      continue;
    }
    final position = id - _rackPositionBase;
    if (rackPositions.contains(position)) byPosition[position] = slot;
  }

  final missing = [
    for (final position in rackPositions)
      if (!byPosition.containsKey(position)) position,
  ];
  if (missing.length == 1 && carriage != null && !carriage.isEmpty) {
    byPosition[missing.single] = carriage;
  }
  return byPosition;
}

/// Whether the nozzle in one rack position can print a group that asks for
/// [diameter] and [volumeType].
///
/// Mirrors the filter Bambu Studio applies in its own picker: the position has
/// to hold a nozzle, and that nozzle has to match the slice's diameter and flow
/// type. Flow is compared only when both sides state it, so a printer that
/// omits the code is not thereby ruled out.
bool rackSlotFits(
  NozzleRackSlot slot, {
  required String diameter,
  required String volumeType,
}) {
  final slotDiameter = slot.nozzleDiameter?.trim() ?? '';
  final slotType = slot.nozzleType?.trim() ?? '';
  if (slotDiameter.isEmpty && slotType.isEmpty) return false;

  // "0.40" and "0.4" are the same nozzle spelled two ways — the 3MF pads, the
  // printer does not — so the strings cannot be compared directly.
  final wantedDiameter = double.tryParse(diameter.trim());
  final haveDiameter = double.tryParse(slotDiameter);
  if (wantedDiameter == null || haveDiameter == null) return false;
  if ((wantedDiameter - haveDiameter).abs() > 0.005) return false;

  final wantedFlow = highFlowFromName(volumeType);
  final haveFlow = highFlowFromCode(slotType);
  if (wantedFlow != null && haveFlow != null && wantedFlow != haveFlow) {
    return false;
  }
  return true;
}

/// Whether the printer's own flow-type code names a high-flow nozzle: `HH…`
/// yes, anything else no. Null when the printer states nothing, which is not
/// the same as "standard" — [rackSlotFits] then skips the flow check rather
/// than ruling the position out.
bool? highFlowFromCode(String? code) {
  final value = code?.trim().toUpperCase() ?? '';
  return value.isEmpty ? null : value.startsWith('HH');
}

/// The same answer from the slicer's spelling of the property (`High Flow` /
/// `Standard`), which is the form a filament group states it in.
bool? highFlowFromName(String? name) {
  final value = name?.trim().toLowerCase() ?? '';
  return value.isEmpty ? null : value.startsWith('high flow');
}

/// A nozzle diameter as one number rather than two spellings: the slicer pads
/// it (`0.40`) and the printer does not (`0.4`), and a row showing both next to
/// each other reads as two different nozzles. Anything unparseable is passed
/// through untouched.
String nozzleDiameterLabel(String? raw) {
  final text = raw?.trim() ?? '';
  final value = double.tryParse(text);
  if (value == null) return text;
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
