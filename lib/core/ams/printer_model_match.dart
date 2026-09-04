/// Deciding which printer a filament preset belongs to, from its name.
///
/// A cloud account holds every preset for every printer the user owns, so an
/// unfiltered picker offers H2D profiles for an A1 slot. The only evidence is
/// the name — Bambu writes the model into it, in three different shapes — and
/// the registry at `GET /slicer/printer-models` is the map between the long
/// names that appear there and the short codes `Printer.model` uses.
///
/// Nothing here guesses: a name that resolves to no model stays visible. Hiding
/// a preset we merely failed to classify is worse than showing one too many.
library;

/// Bambu Cloud started shipping terse model codes in `@BBL <code>` suffixes
/// mid-2026 — "A1 Mini" became "A1M" (bambuddy #1649) — while user presets kept
/// the long form, so both have to match the same printer. Kept deliberately
/// narrow: a wider net would quietly group printers that are genuinely
/// different.
const _modelAliases = <String, List<String>>{
  'A1 MINI': ['A1M'],
};

/// The nozzle segment a preset name ends with. The word itself is optional:
/// "@BBL X1C 0.4" turns up without it, and folding the size into the model
/// token there would leave the preset matching no printer at all — the one
/// outcome this file is written to avoid.
const _nozzleSuffix = r'(?:\s+[\d.]+\s*(?:mm)?\s*(?:nozzle)?)?$';

final _bblSuffix =
    RegExp('^BBL\\s+(.+?)$_nozzleSuffix', caseSensitive: false);
final _longSuffix =
    RegExp('^Bambu Lab\\s+(.+?)$_nozzleSuffix', caseSensitive: false);

/// Whether a model token taken from a preset name names the same printer as
/// [printerModel] (the short code on our `Printer`).
bool matchesPrinterModel(String presetModel, String printerModel) {
  final preset = presetModel.toUpperCase();
  final printer = printerModel.toUpperCase();
  if (preset == printer) return true;
  if (_modelAliases[printer]?.contains(preset) ?? false) return true;
  if (_modelAliases[preset]?.contains(printer) ?? false) return true;
  return false;
}

/// True unless [name] names a *different* printer than [printerModel].
///
/// The fail-open rule this whole file exists for, in one place: a name that
/// resolves to no model, and a caller with no model of its own, both keep the
/// preset. [printerModels] is the registry; without it nothing resolves and
/// nothing is hidden.
bool presetFitsPrinterModel(
  String name,
  String? printerModel,
  Map<String, String> printerModels,
) {
  if (printerModel == null || printerModel.isEmpty) return true;
  final presetModel = presetPrinterModel(name, printerModels);
  if (presetModel == null) return true;
  return matchesPrinterModel(presetModel, printerModel);
}

/// The printer a preset name refers to, as a short code, or null when the name
/// says nothing about it.
///
/// [modelsLongToShort] is the registry verbatim: `{"Bambu Lab X1 Carbon":
/// "X1C", …}`.
String? presetPrinterModel(
  String name,
  Map<String, String> modelsLongToShort,
) {
  final atIndex = name.indexOf('@');
  if (atIndex >= 0) {
    final suffix = name.substring(atIndex + 1).trim();

    // "@BBL X1C 0.4 nozzle" — Bambu's own cloud presets, already short.
    final bbl = _bblSuffix.firstMatch(suffix);
    if (bbl != null) return bbl.group(1)!.trim();

    // "@Bambu Lab X1 Carbon 0.4 nozzle" — what the slicer writes when a user
    // saves their own preset. Resolved through the registry; an unknown model
    // is returned as written, which still matches a printer named the same way.
    final long = _longSuffix.firstMatch(suffix);
    if (long != null) {
      final fragment = long.group(1)!.trim();
      final key = 'Bambu Lab $fragment';
      final direct = modelsLongToShort[key];
      if (direct != null) return direct;
      final lowered = key.toLowerCase();
      for (final entry in modelsLongToShort.entries) {
        if (entry.key.toLowerCase() == lowered) return entry.value;
      }
      return fragment;
    }
  }

  // No suffix at all: many user-authored presets put the model at the front
  // ("X1C eSUN PETG-Basic Filament", bambuddy #1623). Scan for any known token,
  // longest first so "A1 Mini" is not eaten by "A1".
  for (final candidate in _scanTokens(modelsLongToShort)) {
    if (candidate.pattern.hasMatch(name)) return candidate.short;
  }
  return null;
}

typedef _ModelToken = ({RegExp pattern, String short});

/// The registry is static reference data and the picker classifies a whole
/// preset list per keystroke, so the tokens and their patterns are built once
/// per registry rather than once per preset. Identity comparison is enough: the
/// map comes from a provider and is replaced, never edited.
Map<String, String>? _scannedRegistry;
List<_ModelToken> _scannedTokens = const [];

List<_ModelToken> _scanTokens(Map<String, String> modelsLongToShort) {
  if (identical(_scannedRegistry, modelsLongToShort)) return _scannedTokens;

  final tokens = <({String token, String short})>[];
  final seen = <String>{};
  for (final entry in modelsLongToShort.entries) {
    final fragment = entry.key.replaceFirst(RegExp(r'^Bambu Lab\s+'), '');
    if (seen.add(fragment.toLowerCase())) {
      tokens.add((token: fragment, short: entry.value));
    }
    if (seen.add(entry.value.toLowerCase())) {
      tokens.add((token: entry.value, short: entry.value));
    }
  }
  tokens.sort((a, b) => b.token.length.compareTo(a.token.length));

  _scannedRegistry = modelsLongToShort;
  _scannedTokens = [
    for (final t in tokens) (pattern: _tokenPattern(t.token), short: t.short),
  ];
  return _scannedTokens;
}

/// The full printer-preset name for a printer, e.g. `X1C` + `0.4` → "Bambu Lab
/// X1 Carbon 0.4 nozzle". That is the form an imported preset's
/// `compatible_printers` list is written in, so it is the only thing those can
/// be compared against. Null when the registry does not know the model.
String? fullPrinterPresetName(
  String printerModel,
  Map<String, String> modelsLongToShort,
  String nozzleDiameter,
) {
  for (final entry in modelsLongToShort.entries) {
    if (entry.value != printerModel) continue;
    final longName = entry.key.startsWith('Bambu Lab ')
        ? entry.key
        : 'Bambu Lab ${entry.key}';
    return '$longName $nozzleDiameter nozzle';
  }
  return null;
}

/// Comparable form of a printer-preset name: the slicer's `"# "` user-clone
/// prefix off, whitespace collapsed, case dropped. Without the prefix rule a
/// preset cloned from a printer reads as incompatible with that same printer.
String normalisePrinterPresetName(String name) => name
    .replaceFirst(RegExp(r'^#\s*'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toLowerCase();

/// A literal model token as a word-boundary pattern. Escaped so a token with a
/// `.` in it stays literal, and with whitespace loosened so "A1 Mini" matches
/// "A1  Mini".
RegExp _tokenPattern(String token) {
  final escaped = token
      .replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (m) => '\\${m[0]}')
      .replaceAll(RegExp(r'\s+'), r'\s+');
  return RegExp('\\b$escaped\\b', caseSensitive: false);
}
