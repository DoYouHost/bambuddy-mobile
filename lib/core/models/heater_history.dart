import 'json_utils.dart';

/// One recorded heater sample: the reading and the setpoint that was in force.
///
/// Backend: `GET /printer-sensor-history/{printerId}?hours=1..168&kinds=…`
/// (reference bambuddy `backend/app/api/routes/printer_sensor_history.py`).
/// The server samples every 60 s for connected printers and keeps 30 days by
/// default, so a window right after a printer comes online is still sparse.
class HeaterHistoryPoint {
  const HeaterHistoryPoint({required this.recordedAt, this.value, this.target});

  /// Sample time, normalized to local time for chart display.
  final DateTime recordedAt;

  /// Reading in °C; null when the sensor didn't report one.
  final double? value;

  /// Setpoint in °C at that moment; null when the heater was off or unknown.
  final double? target;

  static HeaterHistoryPoint fromJson(Map<String, dynamic> json) =>
      HeaterHistoryPoint(
        // Sensor rows are stamped naive, so the shared helper is what makes the
        // chart's x-axis land on the hour the reading was actually taken.
        recordedAt:
            dateTimeFromJson(json['recorded_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0),
        value: toDoubleOrNull(json['value']),
        target: toDoubleOrNull(json['target']),
      );
}

/// One sensor's series plus the server-computed min/max/avg over the window.
class HeaterSeries {
  const HeaterSeries({
    required this.sensorKind,
    required this.points,
    this.minValue,
    this.maxValue,
    this.avgValue,
  });

  /// Server key of the sensor: `nozzle`, `nozzle_2`, `bed` or `chamber` — the
  /// same vocabulary the WebSocket frame uses for the live tiles.
  final String sensorKind;
  final List<HeaterHistoryPoint> points;
  final double? minValue;
  final double? maxValue;
  final double? avgValue;

  bool get isEmpty => points.isEmpty;

  static HeaterSeries fromJson(Map<String, dynamic> json) {
    final raw = json['data'];
    return HeaterSeries(
      sensorKind: json['sensor_kind']?.toString() ?? '',
      points: [
        if (raw is List)
          for (final e in raw)
            if (e is Map<String, dynamic>) HeaterHistoryPoint.fromJson(e),
      ],
      minValue: toDoubleOrNull(json['min_value']),
      maxValue: toDoubleOrNull(json['max_value']),
      avgValue: toDoubleOrNull(json['avg_value']),
    );
  }
}

/// Full response: one series per requested sensor kind.
class HeaterHistory {
  const HeaterHistory({required this.printerId, required this.series});

  final int printerId;
  final List<HeaterSeries> series;

  /// The series for [kind], or null when the server sent none for it.
  HeaterSeries? seriesFor(String kind) {
    for (final s in series) {
      if (s.sensorKind == kind) return s;
    }
    return null;
  }

  static HeaterHistory fromJson(Map<String, dynamic> json) {
    final raw = json['series'];
    return HeaterHistory(
      printerId: toInt(json['printer_id']),
      series: [
        if (raw is List)
          for (final e in raw)
            if (e is Map<String, dynamic>) HeaterSeries.fromJson(e),
      ],
    );
  }
}
