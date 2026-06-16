import 'package:json_annotation/json_annotation.dart';

part 'smart_plug.g.dart';

/// Konfiguracja smart gniazdka z `GET /smart-plugs/` i
/// `GET /smart-plugs/by-printer/{id}` (SmartPlugResponse). Parsujemy tylko to,
/// czego używa UI dashboardu — przypisanie do drukarki, widoczność i ostatni
/// znany stan; resztę (MQTT/REST/HA/harmonogramy) serwer trzyma u siebie.
/// Defensywnie: poza `id` wszystko nullable, nieznane klucze ignorowane.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class SmartPlug {
  const SmartPlug({
    required this.id,
    this.name,
    this.plugType,
    this.printerId,
    this.enabled,
    this.lastState,
    this.showOnPrinterCard,
    this.showInSwitchbar,
  });

  factory SmartPlug.fromJson(Map<String, dynamic> json) =>
      _$SmartPlugFromJson(json);

  final int id;

  final String? name;

  /// `tasmota` | `homeassistant` | `mqtt` | `rest` — surowo, nie enumujemy.
  final String? plugType;

  /// Drukarka, do której gniazdko jest przypisane (null = nieprzypisane).
  @JsonKey(fromJson: _toIntOrNull)
  final int? printerId;

  final bool? enabled;

  /// Ostatni znany stan z serwera (np. „ON"/„OFF") — szybki fallback, zanim
  /// dociągniemy żywy [SmartPlugStatus].
  final String? lastState;

  /// Czy gniazdko ma się pokazać na karcie drukarki (preferencja serwera).
  final bool? showOnPrinterCard;

  final bool? showInSwitchbar;

  /// Czy gniazdko nadaje się do pokazania na karcie drukarki: włączone i
  /// oznaczone do wyświetlenia (oba pola domyślnie traktujemy jako „tak”,
  /// gdy serwer ich nie poda).
  bool get visibleOnCard =>
      (enabled ?? true) && (showOnPrinterCard ?? true);

  /// Stan z konfiguracji (fallback, gdy nie ma jeszcze żywego statusu).
  bool? get lastIsOn => switch (lastState?.toUpperCase()) {
        'ON' || 'TRUE' || '1' => true,
        'OFF' || 'FALSE' || '0' => false,
        _ => null,
      };
}

/// Żywy status gniazdka z `GET /smart-plugs/{id}/status` (SmartPlugStatus):
/// stan on/off, osiągalność i pomiar energii. To stąd bierzemy moc na żywo.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class SmartPlugStatus {
  const SmartPlugStatus({
    this.state,
    this.reachable,
    this.deviceName,
    this.energy,
  });

  factory SmartPlugStatus.fromJson(Map<String, dynamic> json) =>
      _$SmartPlugStatusFromJson(json);

  /// Surowy stan z serwera (np. „ON"/„OFF"); null gdy nieznany/nieosiągalne.
  final String? state;

  /// Czy gniazdko odpowiada (na false moc/stan są nieaktualne).
  final bool? reachable;

  final String? deviceName;

  final SmartPlugEnergy? energy;

  bool get isReachable => reachable ?? true;

  bool? get isOn => switch (state?.toUpperCase()) {
        'ON' || 'TRUE' || '1' => true,
        'OFF' || 'FALSE' || '0' => false,
        _ => null,
      };

  /// Bieżąca moc czynna w watach — null gdy gniazdko nie mierzy lub nieosiągalne.
  double? get powerW => isReachable ? energy?.power : null;
}

/// Pomiar energii z gniazdka (SmartPlugEnergy). Wszystko opcjonalne — nie każdy
/// typ gniazdka raportuje każdy parametr.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class SmartPlugEnergy {
  const SmartPlugEnergy({
    this.power,
    this.voltage,
    this.current,
    this.today,
    this.yesterday,
    this.total,
  });

  factory SmartPlugEnergy.fromJson(Map<String, dynamic> json) =>
      _$SmartPlugEnergyFromJson(json);

  /// Moc czynna [W].
  @JsonKey(fromJson: _toDoubleOrNull)
  final double? power;

  /// Napięcie [V].
  @JsonKey(fromJson: _toDoubleOrNull)
  final double? voltage;

  /// Prąd [A].
  @JsonKey(fromJson: _toDoubleOrNull)
  final double? current;

  /// Energia dziś [kWh].
  @JsonKey(fromJson: _toDoubleOrNull)
  final double? today;

  /// Energia wczoraj [kWh].
  @JsonKey(fromJson: _toDoubleOrNull)
  final double? yesterday;

  /// Energia łącznie (licznik) [kWh].
  @JsonKey(fromJson: _toDoubleOrNull)
  final double? total;
}

double? _toDoubleOrNull(dynamic value) => switch (value) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };

int? _toIntOrNull(dynamic value) => switch (value) {
      num n => n.toInt(),
      String s => int.tryParse(s),
      _ => null,
    };
