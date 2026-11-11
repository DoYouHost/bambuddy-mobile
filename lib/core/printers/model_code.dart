/// The model a printer advertises over SSDP is an internal code (`N10`, `O1D`);
/// the add-printer form stores the short name. A port of the web's
/// `mapModelCode` (`frontend/src/utils/printerModel.ts`), which the web applies
/// when a discovered printer prefills the form and in the discovery list.
///
/// Not the server's `PRINTER_MODEL_ID_MAP` that `gcode_compat.dart` ports: the
/// web adds `BL-P002`/`BL-P003`, and an unknown code comes back unchanged.
library;

const _ssdpCodes = {
  'O1D': 'H2D',
  'O1E': 'H2D Pro',
  'O2D': 'H2D Pro',
  'O1C': 'H2C',
  'O1C2': 'H2C',
  'O1S': 'H2S',
  'N10': 'H3C',
  'BL-P001': 'X1C',
  'BL-P002': 'X1',
  'BL-P003': 'X1E',
  'C13': 'X1E',
  'N6': 'X2D',
  'N9': 'A2L',
  'C11': 'P1P',
  'C12': 'P1S',
  'N7': 'P2S',
  'N2S': 'A1',
  'N1': 'A1 Mini',
  'A11': 'A1',
  'A12': 'A1 Mini',
  'A04': 'A1 Mini',
};

/// The short model name for an SSDP [code]; anything else unchanged.
String mapModelCode(String code) => _ssdpCodes[code] ?? code;
