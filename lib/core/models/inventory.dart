/// Modele magazynu filamentów (szpule) — znormalizowane domenowo, niezależne od
/// backendu. Aplikacja używa natywnego `/inventory/*` (domyślny), ale ma działać
/// też na Spoolman (`/spoolman/inventory/*`), który zwraca inny, luźny kształt
/// JSON. Dlatego model jest pisany ręcznie z tolerancyjnymi helperami i osobnymi
/// fabrykami per backend — UI dostaje jeden spójny typ, nie wie, skąd dane.
///
/// Parsowanie defensywne: poza `id`/`material` wszystko nullable, nieznane klucze
/// ignorowane, liczby tolerują int/num/string.
library;

/// Pojedyncza szpula w magazynie. Pola wagowe w gramach.
class Spool {
  const Spool({
    required this.id,
    required this.material,
    this.subtype,
    this.colorName,
    this.rgba,
    this.brand,
    this.labelWeight = 0,
    this.weightUsed = 0,
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
    this.kProfiles = const [],
  });

  /// Natywny `SpoolResponse` z `GET /inventory/spools`.
  factory Spool.fromNative(Map<String, dynamic> json) => Spool(
        id: _toInt(json['id']) ?? -1,
        material: (json['material'] as String?)?.trim().isNotEmpty == true
            ? json['material'] as String
            : 'Unknown',
        subtype: _str(json['subtype']),
        colorName: _str(json['color_name']),
        rgba: _str(json['rgba']),
        brand: _str(json['brand']),
        labelWeight: _toInt(json['label_weight']) ?? 0,
        weightUsed: _toDouble(json['weight_used']) ?? 0,
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
        kProfiles: _kProfiles(json['k_profiles']),
      );

  /// Spoolman zwraca luźny obiekt (passthrough) — nazwy pól bywają inne, więc
  /// czytamy tolerancyjnie z kilku możliwych kluczy.
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

  /// Surowy zapis koloru do swatcha (np. hex8 `RRGGBBAA` lub `#RRGGBB`).
  final String? rgba;
  final String? brand;

  /// Waga pełnej szpuli wg etykiety [g] (netto filamentu, bez rdzenia).
  final int labelWeight;

  /// Zużyty filament [g].
  final double weightUsed;
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
  final List<SpoolKProfile> kProfiles;

  /// Pozostały filament [g] (nie schodzi poniżej 0).
  double get remainingWeight {
    final r = labelWeight - weightUsed;
    return r < 0 ? 0 : r;
  }

  /// Udział pozostałego filamentu (0..1); null gdy nie znamy wagi etykiety.
  double? get remainingFraction {
    if (labelWeight <= 0) return null;
    final f = remainingWeight / labelWeight;
    return f.clamp(0.0, 1.0);
  }

  bool get isArchived => archivedAt != null && archivedAt!.isNotEmpty;

  /// Czy poniżej progu low-stock (domyślnie 10% gdy serwer nie poda progu).
  bool get isLowStock {
    final frac = remainingFraction;
    if (frac == null) return false;
    final thresholdPct = lowStockThresholdPct ?? 10;
    return frac * 100 <= thresholdPct;
  }

  /// Czytelna nazwa do listy: marka + materiał + (kolor).
  String get displayName {
    final parts = <String>[?brand, material, ?subtype];
    return parts.join(' ');
  }
}

/// Przypisanie szpuli do slotu AMS — znormalizowane z natywnego
/// `SpoolAssignmentResponse` i spoolmanowego `SpoolmanSlotAssignmentEnriched`.
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

  /// Szpula zewnętrzna (na uchwycie zewn.), NIE w jednostce AMS — serwer używa
  /// dla niej id 254/255, tak samo jak na dashboardzie (patrz `printer_status`
  /// `externalSpools`). Wtedy „slotem" jest ekstruder, nie „AMS·tray".
  bool get isExternalSpool => amsId >= 254;

  /// Ekstruder karmiony przez szpulę zewnętrzną: 255 → 1 (lewy), 254 → 0 (prawy).
  /// UWAGA: backend inventory numeruje sloty zewnętrzne ODWROTNIE niż strumień
  /// MQTT `vtTray` (gdzie 254 = lewy — patrz `printer_status.extruderForExternal`).
  /// Zweryfikowane fizycznie na X2D: szpula z `ams_id=255` siedzi w LEWYM
  /// ekstruderze (dashboard pokazuje ją na „L"). null dla zwykłego slotu AMS.
  int? get extruder => switch (amsId) {
        255 => 1,
        254 => 0,
        _ => null,
      };

  /// Etykieta slotu AMS do UI: `ams_label` z serwera albo `AMS{ams}·{tray+1}`.
  /// Dla szpuli zewnętrznej label budujemy w UI (potrzebny l10n) — patrz
  /// `assignmentSlotLabel`.
  String get slotLabel =>
      amsLabel ?? 'AMS$amsId · ${trayId + 1}';
}

/// Wpis historii zużycia szpuli (`SpoolUsageHistoryResponse`).
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

/// Profil kalibracji K przypięty do szpuli (`SpoolKProfileResponse`) — pokazujemy
/// tylko podsumowanie w szczegółach.
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
