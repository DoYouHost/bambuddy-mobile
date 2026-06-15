import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'server_profile.dart';

/// Persystencja profilu serwera w SharedPreferences.
/// URL i tryb auth nie są sekretami — sekrety trzyma CredentialsStore.
class SettingsRepository {
  SettingsRepository(this._prefs);

  static const _profileKey = 'server_profile';
  static const _bgMonitoringKey = 'bg_monitoring_enabled';

  final SharedPreferences _prefs;

  ServerProfile? loadProfile() {
    final raw = _prefs.getString(_profileKey);
    if (raw == null) return null;
    try {
      return ServerProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      // Uszkodzony wpis traktujemy jak brak profilu — użytkownik
      // przejdzie ponownie przez setup zamiast oglądać crash.
      return null;
    }
  }

  Future<void> saveProfile(ServerProfile profile) =>
      _prefs.setString(_profileKey, jsonEncode(profile.toJson()));

  Future<void> clearProfile() => _prefs.remove(_profileKey);

  /// Czy monitorować wydruki w tle (foreground service). Domyślnie włączone —
  /// priorytetem jest niezawodność powiadomień; użytkownik może wyłączyć, by
  /// pozbyć się stałego powiadomienia kosztem łapania startu wydruku w tle.
  bool loadBgMonitoringEnabled() => _prefs.getBool(_bgMonitoringKey) ?? true;

  Future<void> saveBgMonitoringEnabled(bool enabled) =>
      _prefs.setBool(_bgMonitoringKey, enabled);
}
