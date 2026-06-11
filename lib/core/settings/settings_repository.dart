import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'server_profile.dart';

/// Persystencja profilu serwera w SharedPreferences.
/// URL i tryb auth nie są sekretami — sekrety trzyma CredentialsStore.
class SettingsRepository {
  SettingsRepository(this._prefs);

  static const _profileKey = 'server_profile';

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
}
