/// The web's filament mapping, ported line for line from
/// `frontend/src/hooks/useFilamentMapping.ts` and the helpers it uses in
/// `frontend/src/utils/amsHelpers.ts`: which loaded slot each filament of a
/// print goes to, and the `ams_mapping` array that carries the answer.
///
/// Kept structurally identical to the TypeScript so the two can be read side
/// by side — the dialog and the app must not pick different slots for the same
/// print, and the server's dispatcher (`print_scheduler.py`) is held to the
/// same ranking.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/filament_requirement.dart';
import '../models/printer_status.dart';
import 'slot_addressing.dart';

/// One loaded slot (`LoadedFilament`).
@immutable
class LoadedFilament {
  const LoadedFilament({
    required this.type,
    required this.color,
    required this.amsId,
    required this.trayId,
    required this.isHt,
    required this.isExternal,
    required this.globalTrayId,
    this.trayInfoIdx = '',
    this.extruderId,
    this.remain = -1,
  });

  final String type;

  /// `#RRGGBB`, or `#RRGGBBAA` below full opacity ([normalizeColor]).
  final String color;
  final int amsId;
  final int trayId;
  final bool isHt;
  final bool isExternal;
  final int globalTrayId;
  final String trayInfoIdx;

  /// 0 = right, 1 = left; null on a single-nozzle printer.
  final int? extruderId;

  /// The AMS's own percent, -1 when unknown.
  final int remain;
}

/// `buildLoadedFilaments`: every slot of [status] that reports a type.
List<LoadedFilament> buildLoadedFilaments(PrinterStatus? status) {
  if (status == null) return const [];
  final extruderMap = status.amsExtruderMap;
  final externals = status.vtTray ?? const <AmsTray>[];
  final nozzles = status.nozzles ?? const [];
  // The backend always sends two nozzle entries, so the second one's diameter
  // is the signal, with the extruder map and a second holder as fallbacks.
  final hasDualNozzle =
      (nozzles.length > 1 &&
          (nozzles[1].nozzleDiameter?.isNotEmpty ?? false)) ||
      (extruderMap?.isNotEmpty ?? false) ||
      externals.length > 1;

  final out = <LoadedFilament>[];
  final units = status.ams ?? const <AmsUnit>[];
  for (var u = 0; u < units.length; u++) {
    final unit = units[u];
    final trays = unit.trays ?? const <AmsTray>[];
    final amsId = unit.id ?? u;
    final isHt = trays.length == 1;
    for (final tray in trays) {
      final type = tray.trayType;
      if (type == null || type.isEmpty) continue;
      final trayId = tray.id ?? 0;
      out.add(
        LoadedFilament(
          type: type,
          color: normalizeColor(tray.trayColor),
          amsId: amsId,
          trayId: trayId,
          isHt: isHt,
          isExternal: false,
          globalTrayId: globalTrayId(amsId: amsId, trayId: trayId),
          trayInfoIdx: tray.trayInfoIdx ?? '',
          extruderId: extruderMap?[amsId],
          remain: tray.remain ?? -1,
        ),
      );
    }
  }
  for (final ext in externals) {
    final type = ext.trayType;
    if (type == null || type.isEmpty) continue;
    final id = ext.id ?? externalTrayIdBase;
    out.add(
      LoadedFilament(
        type: type,
        color: normalizeColor(ext.trayColor),
        amsId: -1,
        trayId: id - externalTrayIdBase,
        isHt: false,
        isExternal: true,
        // The holder's global id is its tray id, 254 or 255.
        globalTrayId: id,
        trayInfoIdx: ext.trayInfoIdx ?? '',
        extruderId: hasDualNozzle ? 255 - id : null,
        remain: ext.remain ?? -1,
      ),
    );
  }
  return out;
}

/// `normalizeColor`: `#RRGGBB`, keeping the alpha only below `ff`; grey for
/// no colour at all.
String normalizeColor(String? color) {
  if (color == null || color.isEmpty) return '#808080';
  final clean = color.replaceFirst('#', '');
  if (clean.length >= 8 && clean.substring(6, 8).toLowerCase() != 'ff') {
    return '#${clean.substring(0, 8)}';
  }
  return '#${clean.substring(0, math.min(6, clean.length))}';
}

/// `normalizeColorForCompare`: lower case, no hash, no alpha.
String normalizeColorForCompare(String? color) {
  if (color == null || color.isEmpty) return '';
  final clean = color.replaceFirst('#', '').toLowerCase();
  return clean.substring(0, math.min(6, clean.length));
}

/// Types the firmware treats as one (`FILAMENT_TYPE_GROUPS`).
const _filamentTypeGroups = [
  ['PA-CF', 'PA12-CF', 'PAHT-CF'],
];

final _equivalence = {
  for (final group in _filamentTypeGroups)
    for (final t in group) t.toUpperCase(): group.first.toUpperCase(),
};

String _canonicalFilamentType(String? type) {
  if (type == null || type.isEmpty) return '';
  final upper = type.toUpperCase();
  return _equivalence[upper] ?? upper;
}

bool filamentTypesCompatible(String? a, String? b) =>
    _canonicalFilamentType(a) == _canonicalFilamentType(b);

/// `colorsAreSimilar`: every RGB channel within [threshold].
bool colorsAreSimilar(String? a, String? b, {int threshold = 40}) {
  final rgb1 = _rgb(normalizeColorForCompare(a));
  final rgb2 = _rgb(normalizeColorForCompare(b));
  if (rgb1 == null || rgb2 == null) return false;
  for (var i = 0; i < 3; i++) {
    if ((rgb1[i] - rgb2[i]).abs() > threshold) return false;
  }
  return true;
}

List<int>? _rgb(String hex) {
  if (hex.length < 6) return null;
  final channels = [
    for (final i in const [0, 2, 4])
      int.tryParse(hex.substring(i, i + 2), radix: 16),
  ];
  return channels.contains(null) ? null : channels.cast<int>();
}

const _d65White = [0.95047, 1.0, 1.08883];
const _labDelta = 6 / 29;

/// `hexToLab`: CIE L*a*b* under D65.
List<double>? _hexToLab(String? color) {
  final rgb = _rgb(normalizeColorForCompare(color));
  if (rgb == null) return null;
  final linear = [
    for (final c in rgb)
      c / 255 <= 0.04045
          ? c / 255 / 12.92
          : math.pow((c / 255 + 0.055) / 1.055, 2.4).toDouble(),
  ];
  final (r, g, b) = (linear[0], linear[1], linear[2]);
  final xyz = [
    0.4124564 * r + 0.3575761 * g + 0.1804375 * b,
    0.2126729 * r + 0.7151522 * g + 0.072175 * b,
    0.0193339 * r + 0.119192 * g + 0.9503041 * b,
  ];
  double f(double t) => t > math.pow(_labDelta, 3)
      ? math.pow(t, 1 / 3).toDouble()
      : t / (3 * _labDelta * _labDelta) + 4 / 29;
  final fx = f(xyz[0] / _d65White[0]);
  final fy = f(xyz[1] / _d65White[1]);
  final fz = f(xyz[2] / _d65White[2]);
  return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
}

/// `ciede2000`, kL = kC = kH = 1.
@visibleForTesting
double ciede2000(List<double> lab1, List<double> lab2) {
  final (l1, a1, b1) = (lab1[0], lab1[1], lab1[2]);
  final (l2, a2, b2) = (lab2[0], lab2[1], lab2[2]);
  double rad(double deg) => deg * math.pi / 180;
  double hypot(double x, double y) => math.sqrt(x * x + y * y);
  final pow25to7 = math.pow(25, 7).toDouble();

  final c1 = hypot(a1, b1);
  final c2 = hypot(a2, b2);
  final cBar7 = math.pow((c1 + c2) / 2, 7).toDouble();
  final g = 0.5 * (1 - math.sqrt(cBar7 / (cBar7 + pow25to7)));

  final a1p = (1 + g) * a1;
  final a2p = (1 + g) * a2;
  final c1p = hypot(a1p, b1);
  final c2p = hypot(a2p, b2);

  double hue(double ap, double bp) {
    if (ap == 0 && bp == 0) return 0;
    final deg = math.atan2(bp, ap) * 180 / math.pi;
    return deg < 0 ? deg + 360 : deg;
  }

  final h1p = hue(a1p, b1);
  final h2p = hue(a2p, b2);

  final dlp = l2 - l1;
  final dcp = c2p - c1p;

  final chromaProduct = c1p * c2p;
  var dhp = 0.0;
  if (chromaProduct != 0) {
    dhp = h2p - h1p;
    if (dhp > 180) {
      dhp -= 360;
    } else if (dhp < -180) {
      dhp += 360;
    }
  }
  final dhpBig = 2 * math.sqrt(chromaProduct) * math.sin(rad(dhp) / 2);

  final lBar = (l1 + l2) / 2;
  final cBar = (c1p + c2p) / 2;

  final double hBar;
  if (chromaProduct == 0) {
    hBar = h1p + h2p;
  } else if ((h1p - h2p).abs() <= 180) {
    hBar = (h1p + h2p) / 2;
  } else if (h1p + h2p < 360) {
    hBar = (h1p + h2p + 360) / 2;
  } else {
    hBar = (h1p + h2p - 360) / 2;
  }

  final t =
      1 -
      0.17 * math.cos(rad(hBar - 30)) +
      0.24 * math.cos(rad(2 * hBar)) +
      0.32 * math.cos(rad(3 * hBar + 6)) -
      0.2 * math.cos(rad(4 * hBar - 63));

  final cBarP7 = math.pow(cBar, 7).toDouble();
  final rc = 2 * math.sqrt(cBarP7 / (cBarP7 + pow25to7));
  final lBar50 = (lBar - 50) * (lBar - 50);
  final sl = 1 + (0.015 * lBar50) / math.sqrt(20 + lBar50);
  final sc = 1 + 0.045 * cBar;
  final sh = 1 + 0.015 * cBar * t;
  final hTerm = (hBar - 275) / 25;
  final rt = -math.sin(rad(2 * (30 * math.exp(-(hTerm * hTerm))))) * rc;

  final dL = dlp / sl;
  final dC = dcp / sc;
  final dH = dhpBig / sh;
  return math.sqrt(dL * dL + dC * dC + dH * dH + rt * dC * dH);
}

/// `colorDistance`: CIEDE2000 between two hex colours, null if either is not
/// one.
double? perceptualColorDistance(String? a, String? b) {
  final lab1 = _hexToLab(a);
  final lab2 = _hexToLab(b);
  if (lab1 == null || lab2 == null) return null;
  return ciede2000(lab1, lab2);
}

/// `findNearestSimilar`: the closest of the [candidates] [colorsAreSimilar]
/// admits; ties keep the earliest, so the order given is the tie-break.
LoadedFilament? _findNearestSimilar(
  List<LoadedFilament> candidates,
  String? requiredColor,
) {
  LoadedFilament? best;
  var bestDistance = double.infinity;
  for (final candidate in candidates) {
    if (!colorsAreSimilar(candidate.color, requiredColor)) continue;
    final distance = perceptualColorDistance(candidate.color, requiredColor);
    if (distance == null) continue;
    if (distance < bestDistance) {
      best = candidate;
      bestDistance = distance;
    }
  }
  return best;
}

int _slotPriority(int amsId, int trayId) {
  if (amsId < 0) return 10000;
  if (amsId >= amsHtUnitBase) {
    return 1000 + (amsId - amsHtUnitBase) * 4 + trayId;
  }
  return amsId * 4 + trayId;
}

/// `preferLowestSortKey`: spools the inventory tracks first, by grams; the
/// rest by the AMS's percent, unknown last; slot order breaks ties.
List<num> _preferLowestSortKey(
  LoadedFilament f,
  Map<int, double>? inventoryByTrayId,
) {
  final slot = _slotPriority(f.amsId, f.trayId);
  final grams = inventoryByTrayId?[f.globalTrayId];
  if (grams != null) return [0, grams, slot];
  return [1, f.remain >= 0 ? f.remain : 101, slot];
}

int _compareSortKeys(List<num> a, List<num> b) {
  for (var i = 0; i < 3; i++) {
    final c = a[i].compareTo(b[i]);
    if (c != 0) return c;
  }
  return 0;
}

/// `effectivePreferLowest`: the server setting, unless the printer says its
/// AMS Filament Backup is off — then nothing can take over when the lowest
/// spool runs out. Unknown keeps the setting.
bool effectivePreferLowest(bool? setting, bool? amsFilamentBackup) =>
    (setting ?? false) && amsFilamentBackup != false;

enum FilamentMatch { match, typeOnly, mismatch }

/// One requirement against what is loaded (`FilamentComparison`).
@immutable
class FilamentComparison {
  const FilamentComparison({
    required this.requirement,
    required this.loaded,
    required this.status,
    required this.isManual,
  });

  final FilamentRequirement requirement;
  final LoadedFilament? loaded;
  final FilamentMatch status;
  final bool isManual;
}

/// `coloursMatch`: a requirement with no colour asks for none.
bool _coloursMatch(String? loaded, String? required) {
  final want = normalizeColorForCompare(required);
  if (want.isEmpty) return true;
  return normalizeColorForCompare(loaded) == want ||
      colorsAreSimilar(loaded, required);
}

/// `buildFilamentComparison`. Stateful across the list — a slot given to one
/// filament is not offered to the next — so pass exactly one plate's
/// requirements. [manual] maps `slot_id` to a global tray id.
List<FilamentComparison> buildFilamentComparison(
  List<FilamentRequirement> requirements,
  List<LoadedFilament> loaded,
  Map<int, int> manual, {
  bool preferLowest = false,
  Map<int, double>? inventoryByTrayId,
  bool ftsActive = false,
}) {
  if (requirements.isEmpty) return const [];
  final used = {...manual.values};

  int byLowest(LoadedFilament a, LoadedFilament b) => _compareSortKeys(
    _preferLowestSortKey(a, inventoryByTrayId),
    _preferLowestSortKey(b, inventoryByTrayId),
  );

  return [
    for (final req in requirements)
      () {
        final slotId = req.slotId;
        final manualTray = slotId > 0 ? manual[slotId] : null;
        if (manualTray != null) {
          final pick = loaded
              .where((f) => f.globalTrayId == manualTray)
              .firstOrNull;
          if (pick != null) {
            final typeMatch = filamentTypesCompatible(pick.type, req.type);
            final colorMatch = _coloursMatch(pick.color, req.color);
            return FilamentComparison(
              requirement: req,
              loaded: pick,
              status: typeMatch && colorMatch
                  ? FilamentMatch.match
                  : typeMatch
                  ? FilamentMatch.typeOnly
                  : FilamentMatch.mismatch,
              isManual: true,
            );
          }
        }

        final reqIdx = req.trayInfoIdx ?? '';
        var available = [
          for (final f in loaded)
            if (!used.contains(f.globalTrayId)) f,
        ];
        // A hard filter: a slot on the other nozzle fails the print. A
        // Filament Track Switch routes any slot to either nozzle.
        if (req.nozzleId != null && !ftsActive) {
          available = [
            for (final f in available)
              if (f.extruderId == req.nozzleId) f,
          ];
        }
        if (preferLowest) {
          available = [...available]..sort(byLowest);
        }

        bool sameType(LoadedFilament f) =>
            filamentTypesCompatible(f.type, req.type);
        bool sameColor(LoadedFilament f) =>
            normalizeColorForCompare(f.color) ==
            normalizeColorForCompare(req.color);

        LoadedFilament? idxMatch;
        LoadedFilament? exactMatch;
        LoadedFilament? similarMatch;
        LoadedFilament? typeOnlyMatch;

        if (reqIdx.isNotEmpty) {
          final idxMatches = [
            for (final f in available)
              if (f.trayInfoIdx == reqIdx) f,
          ];
          if (idxMatches.length == 1) {
            idxMatch = idxMatches.single;
          } else if (idxMatches.length > 1) {
            if (preferLowest) idxMatches.sort(byLowest);
            exactMatch = idxMatches
                .where((f) => sameType(f) && sameColor(f))
                .firstOrNull;
            if (exactMatch == null) {
              similarMatch = _findNearestSimilar(
                idxMatches.where(sameType).toList(),
                req.color,
              );
            }
            if (exactMatch == null && similarMatch == null) {
              typeOnlyMatch = idxMatches.where(sameType).firstOrNull;
            }
          }
        }

        if (idxMatch == null &&
            exactMatch == null &&
            similarMatch == null &&
            typeOnlyMatch == null) {
          exactMatch = available
              .where((f) => sameType(f) && sameColor(f))
              .firstOrNull;
          if (exactMatch == null) {
            similarMatch = _findNearestSimilar(
              available.where(sameType).toList(),
              req.color,
            );
          }
          if (exactMatch == null && similarMatch == null) {
            typeOnlyMatch = available.where(sameType).firstOrNull;
          }
        }

        final pick = idxMatch ?? exactMatch ?? similarMatch ?? typeOnlyMatch;
        if (pick != null) used.add(pick.globalTrayId);
        // #2687: the colour verdict is judged on the slot picked, whichever
        // branch picked it.
        return FilamentComparison(
          requirement: req,
          loaded: pick,
          status: pick == null
              ? FilamentMatch.mismatch
              : _coloursMatch(pick.color, req.color)
              ? FilamentMatch.match
              : FilamentMatch.typeOnly,
          isManual: false,
        );
      }(),
  ];
}

/// `buildAmsMapping`: indexed by `slot_id - 1`, the global tray id or -1, so
/// a plate printing only slot 3 still sends `[-1, -1, tray]`. Null when
/// there is nothing to map.
List<int>? buildAmsMapping(List<FilamentComparison> comparisons) {
  if (comparisons.isEmpty) return null;
  final maxSlotId = comparisons
      .map((c) => c.requirement.slotId)
      .reduce(math.max);
  if (maxSlotId <= 0) return null;
  final mapping = List<int>.filled(maxSlotId, -1);
  for (final c in comparisons) {
    final slotId = c.requirement.slotId;
    if (slotId > 0) mapping[slotId - 1] = c.loaded?.globalTrayId ?? -1;
  }
  return mapping;
}
