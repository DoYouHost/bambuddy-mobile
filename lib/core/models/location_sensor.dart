import 'json_utils.dart';

/// What a bound sensor is measuring, decided from Home Assistant's
/// `device_class` the same way the server decides it
/// (`_CATEGORY_BY_DEVICE_CLASS`, `backend/app/api/routes/location_ha_sensors.py`).
///
/// The server allows one sensor per category per location, so these are also
/// the most a location can show at once. Anything else — a CO2 meter, a door
/// contact — falls to [other] and is shown by its own name instead of an icon
/// the reader would have to guess at.
enum LocationSensorCategory {
  temperature('temperature'),
  humidity('humidity'),
  battery('battery'),
  other('');

  const LocationSensorCategory(this.deviceClass);

  final String deviceClass;

  static LocationSensorCategory fromDeviceClass(String? value) {
    if (value == null || value.isEmpty) return other;
    for (final category in values) {
      if (category != other && category.deviceClass == value) return category;
    }
    return other;
  }
}

/// One Home Assistant sensor bound to a storage location — the row
/// `GET /location-ha-sensors/` lists (`LocationHASensorResponse`, server #2827).
///
/// Slim on purpose: the app never edits a binding (creating one needs
/// `smart_plugs:create`, which no API key can hold, and picking the entity
/// needs the HA URL and token that are configured server-side), so the only
/// thing the listing is read for is *which* locations have something to show.
class LocationSensorBinding {
  const LocationSensorBinding({
    required this.id,
    required this.locationId,
    required this.showOnCard,
  });

  factory LocationSensorBinding.fromJson(Map<String, dynamic> json) =>
      LocationSensorBinding(
        id: toInt(json['id']),
        locationId: toInt(json['location_id']),
        showOnCard: toBoolOrFalse(json['show_on_card']),
      );

  final int id;
  final int locationId;

  /// Whether the reading is meant to be shown next to the location's spools.
  /// The readings route filters on it too; carried here so the "does this
  /// location have anything to show" question is answered without a second
  /// request.
  final bool showOnCard;
}

/// One sensor's live state, as `GET /location-ha-sensors/by-location/{id}/readings`
/// reports it (`LocationHASensorReading`).
class LocationSensorReading {
  const LocationSensorReading({
    required this.id,
    required this.name,
    required this.entityId,
    required this.numeric,
    this.deviceClass,
    this.unit,
    this.state,
    this.value,
    this.alerting = false,
    this.reachable = true,
    this.lastChanged,
  });

  factory LocationSensorReading.fromJson(Map<String, dynamic> json) =>
      LocationSensorReading(
        id: toInt(json['id']),
        name: toStringOrNull(json['name']) ?? '',
        entityId: toStringOrNull(json['entity_id']) ?? '',
        numeric: toStringOrNull(json['kind']) == 'numeric',
        deviceClass: toStringOrNull(json['device_class']),
        unit: toStringOrNull(json['unit']),
        state: toStringOrNull(json['state']),
        value: toDoubleOrNull(json['value']),
        alerting: toBoolOrFalse(json['alerting']),
        // Absent means the poller has not reached this sensor yet, which the
        // server reports as `false` — so the tolerant default here is the one
        // that does not invent freshness for a payload that omitted the field.
        reachable: toBoolOrFalse(json['reachable']),
        lastChanged: dateTimeFromJson(json['last_changed']),
      );

  final int id;

  /// The name the binding was given, not the Home Assistant friendly name.
  final String name;

  final String entityId;

  /// `kind` = `numeric` (a `sensor.*` with a parsed [value]) rather than
  /// `binary` (a `binary_sensor.*`, whose whole reading is [state]).
  final bool numeric;

  final String? deviceClass;

  /// Home Assistant's own unit string (`°C`, `%`, `V`) — never translated:
  /// what the entity reports is what the reading is in.
  final String? unit;

  /// Raw Home Assistant state: `on`/`off` for a binary sensor, the number as
  /// text for a numeric one. Null when the entity is unavailable and has never
  /// been read.
  final String? state;

  final double? value;

  /// The reading is outside the thresholds the binding carries. Only ever true
  /// for a reading the poller could actually take.
  final bool alerting;

  /// Whether the last poll reached the entity. False also covers "not polled
  /// yet", in which case [state] is the last value that was persisted.
  final bool reachable;

  final DateTime? lastChanged;

  LocationSensorCategory get category =>
      LocationSensorCategory.fromDeviceClass(deviceClass);

  bool get isOn => state == 'on';

  /// The number and its unit, e.g. `21.5°C` or `43%`. Null for a binary sensor
  /// or a numeric one with nothing readable — both of which are shown by their
  /// state instead.
  ///
  /// One decimal only where there is one: a hygrometer reporting `43.0` says
  /// nothing more than `43`, and the pills sit two or three to a row.
  String? get formattedValue {
    final v = value;
    if (!numeric || v == null) return null;
    final rounded = (v * 10).roundToDouble() / 10;
    final digits = rounded == rounded.roundToDouble() ? 0 : 1;
    return '${rounded.toStringAsFixed(digits)}${unit ?? ''}';
  }
}
