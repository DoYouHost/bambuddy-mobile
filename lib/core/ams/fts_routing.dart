/// Which nozzle an AMS slot feeds, with or without a Filament Track Switch.
///
/// Ports `backend/app/utils/fts_routing.py`, including its refusal to guess:
/// null means the printer has not said, and conflating that with "the
/// right-hand nozzle" is what bound a left-nozzle K-profile to a right-hand
/// slot.
library;

import 'slot_addressing.dart';

/// Extruder each switch inlet rests on: `A` → 1 (left), `B` → 0 (right) — the
/// same left/right numbering the whole app uses, see [slot_addressing].
///
/// Measured on the maintainer's H2C rather than read from telemetry: the
/// server's own note says `fila_switch.out` reports both outlets as the same
/// extruder, so it does not describe the wiring. The switch crosses the two
/// during a filament change, so this is where a slot sits *between* prints,
/// which is what configuring a slot by hand needs.
const _inletExtruder = <String, int>{'A': 1, 'B': 0};

int? extruderForInlet(String? inlet) {
  final key = inlet?.trim().toUpperCase();
  return (key == null || key.isEmpty) ? null : _inletExtruder[key];
}

/// [amsId] 255 is the external holder, where the tray id names the side — see
/// [extruderForExternalSide]. With a switch fitted an AMS reports 0xE instead
/// of an extruder, so [amsSwitchInlet] (`{amsId: "A"|"B"}`, only sent by
/// servers from the FTS release onwards) is the only binding it has left.
int? slotExtruder({
  required int amsId,
  required int trayId,
  Map<int, int>? amsExtruderMap,
  Map<int, String>? amsSwitchInlet,
}) {
  if (amsId == externalHolderUnit) return extruderForExternalSide(trayId);
  final mapped = amsExtruderMap?[amsId];
  if (mapped != null) return mapped;
  return extruderForInlet(amsSwitchInlet?[amsId]);
}
