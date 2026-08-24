/// Filament inventory models (spools) — domain-normalized, backend-agnostic.
/// App uses native `/inventory/*` (default) but must work with Spoolman
/// (`/spoolman/inventory/*`), which returns different JSON shape. So model is
/// hand-written with tolerant helpers and per-backend factories — UI gets one
/// coherent type, unaware of source.
///
/// Defensive parsing: all except `id`/`material` are nullable, unknown keys
/// ignored, numbers accept int/num/string.
library;

import 'json_utils.dart';

/// Strips everything that is not a hex digit and upper-cases the rest — the
/// form the server stores RFID identifiers in, so comparing a printer-reported
/// tag against a stored one has to go through here first
/// (`backend/app/utils/tag_normalization.py::normalize_hex`).
String normalizeTagHex(String? value) {
  if (value == null) return '';
  final buffer = StringBuffer();
  for (final unit in value.trim().codeUnits) {
    final isDigit = unit >= 0x30 && unit <= 0x39;
    final isUpper = unit >= 0x41 && unit <= 0x46;
    final isLower = unit >= 0x61 && unit <= 0x66;
    if (isDigit || isUpper) {
      buffer.writeCharCode(unit);
    } else if (isLower) {
      buffer.writeCharCode(unit - 0x20);
    }
  }
  return buffer.toString();
}

/// A tag UID as the server keys on it: the column holds 16 characters, and a
/// longer value keeps its least-significant bytes.
String normalizeTagUid(String? value) {
  final uid = normalizeTagHex(value);
  return uid.length > 16 ? uid.substring(uid.length - 16) : uid;
}

/// A tray UUID as the server keys on it: 32 characters, truncated from the
/// front — the opposite end from [normalizeTagUid], mirroring the server.
String normalizeTrayUuid(String? value) {
  final uuid = normalizeTagHex(value);
  return uuid.length >= 32 ? uuid.substring(0, 32) : uuid;
}

/// One spool on the shelf. Every weight field is in grams.
class Spool {
  const Spool({
    required this.id,
    required this.material,
    this.subtype,
    this.colorName,
    this.rgba,
    this.extraColors,
    this.effectType,
    this.brand,
    this.labelWeight = 0,
    this.weightUsed = 0,
    this.weightUsedBaseline = 0,
    this.coreWeight = 250,
    this.coreWeightCatalogId,
    this.lastScaleWeight,
    this.costPerKg,
    this.lowStockThresholdPct,
    this.storageLocation,
    this.category,
    this.note,
    this.nozzleTempMin,
    this.nozzleTempMax,
    this.tagUid,
    this.trayUuid,
    this.archivedAt,
    this.lastUsed,
    this.slicerFilament,
    this.slicerFilamentName,
    this.kProfiles = const [],
  });

  /// Native `SpoolResponse` from `GET /inventory/spools`.
  factory Spool.fromNative(Map<String, dynamic> json) => Spool(
        id: toIntOrNull(json['id']) ?? -1,
        material: (json['material'] as String?)?.trim().isNotEmpty == true
            ? json['material'] as String
            : 'Unknown',
        subtype: toStringOrNull(json['subtype']),
        colorName: toStringOrNull(json['color_name']),
        rgba: toStringOrNull(json['rgba']),
        extraColors: toStringOrNull(json['extra_colors']),
        effectType: toStringOrNull(json['effect_type']),
        brand: toStringOrNull(json['brand']),
        labelWeight: toIntOrNull(json['label_weight']) ?? 0,
        weightUsed: toDoubleOrNull(json['weight_used']) ?? 0,
        weightUsedBaseline: toDoubleOrNull(json['weight_used_baseline']) ?? 0,
        coreWeight: toIntOrNull(json['core_weight']) ?? 250,
        coreWeightCatalogId: toIntOrNull(json['core_weight_catalog_id']),
        lastScaleWeight: toIntOrNull(json['last_scale_weight']),
        costPerKg: toDoubleOrNull(json['cost_per_kg']),
        lowStockThresholdPct: toIntOrNull(json['low_stock_threshold_pct']),
        storageLocation: toStringOrNull(json['storage_location']),
        category: toStringOrNull(json['category']),
        note: toStringOrNull(json['note']),
        nozzleTempMin: toIntOrNull(json['nozzle_temp_min']),
        nozzleTempMax: toIntOrNull(json['nozzle_temp_max']),
        tagUid: toStringOrNull(json['tag_uid']),
        trayUuid: toStringOrNull(json['tray_uuid']),
        archivedAt: toStringOrNull(json['archived_at']),
        lastUsed: toStringOrNull(json['last_used']),
        slicerFilament: toStringOrNull(json['slicer_filament']),
        slicerFilamentName: toStringOrNull(json['slicer_filament_name']),
        kProfiles: parseJsonList(json['k_profiles'], SpoolKProfile.fromJson),
      );

  /// Spoolman returns loose object (passthrough) — field names vary, so read
  /// tolerantly from several possible keys.
  factory Spool.fromSpoolman(Map<String, dynamic> json) {
    final filament = json['filament'];
    final fil = filament is Map<String, dynamic> ? filament : const {};
    return Spool(
      id: toIntOrNull(json['id']) ?? -1,
      material: toStringOrNull(json['material']) ??
          toStringOrNull(fil['material']) ??
          toStringOrNull(json['filament_type']) ??
          'Unknown',
      subtype: toStringOrNull(json['subtype']),
      colorName: toStringOrNull(json['color_name']) ?? toStringOrNull(fil['name']),
      rgba: toStringOrNull(json['rgba']) ?? toStringOrNull(fil['color_hex']),
      brand: toStringOrNull(json['brand']) ?? toStringOrNull((fil['vendor'] as Map?)?['name']),
      labelWeight: toIntOrNull(json['label_weight']) ??
          toIntOrNull(json['initial_weight']) ??
          toIntOrNull(fil['weight']) ??
          0,
      weightUsed: toDoubleOrNull(json['weight_used']) ?? toDoubleOrNull(json['used_weight']) ?? 0,
      // Spoolman has no such column: the backend derives the baseline from its
      // `used_weight` vs `remaining_weight` pair and hands it over under the
      // native name (`routes/_spoolman_helpers.py::_map_spoolman_spool`).
      weightUsedBaseline: toDoubleOrNull(json['weight_used_baseline']) ?? 0,
      costPerKg: toDoubleOrNull(json['cost_per_kg']) ?? toDoubleOrNull(fil['price']),
      lowStockThresholdPct: toIntOrNull(json['low_stock_threshold_pct']),
      storageLocation: toStringOrNull(json['storage_location']) ?? toStringOrNull(json['location']),
      category: toStringOrNull(json['category']),
      note: toStringOrNull(json['note']) ?? toStringOrNull(json['comment']),
      tagUid: toStringOrNull(json['tag_uid']),
      trayUuid: toStringOrNull(json['tray_uuid']),
      archivedAt: toStringOrNull(json['archived_at']) ?? toStringOrNull(json['archived']),
      lastUsed: toStringOrNull(json['last_used']),
    );
  }

  final int id;
  final String material;
  final String? subtype;
  final String? colorName;

  /// Raw color for swatch (e.g. hex8 `RRGGBBAA` or `#RRGGBB`).
  final String? rgba;

  /// Additional color stops (gradient), comma-separated hex — multi-color filament.
  final String? extraColors;

  /// Visual effect (e.g. silk/glow) — `effect_type`.
  final String? effectType;
  final String? brand;

  /// Full spool weight per label [g] (filament net, without core).
  final int labelWeight;

  /// Used filament [g].
  final double weightUsed;

  /// Where the resettable consumption counter starts from [g]. Stamped equal to
  /// [weightUsed] by the reset action, which is why resetting the counter does
  /// not give the spool its remaining weight back.
  final double weightUsedBaseline;

  /// Empty spool/core weight [g] (`core_weight`).
  final int coreWeight;

  /// Catalog entry ID if selected from list (`core_weight_catalog_id`).
  final int? coreWeightCatalogId;

  /// Last weight scale reading [g] gross (`last_scale_weight`).
  final int? lastScaleWeight;
  final double? costPerKg;
  final int? lowStockThresholdPct;
  final String? storageLocation;
  final String? category;
  final String? note;
  final int? nozzleTempMin;
  final int? nozzleTempMax;
  final String? tagUid;

  /// The other half of the RFID identity. The server matches a slot to a spool
  /// on `tray_uuid` first and falls back to `tag_uid`, because only the UUID
  /// survives a re-spool (`GET /inventory/spools/by-tag`,
  /// `backend/app/api/routes/inventory.py`).
  final String? trayUuid;

  final String? archivedAt;
  final String? lastUsed;

  /// Slicer filament-preset name this spool maps to (e.g. "Bambu PLA Basic
  /// @BBL X2D"). Drives "owned filament" filtering in the slice modal. Native
  /// backend only — Spoolman has no equivalent.
  /// Slicer filament preset id/code (`slicer_filament`) — the print profile the
  /// spool is added with; pairs with [slicerFilamentName] (human-readable).
  final String? slicerFilament;
  final String? slicerFilamentName;
  final List<SpoolKProfile> kProfiles;

  /// Remaining filament [g] (clamps to 0).
  double get remainingWeight {
    final r = labelWeight - weightUsed;
    return r < 0 ? 0 : r;
  }

  /// Filament consumed since the counter was last reset [g].
  ///
  /// The resettable counter, not lifetime use: `weight_used` keeps climbing
  /// while the reset action moves [weightUsedBaseline] up to meet it. It is
  /// therefore independent of [remainingWeight] — resetting this to zero leaves
  /// the spool as empty as it was, which is the whole point of the split
  /// (server issue #1390).
  double get consumedWeight {
    final c = weightUsed - weightUsedBaseline;
    return c < 0 ? 0 : c;
  }

  /// Remaining filament fraction (0..1); null if label weight unknown.
  double? get remainingFraction {
    if (labelWeight <= 0) return null;
    final f = remainingWeight / labelWeight;
    return f.clamp(0.0, 1.0);
  }

  bool get isArchived => archivedAt != null && archivedAt!.isNotEmpty;

  /// Whether below low-stock threshold (default 10% if server doesn't provide).
  bool get isLowStock {
    final frac = remainingFraction;
    if (frac == null) return false;
    final thresholdPct = lowStockThresholdPct ?? 10;
    return frac * 100 <= thresholdPct;
  }

  /// Display name for list: brand + material + (subtype).
  String get displayName {
    final parts = <String>[?brand, material, ?subtype];
    return parts.join(' ');
  }

  /// Whether a free-text search matches this spool. An empty query matches
  /// everything.
  ///
  /// Lives on the model because more than one screen searches spools, and a
  /// second spelling of "what counts as a match" is how the same word starts
  /// finding different things in two places.
  bool matchesSearch(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    for (final field in [material, subtype, brand, colorName, storageLocation, category]) {
      if (field != null && field.toLowerCase().contains(q)) return true;
    }
    return false;
  }
}

/// Editable spool field set for saving (create/update) — backend-agnostic.
/// UI fills draft, source translates to proper body shape
/// (`SpoolCreate`/`SpoolUpdate` native, `SpoolmanInventory*` for Spoolman).
/// Fields unknown to a backend (low-stock threshold, category, nozzle temps)
/// simply don't go into its JSON.
class SpoolDraft {
  const SpoolDraft({
    required this.material,
    this.subtype,
    this.brand,
    this.colorName,
    this.rgba,
    this.extraColors,
    this.effectType,
    this.labelWeight,
    this.weightUsed,
    this.coreWeight,
    this.coreWeightCatalogId,
    this.lastScaleWeight,
    this.costPerKg,
    this.lowStockThresholdPct,
    this.storageLocation,
    this.category,
    this.nozzleTempMin,
    this.nozzleTempMax,
    this.slicerFilament,
    this.slicerFilamentName,
    this.note,
  });

  /// Draft from existing spool — for edit form prefill.
  factory SpoolDraft.fromSpool(Spool s) => SpoolDraft(
        material: s.material,
        subtype: s.subtype,
        brand: s.brand,
        colorName: s.colorName,
        rgba: s.rgba,
        extraColors: s.extraColors,
        effectType: s.effectType,
        labelWeight: s.labelWeight,
        weightUsed: s.weightUsed,
        coreWeight: s.coreWeight,
        coreWeightCatalogId: s.coreWeightCatalogId,
        lastScaleWeight: s.lastScaleWeight,
        costPerKg: s.costPerKg,
        lowStockThresholdPct: s.lowStockThresholdPct,
        storageLocation: s.storageLocation,
        category: s.category,
        nozzleTempMin: s.nozzleTempMin,
        nozzleTempMax: s.nozzleTempMax,
        slicerFilament: s.slicerFilament,
        slicerFilamentName: s.slicerFilamentName,
        note: s.note,
      );

  final String material;
  final String? subtype;
  final String? brand;
  final String? colorName;
  final String? rgba;
  final String? extraColors;
  final String? effectType;
  final int? labelWeight;
  final double? weightUsed;
  final int? coreWeight;
  final int? coreWeightCatalogId;
  final int? lastScaleWeight;
  final double? costPerKg;
  final int? lowStockThresholdPct;
  final String? storageLocation;
  final String? category;
  final int? nozzleTempMin;
  final int? nozzleTempMax;
  final String? slicerFilament;
  final String? slicerFilamentName;
  final String? note;

  /// Body for native `/inventory/spools` (`SpoolCreate`/`SpoolUpdate` same fields;
  /// server ignores missing). Skip null to avoid zeroing untouched fields on PATCH.
  Map<String, dynamic> toNativeJson() => {
        'material': material,
        if (subtype != null) 'subtype': subtype,
        if (brand != null) 'brand': brand,
        if (colorName != null) 'color_name': colorName,
        if (rgba != null) 'rgba': rgba,
        if (extraColors != null) 'extra_colors': extraColors,
        if (effectType != null) 'effect_type': effectType,
        if (labelWeight != null) 'label_weight': labelWeight,
        if (weightUsed != null) 'weight_used': weightUsed,
        if (coreWeight != null) 'core_weight': coreWeight,
        if (coreWeightCatalogId != null)
          'core_weight_catalog_id': coreWeightCatalogId,
        if (lastScaleWeight != null) 'last_scale_weight': lastScaleWeight,
        if (costPerKg != null) 'cost_per_kg': costPerKg,
        if (lowStockThresholdPct != null)
          'low_stock_threshold_pct': lowStockThresholdPct,
        if (storageLocation != null) 'storage_location': storageLocation,
        if (category != null) 'category': category,
        if (nozzleTempMin != null) 'nozzle_temp_min': nozzleTempMin,
        if (nozzleTempMax != null) 'nozzle_temp_max': nozzleTempMax,
        if (slicerFilament != null) 'slicer_filament': slicerFilament,
        if (slicerFilamentName != null)
          'slicer_filament_name': slicerFilamentName,
        if (note != null) 'note': note,
      };

  /// Body for Spoolman (`SpoolmanInventoryCreate`/`Update`) — narrower field set;
  /// fields unsupported by Spoolman are skipped.
  Map<String, dynamic> toSpoolmanJson() => {
        if (material.isNotEmpty) 'material': material,
        if (subtype != null) 'subtype': subtype,
        if (brand != null) 'brand': brand,
        if (colorName != null) 'color_name': colorName,
        if (rgba != null) 'rgba': rgba,
        if (labelWeight != null) 'label_weight': labelWeight,
        if (weightUsed != null) 'weight_used': weightUsed,
        if (coreWeight != null) 'core_weight': coreWeight,
        if (costPerKg != null) 'cost_per_kg': costPerKg,
        if (storageLocation != null) 'storage_location': storageLocation,
        if (note != null) 'note': note,
      };
}

/// Spool assignment to AMS slot — normalized from native
/// `SpoolAssignmentResponse` and Spoolman `SpoolmanSlotAssignmentEnriched`.
class SpoolAssignment {
  const SpoolAssignment({
    required this.spoolId,
    required this.printerId,
    required this.amsId,
    required this.trayId,
    this.printerName,
    this.amsLabel,
  });

  factory SpoolAssignment.fromNative(Map<String, dynamic> json) =>
      SpoolAssignment(
        spoolId: toIntOrNull(json['spool_id']) ?? -1,
        printerId: toIntOrNull(json['printer_id']) ?? -1,
        amsId: toIntOrNull(json['ams_id']) ?? -1,
        trayId: toIntOrNull(json['tray_id']) ?? -1,
        printerName: toStringOrNull(json['printer_name']),
        amsLabel: toStringOrNull(json['ams_label']),
      );

  factory SpoolAssignment.fromSpoolman(Map<String, dynamic> json) =>
      SpoolAssignment(
        spoolId: toIntOrNull(json['spoolman_spool_id']) ?? -1,
        printerId: toIntOrNull(json['printer_id']) ?? -1,
        amsId: toIntOrNull(json['ams_id']) ?? -1,
        trayId: toIntOrNull(json['tray_id']) ?? -1,
        printerName: toStringOrNull(json['printer_name']),
        amsLabel: toStringOrNull(json['ams_label']),
      );

  final int spoolId;
  final int printerId;
  final int amsId;
  final int trayId;
  final String? printerName;
  final String? amsLabel;

  /// External spool (external holder), NOT in AMS unit — inventory backend
  /// marks as `ams_id` 254/255. Then "slot" is extruder (dual-head printers),
  /// not "AMS·tray".
  bool get isExternalSpool => amsId >= 254;

  /// Extruder fed by external spool (X2D/H2D). NOTE: inventory backend has
  /// BOTH external spools with `ams_id=255` — distinguished by `tray_id`.
  /// Verified live on X2D from raw assignments:
  /// TPU `ams=255, tray=0` sits physically LEFT, PLA `ams=255, tray=1` RIGHT.
  /// (Different from MQTT `vtTray` 254/255 from dashboard — don't confuse.)
  /// Convention as in `printer_status`: 1 = left, 0 = right;
  /// null for regular AMS slot or unexpected `tray_id`.
  int? get extruder {
    if (!isExternalSpool) return null;
    return switch (trayId) {
      0 => 1, // tray 0 → left extruder
      1 => 0, // tray 1 → right extruder
      _ => null,
    };
  }

  /// AMS slot label for UI: `ams_label` from server or `AMS{ams}·{tray+1}`.
  /// For external spool, label built in UI (needs l10n) — see `assignmentSlotLabel`.
  String get slotLabel =>
      amsLabel ?? 'AMS$amsId · ${trayId + 1}';
}

/// Spool-to-slot assignment request (`SpoolAssignmentCreate`). Physical key
/// is triple (printer, AMS unit, tray); for external spool `amsId=255`,
/// `trayId` distinguishes extruder (0=left, 1=right — see [SpoolAssignment]).
class SpoolAssignmentDraft {
  const SpoolAssignmentDraft({
    required this.spoolId,
    required this.printerId,
    required this.amsId,
    required this.trayId,
  });

  final int spoolId;
  final int printerId;
  final int amsId;
  final int trayId;

  Map<String, dynamic> toNativeJson() => {
        'spool_id': spoolId,
        'printer_id': printerId,
        'ams_id': amsId,
        'tray_id': trayId,
      };
}

/// Spool usage history entry (`SpoolUsageHistoryResponse`).
class SpoolUsageEntry {
  const SpoolUsageEntry({
    required this.id,
    this.printName,
    this.weightUsed = 0,
    this.percentUsed = 0,
    this.status,
    this.cost,
    this.createdAt,
  });

  factory SpoolUsageEntry.fromNative(Map<String, dynamic> json) =>
      SpoolUsageEntry(
        id: toIntOrNull(json['id']) ?? -1,
        printName: toStringOrNull(json['print_name']),
        weightUsed: toDoubleOrNull(json['weight_used']) ?? 0,
        percentUsed: toIntOrNull(json['percent_used']) ?? 0,
        status: toStringOrNull(json['status']),
        cost: toDoubleOrNull(json['cost']),
        createdAt: dateTimeFromJson(json['created_at']),
      );

  final int id;
  final String? printName;
  final double weightUsed;
  final int percentUsed;
  final String? status;
  final double? cost;
  final DateTime? createdAt;
}

/// K-calibration profile pinned to spool (`SpoolKProfileResponse`) — show
/// only summary in details.
class SpoolKProfile {
  const SpoolKProfile({
    required this.id,
    this.name,
    this.kValue,
    this.nozzleDiameter,
  });

  factory SpoolKProfile.fromJson(Map<String, dynamic> json) => SpoolKProfile(
        id: toIntOrNull(json['id']) ?? -1,
        name: toStringOrNull(json['name']),
        kValue: toDoubleOrNull(json['k_value']),
        nozzleDiameter: toStringOrNull(json['nozzle_diameter']),
      );

  final int id;
  final String? name;
  final double? kValue;
  final String? nozzleDiameter;
}

