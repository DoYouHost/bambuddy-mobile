/// Which nozzle an AMS slot feeds, with or without a Filament Track Switch.
///
/// Ports `backend/app/utils/fts_routing.py`, deliberately including its
/// refusal to guess: the answer is null when the printer has not said, and the
/// caller decides what a missing answer is worth. On a single-nozzle machine
/// "extruder 0" is the only possible answer and a default is harmless; on a
/// dual-nozzle one "I don't know" and "the right-hand nozzle" are different
/// answers, and conflating them is what bound a left-nozzle K-profile to a slot
/// sitting on the right.
library;

import 'slot_addressing.dart';

/// Extruder each switch inlet rests on: `A` → 1 (left), `B` → 0 (right) — the
/// same left/right numbering the whole app uses, see [slot_addressing].
///
/// Measured on the maintainer's H2C rather than read from telemetry — the
/// server's own note says `fila_switch.out` reports both outlets as the same
/// extruder, so it does not describe the wiring. The switch crosses the two
/// during a filament change, so this is where a slot sits *between* prints,
/// which is what configuring a slot by hand needs.
const _inletExtruder = <String, int>{'A': 1, 'B': 0};

/// [_inletExtruder] for `"A"`/`"B"`, null for anything else the server sends.
int? extruderForInlet(String? inlet) {
  final key = inlet?.trim().toUpperCase();
  return (key == null || key.isEmpty) ? null : _inletExtruder[key];
}

/// The extruder one AMS slot feeds, or null when it cannot be known.
///
/// [amsId] 255 is the external holder, where the tray id names the side
/// directly — see [extruderForExternalSide].
///
/// A real entry in [amsExtruderMap] always wins. With a Filament Track Switch
/// fitted every AMS reports 0xE instead of an extruder and so has no entry
/// there at all; [amsSwitchInlet] (`{amsId: "A"|"B"}`, only sent by servers
/// from the FTS release onwards) is then the only binding available. An AMS
/// wired straight to one nozzle keeps its mapping even on a machine that has a
/// switch fitted for its other units.
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
