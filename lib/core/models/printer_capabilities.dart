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
  'H2C', 'H2D', 'H2DPRO', 'H2S', 'X2D',
  'O1C', 'O1C2', 'O1D', 'O1E', 'O2D', 'O1S', 'N6',
};

/// Models with a cooling/heating airduct flap toggle (P2S/X2D/H2*). Distinct
/// from the heater set: P2S has the flap but no heater; X1E has a heater but
/// no flap.
const _airductModels = <String>{
  'P2S', 'X2D', 'H2C', 'H2D', 'H2DPRO', 'H2S',
  'N7', 'N6', 'O1C', 'O1C2', 'O1D', 'O1E', 'O2D', 'O1S',
};

/// Whether the model can actively heat its chamber (M141 has an effect).
bool supportsChamberHeater(String? model) =>
    _chamberHeaterModels.contains(_norm(model));

/// Whether the model has a cooling/heating airduct flap that can be toggled.
bool supportsAirduct(String? model) => _airductModels.contains(_norm(model));
