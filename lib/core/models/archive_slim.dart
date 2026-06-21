/// Lekki wpis archiwum z `GET /archives/slim` — jeden wiersz na zdarzenie
/// wydruku, bez ciężkich pól (miniatury, gcode itd.). Używany do liczenia
/// bogatych statystyk po stronie klienta (heatmapa, rekordy, rozkład kolorów,
/// zużycie w czasie, histogramy), których nie daje `/archives/stats`.
///
/// Parsowanie defensywne: wszystko poza [status]/[createdAt] bywa null.
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

  /// Szacowany czas druku (z gcode/slicera).
  final int? printTimeSeconds;

  /// Rzeczywisty czas druku (zmierzony). Bazowy dla histogramu czasu trwania.
  final int? actualTimeSeconds;

  final double? filamentUsedGrams;
  final String? filamentType;

  /// Kolor filamentu — `#RRGGBB`, czasem wielokolorowy: `#AABBCC,#112233`.
  final String? filamentColor;

  final DateTime? startedAt;
  final DateTime? completedAt;
  final double? cost;
  final int quantity;

  /// Wydruk udany = status „completed" (reszta to porażki/inne).
  bool get isSuccess => status.toLowerCase() == 'completed';

  /// Czas do statystyk: preferuj rzeczywisty, w razie braku szacowany.
  int? get effectiveSeconds => actualTimeSeconds ?? printTimeSeconds;

  /// Dominujący kolor (pierwszy segment przy filamencie wielokolorowym),
  /// znormalizowany do `#RRGGBB` w wielkich literach. Null, gdy brak/niepoprawny.
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
