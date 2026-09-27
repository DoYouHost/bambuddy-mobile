/// Model → hardware capability gating, ported from the bambuddy backend
/// (`printer_manager.py`). The server exposes no capabilities endpoint, so we
/// gate control affordances client-side from [PrinterStatus.model]. Sets include
/// both display names and the internal MQTT/SSDP codes the server may report.
library;

String _norm(String? model) => (model ?? '').trim().toUpperCase();

/// Models with an ACTIVE chamber heater (respond to M141). The chamber
/// temperature SENSOR is more widespread (X1C/X1E/P2S report it) but those
/// models ignore M141, so only these may set a chamber target.
const _chamberHeaterModels = <String>{
  'H2C',
  'H2D',
  'H2DPRO',
  'H2S',
  'X2D',
  'O1C',
  'O1C2',
  'O1D',
  'O1E',
  'O2D',
  'O1S',
  'N6',
};

/// Models with a cooling/heating airduct flap toggle (P2S/X2D/H2*). Distinct
/// from the heater set: P2S has the flap but no heater; X1E has a heater but
/// no flap.
const _airductModels = <String>{
  'P2S',
  'X2D',
  'H2C',
  'H2D',
  'H2DPRO',
  'H2S',
  'N7',
  'N6',
  'O1C',
  'O1C2',
  'O1D',
  'O1E',
  'O2D',
  'O1S',
};

/// Whether the model can actively heat its chamber (M141 has an effect).
bool supportsChamberHeater(String? model) =>
    _chamberHeaterModels.contains(_norm(model));

/// Whether the model has a cooling/heating airduct flap that can be toggled.
bool supportsAirduct(String? model) => _airductModels.contains(_norm(model));

/// Models whose Z axis carries the toolhead rather than the plate — mirrors
/// `frontend/src/utils/bedSlinger.ts` (the backend has no such table since
/// #1334), normalised the way it does: upper case, letters and digits only.
/// An explicit list on purpose: a prefix match would sweep in the next
/// A-series machine, and a wrong answer points an arrow at the plate.
const _bedSlingerModels = {
  'A1', 'A1MINI', 'A2L', 'A1M', // display names, cloud short code
  'N1', 'N2S', 'N9', 'A04', 'A11', 'A12', // internal MQTT / SSDP codes
};

/// Whether the Z axis moves the toolhead (A1 family, A2L) rather than the plate.
bool isBedSlinger(String? model) =>
    model != null &&
    _bedSlingerModels.contains(
      model.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), ''),
    );
