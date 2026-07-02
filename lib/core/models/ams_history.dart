/// AMS sensor history (temperature + humidity) for a single AMS unit.
///
/// Backend: `GET /ams-history/{printerId}/{amsId}?hours=1..168` (see reference
/// bambuddy `backend/app/api/routes/ams_history.py`). Points are recorded about
/// every 5 minutes while the printer is connected, so a window can be sparse.
class AmsHistoryPoint {
  const AmsHistoryPoint({
    required this.recordedAt,
    this.humidity,
    this.temperature,
  });

  /// Sample time, normalized to local time for chart display.
  final DateTime recordedAt;

  /// Relative humidity in percent; null when the unit doesn't report it.
  final double? humidity;

  /// Temperature in °C; null when the unit doesn't report it.
  final double? temperature;

  static AmsHistoryPoint fromJson(Map<String, dynamic> json) => AmsHistoryPoint(
        recordedAt: DateTime.tryParse('${json['recorded_at']}')?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0),
        humidity: _toDouble(json['humidity']),
        temperature: _toDouble(json['temperature']),
      );
}

/// Full history response: the series plus server-computed min/max/avg per metric.
class AmsHistory {
  const AmsHistory({
    required this.printerId,
    required this.amsId,
    required this.points,
    this.minHumidity,
    this.maxHumidity,
    this.avgHumidity,
    this.minTemperature,
    this.maxTemperature,
    this.avgTemperature,
  });

  final int printerId;
  final int amsId;
  final List<AmsHistoryPoint> points;
  final double? minHumidity;
  final double? maxHumidity;
  final double? avgHumidity;
  final double? minTemperature;
  final double? maxTemperature;
  final double? avgTemperature;

  bool get isEmpty => points.isEmpty;

  static AmsHistory fromJson(Map<String, dynamic> json) {
    final raw = json['data'];
    final points = <AmsHistoryPoint>[
      if (raw is List)
        for (final e in raw)
          if (e is Map<String, dynamic>) AmsHistoryPoint.fromJson(e),
    ];
    return AmsHistory(
      printerId: (json['printer_id'] as num?)?.toInt() ?? 0,
      amsId: (json['ams_id'] as num?)?.toInt() ?? 0,
      points: points,
      minHumidity: _toDouble(json['min_humidity']),
      maxHumidity: _toDouble(json['max_humidity']),
      avgHumidity: _toDouble(json['avg_humidity']),
      minTemperature: _toDouble(json['min_temperature']),
      maxTemperature: _toDouble(json['max_temperature']),
      avgTemperature: _toDouble(json['avg_temperature']),
    );
  }
}

double? _toDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}
