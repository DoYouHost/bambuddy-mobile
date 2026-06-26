/// Filament inventory models (spools) — domain-normalized, backend-agnostic.
/// App uses native `/inventory/*` (default) but must work with Spoolman
/// (`/spoolman/inventory/*`), which returns different JSON shape. So model is
/// hand-written with tolerant helpers and per-backend factories — UI gets one
/// coherent type, unaware of source.
///
/// Defensive parsing: all except `id`/`material` are nullable, unknown keys
/// ignored, numbers accept int/num/string.
library;

/// Pojedyncza szpula w magazynie. Pola wagowe w gramach.
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
    this.archivedAt,
    this.lastUsed,
    this.slicerFilamentName,
    this.kProfiles = const [],
  });

  /// Native `SpoolResponse` from `GET /inventory/spools`.
  factory Spool.fromNative(Map<String, dynamic> json) => Spool(
        id: _toInt(json['id']) ?? -1,
        material: (json['material'] as String?)?.trim().isNotEmpty == true
            ? json['material'] as String
            : 'Unknown',
        subtype: _str(json['subtype']),
        colorName: _str(json['color_name']),
        rgba: _str(json['rgba']),
        extraColors: _str(json['extra_colors']),
        effectType: _str(json['effect_type']),
        brand: _str(json['brand']),
        labelWeight: _toInt(json['label_weight']) ?? 0,
        weightUsed: _toDouble(json['weight_used']) ?? 0,
        coreWeight: _toInt(json['core_weight']) ?? 250,
        coreWeightCatalogId: _toInt(json['core_weight_catalog_id']),
        lastScaleWeight: _toInt(json['last_scale_weight']),
        costPerKg: _toDouble(json['cost_per_kg']),
        lowStockThresholdPct: _toInt(json['low_stock_threshold_pct']),
        storageLocation: _str(json['storage_location']),
        category: _str(json['category']),
        note: _str(json['note']),
        nozzleTempMin: _toInt(json['nozzle_temp_min']),
        nozzleTempMax: _toInt(json['nozzle_temp_max']),
        tagUid: _str(json['tag_uid']),
        archivedAt: _str(json['archived_at']),
        lastUsed: _str(json['last_used']),
        slicerFilamentName: _str(json['slicer_filament_name']),
        kProfiles: _kProfiles(json['k_profiles']),
      );

  /// Spoolman returns loose object (passthrough) — field names vary, so read
  /// tolerantly from several possible keys.
  factory Spool.fromSpoolman(Map<String, dynamic> json) {
    final filament = json['filament'];
    final fil = filament is Map<String, dynamic> ? filament : const {};
    return Spool(
      id: _toInt(json['id']) ?? -1,
      material: _str(json['material']) ??
          _str(fil['material']) ??
          _str(json['filament_type']) ??
          'Unknown',
      subtype: _str(json['subtype']),
      colorName: _str(json['color_name']) ?? _str(fil['name']),
      rgba: _str(json['rgba']) ?? _str(fil['color_hex']),
      brand: _str(json['brand']) ?? _str((fil['vendor'] as Map?)?['name']),
      labelWeight: _toInt(json['label_weight']) ??
          _toInt(json['initial_weight']) ??
          _toInt(fil['weight']) ??
          0,
      weightUsed: _toDouble(json['weight_used']) ?? _toDouble(json['used_weight']) ?? 0,
      costPerKg: _toDouble(json['cost_per_kg']) ?? _toDouble(fil['price']),
      lowStockThresholdPct: _toInt(json['low_stock_threshold_pct']),
      storageLocation: _str(json['storage_location']) ?? _str(json['location']),
      category: _str(json['category']),
      note: _str(json['note']) ?? _str(json['comment']),
      tagUid: _str(json['tag_uid']),
      archivedAt: _str(json['archived_at']) ?? _str(json['archived']),
      lastUsed: _str(json['last_used']),
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
  final String? archivedAt;
  final String? lastUsed;

  /// Slicer filament-preset name this spool maps to (e.g. "Bambu PLA Basic
  /// @BBL X2D"). Drives "owned filament" filtering in the slice modal. Native
  /// backend only — Spoolman has no equivalent.
  final String? slicerFilamentName;
  final List<SpoolKProfile> kProfiles;

  /// Remaining filament [g] (clamps to 0).
  double get remainingWeight {
    final r = labelWeight - weightUsed;
    return r < 0 ? 0 : r;
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
        spoolId: _toInt(json['spool_id']) ?? -1,
        printerId: _toInt(json['printer_id']) ?? -1,
        amsId: _toInt(json['ams_id']) ?? -1,
        trayId: _toInt(json['tray_id']) ?? -1,
        printerName: _str(json['printer_name']),
        amsLabel: _str(json['ams_label']),
      );

  factory SpoolAssignment.fromSpoolman(Map<String, dynamic> json) =>
      SpoolAssignment(
        spoolId: _toInt(json['spoolman_spool_id']) ?? -1,
        printerId: _toInt(json['printer_id']) ?? -1,
        amsId: _toInt(json['ams_id']) ?? -1,
        trayId: _toInt(json['tray_id']) ?? -1,
        printerName: _str(json['printer_name']),
        amsLabel: _str(json['ams_label']),
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
        id: _toInt(json['id']) ?? -1,
        printName: _str(json['print_name']),
        weightUsed: _toDouble(json['weight_used']) ?? 0,
        percentUsed: _toInt(json['percent_used']) ?? 0,
        status: _str(json['status']),
        cost: _toDouble(json['cost']),
        createdAt: _str(json['created_at']),
      );

  final int id;
  final String? printName;
  final double weightUsed;
  final int percentUsed;
  final String? status;
  final double? cost;
  final String? createdAt;
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
        id: _toInt(json['id']) ?? -1,
        name: _str(json['name']),
        kValue: _toDouble(json['k_value']),
        nozzleDiameter: _str(json['nozzle_diameter']),
      );

  final int id;
  final String? name;
  final double? kValue;
  final String? nozzleDiameter;
}

List<SpoolKProfile> _kProfiles(dynamic raw) {
  if (raw is! List) return const [];
  final out = <SpoolKProfile>[];
  for (final e in raw) {
    if (e is Map<String, dynamic>) {
      try {
        out.add(SpoolKProfile.fromJson(e));
      } on Object {
        continue;
      }
    }
  }
  return out;
}

String? _str(dynamic v) {
  if (v is String) return v.isEmpty ? null : v;
  return null;
}

int? _toInt(dynamic v) => switch (v) {
      int i => i,
      num n => n.toInt(),
      String s => int.tryParse(s),
      _ => null,
    };

double? _toDouble(dynamic v) => switch (v) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };
