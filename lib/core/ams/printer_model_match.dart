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
    final bbl = RegExp(r'^BBL\s+(.+?)(?:\s+[\d.]+\s*nozzle)?$',
            caseSensitive: false)
        .firstMatch(suffix);
    if (bbl != null) return bbl.group(1)!.trim();

    // "@Bambu Lab X1 Carbon 0.4 nozzle" — what the slicer writes when a user
    // saves their own preset. Resolved through the registry; an unknown model
    // is returned as written, which still matches a printer named the same way.
    final long = RegExp(r'^Bambu Lab\s+(.+?)(?:\s+[\d.]+\s*nozzle)?$',
            caseSensitive: false)
        .firstMatch(suffix);
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
  for (final candidate in tokens) {
    if (_tokenPattern(candidate.token).hasMatch(name)) return candidate.short;
  }
  return null;
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
