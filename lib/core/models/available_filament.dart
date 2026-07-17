/// One filament currently loaded on some active printer of a given model,
/// from `GET /printers/available-filaments?model=&location=`. Used to populate
/// the per-slot override dropdown in model-based (`Any <model>`) assignment:
/// the scheduler will match the queued job against these instead of the file's
/// original 3MF filaments.
class AvailableFilament {
  const AvailableFilament({
    required this.type,
    required this.color,
    this.traySubBrands,
    this.trayInfoIdx,
    this.extruderId,
  });

  factory AvailableFilament.fromJson(Map<String, dynamic> json) =>
      AvailableFilament(
        type: (json['type'] as String?) ?? '',
        color: (json['color'] as String?) ?? '',
        traySubBrands: json['tray_sub_brands'] as String?,
        trayInfoIdx: json['tray_info_idx'] as String?,
        extruderId: (json['extruder_id'] as num?)?.toInt(),
      );

  static List<AvailableFilament> parseList(List<dynamic> list) {
    final out = <AvailableFilament>[];
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final f = AvailableFilament.fromJson(item);
      if (f.type.isEmpty) continue;
      out.add(f);
    }
    return out;
  }

  /// Material type, e.g. "PLA", "TPU 95A" (raw, original case).
  final String type;

  /// Color `#RRGGBB` or `#RRGGBBAA`.
  final String color;

  /// Sub-brand label, e.g. "Bambu TPU 95A" — preferred display over [type].
  final String? traySubBrands;

  /// Bambu SKU code, e.g. "GFA01".
  final String? trayInfoIdx;

  /// Extruder id on dual-nozzle printers (H2D); null on single-nozzle.
  final int? extruderId;

  /// Display label — sub-brand if known, else the raw type.
  String get label =>
      (traySubBrands != null && traySubBrands!.isNotEmpty) ? traySubBrands! : type;
}
