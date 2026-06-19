import 'dart:convert';

/// Typy lokalnych powiadomień, jakie potrafi wykryć [PrintMonitor] z ramek WS
/// `printer_status`. Świadomie pomijamy zdarzenia kolejki / funkcje serwera
/// bambuddy (quiet hours, digest, providers) — tu liczy się tylko to, co da się
/// wywnioskować lokalnie ze statusu drukarki.
enum NotifEvent {
  printStarted,
  printFinished,
  printFailed,
  firstLayer,
  milestones,
  plateNotEmpty,
  printerOffline,
  printerError,
  lowFilament,
  amsHumidity,
  bedCooled,
}

/// Wybór użytkownika: które zdarzenia mają puszczać powiadomienie i z jakimi
/// progami. Serializowana do JEDNEGO stringa w SharedPreferences, by isolate tła
/// (który czyta `SharedPreferences.getInstance()` od zera) mógł ją odczytać tak
/// samo jak UI. Parsowanie tolerancyjne — nieznana nazwa zdarzenia jest
/// pomijana (kompatybilność wprzód: starsza apka nie wywróci się na nowym enumie).
class NotificationPrefs {
  const NotificationPrefs({
    required this.enabled,
    this.bedCooledTemp = defaultBedCooledTemp,
    this.amsHumidityThreshold = defaultAmsHumidity,
    this.lowFilamentThreshold = defaultLowFilament,
  });

  /// Zbiór zdarzeń, dla których puszczamy powiadomienie.
  final Set<NotifEvent> enabled;

  /// Próg „stół wystygł": alert, gdy temperatura stołu spadnie poniżej (°C).
  final int bedCooledTemp;

  /// Próg „wysoka wilgotność AMS": alert, gdy wilgotność przekroczy (%).
  final int amsHumidityThreshold;

  /// Próg „niski filament": alert, gdy pozostała ilość spadnie poniżej (%).
  final int lowFilamentThreshold;

  static const int defaultBedCooledTemp = 35;
  static const int defaultAmsHumidity = 60;
  static const int defaultLowFilament = 10;

  /// Domyślnie włączone tylko zdarzenia „akcyjne"; reszta cicho (OFF), by nie
  /// zalewać użytkownika — sam je włączy w ustawieniach.
  static const Set<NotifEvent> _defaultEnabled = {
    NotifEvent.printFinished,
    NotifEvent.printFailed,
    NotifEvent.plateNotEmpty,
    NotifEvent.printerError,
  };

  static const NotificationPrefs defaults =
      NotificationPrefs(enabled: _defaultEnabled);

  bool isOn(NotifEvent e) => enabled.contains(e);

  NotificationPrefs copyWith({
    Set<NotifEvent>? enabled,
    int? bedCooledTemp,
    int? amsHumidityThreshold,
    int? lowFilamentThreshold,
  }) =>
      NotificationPrefs(
        enabled: enabled ?? this.enabled,
        bedCooledTemp: bedCooledTemp ?? this.bedCooledTemp,
        amsHumidityThreshold: amsHumidityThreshold ?? this.amsHumidityThreshold,
        lowFilamentThreshold: lowFilamentThreshold ?? this.lowFilamentThreshold,
      );

  /// Włącza/wyłącza pojedyncze zdarzenie i zwraca nowy obiekt.
  NotificationPrefs withEvent(NotifEvent e, bool on) {
    final next = {...enabled};
    if (on) {
      next.add(e);
    } else {
      next.remove(e);
    }
    return copyWith(enabled: next);
  }

  Map<String, dynamic> toJson() => {
        'enabled': [for (final e in enabled) e.name],
        'bedCooledTemp': bedCooledTemp,
        'amsHumidityThreshold': amsHumidityThreshold,
        'lowFilamentThreshold': lowFilamentThreshold,
      };

  String encode() => jsonEncode(toJson());

  factory NotificationPrefs.fromJson(Map<String, dynamic> json) {
    final rawEnabled = json['enabled'];
    final names = rawEnabled is List
        ? rawEnabled.map((e) => e.toString()).toSet()
        : const <String>{};
    final enabled = {
      for (final e in NotifEvent.values)
        if (names.contains(e.name)) e,
    };
    return NotificationPrefs(
      enabled: enabled,
      bedCooledTemp: _asInt(json['bedCooledTemp'], defaultBedCooledTemp),
      amsHumidityThreshold:
          _asInt(json['amsHumidityThreshold'], defaultAmsHumidity),
      lowFilamentThreshold:
          _asInt(json['lowFilamentThreshold'], defaultLowFilament),
    );
  }

  /// Dekoduje z surowego stringa SharedPreferences; uszkodzony/pusty → domyślne.
  factory NotificationPrefs.decode(String? raw) {
    if (raw == null || raw.isEmpty) return defaults;
    try {
      return NotificationPrefs.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return defaults;
    }
  }

  static int _asInt(dynamic v, int fallback) => switch (v) {
        num n => n.toInt(),
        String s => int.tryParse(s) ?? fallback,
        _ => fallback,
      };
}
