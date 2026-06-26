/// Lightweight archive entry from `GET /archives/slim` — one row per print event,
/// without heavy fields (thumbnails, gcode, etc.). Used for client-side rich
/// statistics (heatmaps, records, color distribution, consumption over time,
/// histograms) not provided by `/archives/stats`.
///
/// Defensive parsing: all fields except [status]/[createdAt] may be null.
class ArchiveSlim {
  const ArchiveSlim({
    required this.status,
    required this.createdAt,
    this.printerId,
    this.printName,
    this.printTimeSeconds,
    this.actualTimeSeconds,
    this.filamentUsedGrams,
    this.filamentType,
    this.filamentColor,
    this.startedAt,
    this.completedAt,
    this.cost,
    this.quantity = 1,
  });

  factory ArchiveSlim.fromJson(Map<String, dynamic> json) => ArchiveSlim(
        status: (json['status'] as String?) ?? 'unknown',
        createdAt: _date(json['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        printerId: _int(json['printer_id']),
        printName: json['print_name'] as String?,
        printTimeSeconds: _int(json['print_time_seconds']),
        actualTimeSeconds: _int(json['actual_time_seconds']),
        filamentUsedGrams: _double(json['filament_used_grams']),
        filamentType: json['filament_type'] as String?,
        filamentColor: json['filament_color'] as String?,
        startedAt: _date(json['started_at']),
        completedAt: _date(json['completed_at']),
        cost: _double(json['cost']),
        quantity: _int(json['quantity']) ?? 1,
      );

  final String status;
  final DateTime createdAt;
  final int? printerId;
  final String? printName;

  /// Estimated print time from gcode/slicer.
  final int? printTimeSeconds;

  /// Actual print time (measured). Base for duration histogram.
  final int? actualTimeSeconds;

  final double? filamentUsedGrams;
  final String? filamentType;

  /// Filament color — `#RRGGBB`, sometimes multi-color: `#AABBCC,#112233`.
  final String? filamentColor;

  final DateTime? startedAt;
  final DateTime? completedAt;
  final double? cost;
  final int quantity;

  /// Print success = status "completed" (others are failures/other).
  bool get isSuccess => status.toLowerCase() == 'completed';

  /// Time for stats: prefer actual, fall back to estimated.
  int? get effectiveSeconds => actualTimeSeconds ?? printTimeSeconds;

  /// Dominant color (first segment for multi-color filament), normalized to
  /// `#RRGGBB` uppercase. Null if missing or invalid.
  String? get primaryColor {
    final raw = filamentColor?.trim();
    if (raw == null || raw.isEmpty) return null;
    final first = raw.split(',').first.trim();
    final hex = first.startsWith('#') ? first.substring(1) : first;
    if (hex.length < 6) return null;
    return '#${hex.substring(0, 6).toUpperCase()}';
  }
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is String) return int.tryParse(v);
  return null;
}

double? _double(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

DateTime? _date(Object? v) {
  if (v is! String || v.isEmpty) return null;
  return DateTime.tryParse(v);
}
