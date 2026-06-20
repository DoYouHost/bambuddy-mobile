import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../notifications/notification_prefs.dart';
import 'server_profile.dart';

/// Persystencja profilu serwera w SharedPreferences.
/// URL i tryb auth nie są sekretami — sekrety trzyma CredentialsStore.
class SettingsRepository {
  SettingsRepository(this._prefs);

  static const _profileKey = 'server_profile';
  static const _bgMonitoringKey = 'bg_monitoring_enabled';
  static const _notifPrefsKey = 'notification_prefs';
  static const _maintNotifiedKey = 'maintenance_notified_due_ids';

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

  /// Preferencje powiadomień (które zdarzenia, jakie progi). Trzymane jako jeden
  /// string JSON, by isolate tła odczytał je tak samo jak UI. Brak/uszkodzenie
  /// → wartości domyślne.
  NotificationPrefs loadNotificationPrefs() =>
      NotificationPrefs.decode(_prefs.getString(_notifPrefsKey));

  Future<void> saveNotificationPrefs(NotificationPrefs prefs) =>
      _prefs.setString(_notifPrefsKey, prefs.encode());

  /// Zbiór id czynności konserwacji, dla których już puszczono powiadomienie
  /// „przeterminowane". Dedup periodycznego monitora w tle: przeżywa restart
  /// isolate'u (brak ponownego spamu), a po wykonaniu konserwacji pozycja
  /// przestaje być due i jest stąd usuwana (re-arm). Uszkodzony wpis → pusty zbiór.
  Set<int> loadNotifiedMaintenanceDueIds() {
    final raw = _prefs.getStringList(_maintNotifiedKey);
    if (raw == null) return <int>{};
    return {for (final s in raw) int.tryParse(s) ?? -1}..remove(-1);
  }

  Future<void> saveNotifiedMaintenanceDueIds(Set<int> ids) => _prefs.setStringList(
        _maintNotifiedKey,
        [for (final id in ids) id.toString()],
      );
}
