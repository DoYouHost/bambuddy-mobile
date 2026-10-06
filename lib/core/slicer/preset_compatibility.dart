/// Whether a process or filament preset fits the printer preset picked in the
/// slice form — the web's `slicerPrinterMatch.ts::presetCompatibility`, ported
/// rule for rule so both clients agree on what a loaded spool maps to.
///
/// Only [PresetFit.mismatch] is acted on. Anything no rule covers is
/// [PresetFit.unknown] and stays: hiding an untagged preset would make a
/// user's own imported profiles disappear.
library;

import '../ams/printer_model_match.dart';
import '../models/slicer_preset.dart';

enum PresetFit { match, mismatch, unknown }

/// In order: the preset's own `compatible_printers` list when it has one
/// (imported presets), then the printer tag in its name — model and nozzle.
///
/// [registry] is `GET /slicer/printer-models` (long name → short code).
PresetFit presetCompatibility(
  SlicerPreset preset,
  String? selectedPrinterName,
  Map<String, String> registry,
) {
  if (selectedPrinterName == null || selectedPrinterName.isEmpty) {
    return PresetFit.unknown;
  }
  final compat = preset.compatiblePrinters;
  if (compat != null && compat.isNotEmpty) {
    final selected = _stripClonePrefix(selectedPrinterName);
    return compat.any((name) => _stripClonePrefix(name) == selected)
        ? PresetFit.match
        : PresetFit.mismatch;
  }
  return _classifyByName(preset.name, selectedPrinterName, registry);
}

/// Bambu's bundled presets drop the nozzle suffix on the 0.4 variant.
const _defaultNozzle = '0.4';

/// Nozzles Bambu ships run 0.2–0.8; the range keeps "PLA @2026" from being
/// read as a nozzle and ruled out of every printer.
const _minNozzleMm = 0.1;
const _maxNozzleMm = 2.0;

String _stripClonePrefix(String name) =>
    name.replaceFirst(RegExp(r'^#\s*'), '').trim();

({String stripped, String? nozzle}) _takeNozzleSuffix(String s) {
  final m = RegExp(
    r'^(.*?)\s+([\d.]+)\s*nozzle\s*$',
    caseSensitive: false,
  ).firstMatch(s);
  if (m == null) return (stripped: s.trim(), nozzle: null);
  return (stripped: m.group(1)!.trim(), nozzle: m.group(2));
}

/// "Bambu Lab X1 Carbon 0.4 nozzle" → model "X1 Carbon", nozzle "0.4". Null
/// for a printer preset that is not Bambu's.
({String model, String? nozzle})? printerPresetParts(String name) {
  final m = RegExp(
    r'^Bambu Lab\s+(.+)$',
    caseSensitive: false,
  ).firstMatch(_stripClonePrefix(name));
  if (m == null) return null;
  final (:stripped, :nozzle) = _takeNozzleSuffix(m.group(1)!);
  return stripped.isEmpty ? null : (model: stripped, nozzle: nozzle);
}

/// The printer tag of a preset name: "@BBL X1C", "@Bambu Lab H2D 0.4 nozzle",
/// or a bare "@0.2" (nozzle only, [token] null). A user-saved preset's
/// trailing "(Custom)" is dropped first.
({String? token, String? nozzle})? _printerTag(String presetName) {
  final cleaned = presetName
      .replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '')
      .trim();
  const marker = '@BBL ';
  final bbl = cleaned.indexOf(marker);
  if (bbl >= 0) {
    final (:stripped, :nozzle) = _takeNozzleSuffix(
      cleaned.substring(bbl + marker.length).trim(),
    );
    if (stripped.isNotEmpty) return (token: stripped, nozzle: nozzle);
  }
  // A suffix by convention, so from the last '@': a stray earlier one must
  // not swallow it.
  final at = cleaned.lastIndexOf('@');
  if (at < 0) return null;
  final suffix = cleaned.substring(at + 1).trim();
  final long = printerPresetParts(suffix);
  if (long != null) return (token: long.model, nozzle: long.nozzle);
  final nozzleOnly = RegExp(
    r'^([\d.]+)\s*(?:mm)?\s*(?:nozzle)?$',
    caseSensitive: false,
  ).firstMatch(suffix);
  if (nozzleOnly != null) {
    final size = double.tryParse(nozzleOnly.group(1)!);
    if (size != null && size >= _minNozzleMm && size <= _maxNozzleMm) {
      return (token: null, nozzle: nozzleOnly.group(1));
    }
  }
  return null;
}

bool _sameNozzle(String a, String b) {
  final x = double.tryParse(a);
  final y = double.tryParse(b);
  return x != null && y != null && x == y;
}

String _fragmentKey(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();

PresetFit _classifyByName(
  String presetName,
  String selectedPrinterName,
  Map<String, String> registry,
) {
  final tag = _printerTag(presetName);
  if (tag == null) return PresetFit.unknown;
  final selected = printerPresetParts(selectedPrinterName);
  if (selected == null) return PresetFit.unknown;
  final token = tag.token;
  if (token == null) {
    // A size alone can rule a printer out, never prove it.
    final mismatch =
        selected.nozzle != null &&
        tag.nozzle != null &&
        !_sameNozzle(tag.nozzle!, selected.nozzle!);
    return mismatch ? PresetFit.mismatch : PresetFit.unknown;
  }
  final inferred = _longFragmentOf(token, registry) ?? token;
  if (_fragmentKey(selected.model) != _fragmentKey(inferred) &&
      !matchesPrinterModel(token, selected.model)) {
    return PresetFit.mismatch;
  }
  if (selected.nozzle != null &&
      !_sameNozzle(tag.nozzle ?? _defaultNozzle, selected.nozzle!)) {
    return PresetFit.mismatch;
  }
  return PresetFit.match;
}

/// Short code → the first long name the registry gives it, without "Bambu
/// Lab" — `buildShortCodeMap` on the web.
String? _longFragmentOf(String shortCode, Map<String, String> registry) {
  for (final MapEntry(:key, :value) in registry.entries) {
    if (value == shortCode) {
      return key.replaceFirst(RegExp(r'^Bambu Lab\s+'), '');
    }
  }
  return null;
}
