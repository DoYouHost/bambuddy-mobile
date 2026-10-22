/// Whether a file sliced for one printer model may be printed on another.
///
/// A port of the server's `is_gcode_compatible`
/// (`backend/app/utils/printer_models.py`). The server enforces it only for jobs
/// aimed at "any printer of a model" (`print_queue.py`, scheduler); a job for a
/// named printer is accepted whatever the file was sliced for. The single-printer
/// controller always names its printer, so the guard has to live here.
library;

/// The server's `PRINTER_MODEL_ID_MAP`: the internal codes `slice_info.config`
/// and SSDP carry, which `Printer.model` can hold as well. Keys are matched
/// exactly (after trimming), before any normalisation: `BL-P001` and `O1C2`
/// would not survive having their hyphens and case changed first.
const _modelIds = {
  'BL-P001': 'X1C',
  'BL-P002': 'X1',
  'C13': 'X1E',
  'C11': 'P1P',
  'C12': 'P1S',
  'P1P': 'P1P',
  'P1S': 'P1S',
  'N7': 'P2S',
  'P2S': 'P2S',
  'N6': 'X2D',
  'N9': 'A2L',
  'A11': 'A1',
  'A12': 'A1 Mini',
  'N1': 'A1 Mini',
  'N2S': 'A1',
  'A04': 'A1 Mini',
  'O1D': 'H2D',
  'O1E': 'H2D Pro',
  'O2D': 'H2D Pro',
  'O1C': 'H2C',
  'O1C2': 'H2C',
  'O1S': 'H2S',
};

/// The server's `PRINTER_MODEL_MAP`: display names as a 3MF writes them. The
/// server turns them into short names when it ingests a file, so a library file
/// normally carries the short name already; this is for a value written before
/// that, which must not become a false "incompatible" that blocks a valid print.
const _displayNames = {
  'Bambu Lab X1 Carbon': 'X1C',
  'Bambu Lab X1': 'X1',
  'Bambu Lab X1E': 'X1E',
  'Bambu Lab P1S': 'P1S',
  'Bambu Lab P1P': 'P1P',
  'Bambu Lab P2S': 'P2S',
  'Bambu Lab A1': 'A1',
  'Bambu Lab A1 Mini': 'A1 Mini',
  'Bambu Lab A1 mini': 'A1 Mini',
  'Bambu Lab A1M': 'A1 Mini',
  'Bambu Lab H2D': 'H2D',
  'Bambu Lab H2D Pro': 'H2D Pro',
  'Bambu Lab H2C': 'H2C',
  'Bambu Lab H2S': 'H2S',
  'Bambu Lab X2D': 'X2D',
  'Bambu Lab A2L': 'A2L',
};

/// The server's `GCODE_COMPAT_FAMILIES`: the one group proven interchangeable
/// (same kinematics, build volume and G-code dialect). Everything else is an
/// exact match. Extend only as the server does — a wrong entry sends G-code to
/// hardware it was not sliced for.
const _families = [
  {'X1', 'X1C', 'X1E', 'P1P', 'P1S'},
];

String _normalise(String model) {
  final trimmed = model.trim();
  final resolved = _modelIds[trimmed] ?? _displayNames[trimmed] ?? trimmed;
  return resolved.trim().toUpperCase().replaceAll(' ', '').replaceAll('-', '');
}

/// Whether G-code sliced for [slicedFor] may be printed on [printerModel].
///
/// A missing or blank model on either side is compatible: only what a 3MF
/// declares can be checked, and files from before it was recorded must keep
/// printing. (The server also treats a whitespace-only name as a model of its
/// own; here it is blank, which can only make the guard more permissive.)
bool isGcodeCompatible(String? slicedFor, String? printerModel) {
  if (slicedFor == null || slicedFor.trim().isEmpty) return true;
  if (printerModel == null || printerModel.trim().isEmpty) return true;
  final a = _normalise(slicedFor);
  final b = _normalise(printerModel);
  return a == b || _families.any((f) => f.contains(a) && f.contains(b));
}
