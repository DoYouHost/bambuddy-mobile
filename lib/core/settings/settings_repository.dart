import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/swatch_code.dart';
import '../notifications/notification_prefs.dart';
import 'server_profile.dart';

/// Persistence of server profile in SharedPreferences.
/// URL and auth mode are not secrets — CredentialsStore holds those.
class SettingsRepository {
  SettingsRepository(this._prefs);

  static const _profileKey = 'server_profile';
  static const _bgMonitoringKey = 'bg_monitoring_enabled';
  static const _notifPrefsKey = 'notification_prefs';
  static const _maintNotifiedKey = 'maintenance_notified_due_ids';
  static const _maintDirtyKey = 'maintenance_dirty';
  static const _inventoryBackendKey = 'inventory_backend';
  static const _swatchCodesKey = 'swatch_codes';

  final SharedPreferences _prefs;

  ServerProfile? loadProfile() {
    final raw = _prefs.getString(_profileKey);
    if (raw == null) return null;
    try {
      return ServerProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      // Treat corrupted entry as no profile — user will go through
      // setup again instead of crashing.
      return null;
    }
  }

  Future<void> saveProfile(ServerProfile profile) =>
      _prefs.setString(_profileKey, jsonEncode(profile.toJson()));

  Future<void> clearProfile() => _prefs.remove(_profileKey);

  /// Whether to monitor prints in the background (foreground service). Enabled by default —
  /// notification reliability is the priority; user can disable to remove the persistent
  /// notification at the cost of potentially missing print start events in the background.
  bool loadBgMonitoringEnabled() => _prefs.getBool(_bgMonitoringKey) ?? true;

  Future<void> saveBgMonitoringEnabled(bool enabled) =>
      _prefs.setBool(_bgMonitoringKey, enabled);

  /// Notification preferences (which events, what thresholds). Stored as a single
  /// JSON string so the background isolate parses it the same way as the UI.
  /// Corrupted/missing → defaults.
  NotificationPrefs loadNotificationPrefs() =>
      NotificationPrefs.decode(_prefs.getString(_notifPrefsKey));

  Future<void> saveNotificationPrefs(NotificationPrefs prefs) =>
      _prefs.setString(_notifPrefsKey, prefs.encode());

  /// Set of maintenance task IDs for which we've already sent an "overdue" alert.
  /// Dedup for periodic background monitor: survives isolate restarts (no re-spam),
  /// and items stop being due after perform and are removed from here (re-arm).
  /// Corrupted entry → empty set.
  Set<int> loadNotifiedMaintenanceDueIds() {
    final raw = _prefs.getStringList(_maintNotifiedKey);
    if (raw == null) return <int>{};
    return {for (final s in raw) int.tryParse(s) ?? -1}..remove(-1);
  }

  Future<void> saveNotifiedMaintenanceDueIds(Set<int> ids) => _prefs.setStringList(
        _maintNotifiedKey,
        [for (final id in ids) id.toString()],
      );

  /// Whether maintenance state changed outside the UI (action "Mark Done" from notification,
  /// handled in background isolate) and needs screen refresh. Signal between callback isolate
  /// and UI — UI must call `reload()` on prefs before reading, as the write came from another isolate.
  bool maintenanceDirty() => _prefs.getBool(_maintDirtyKey) ?? false;

  Future<void> setMaintenanceDirty(bool dirty) =>
      dirty ? _prefs.setBool(_maintDirtyKey, true) : _prefs.remove(_maintDirtyKey);

  /// Filament inventory backend: `native` (default) or `spoolman`. Stored as enum name;
  /// unknown/corrupted → native.
  String loadInventoryBackend() =>
      _prefs.getString(_inventoryBackendKey) ?? 'native';

  Future<void> saveInventoryBackend(String backend) =>
      _prefs.setString(_inventoryBackendKey, backend);

  /// Swatch codes (filament definitions with assigned codes) — local data stored as a single
  /// JSON string (list of objects). Missing/corrupted → empty list. See [SwatchCode].
  List<SwatchCode> loadSwatchCodes() {
    final raw = _prefs.getString(_swatchCodesKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <SwatchCode>[];
      for (final e in decoded) {
        if (e is Map<String, dynamic>) {
          try {
            out.add(SwatchCode.fromJson(e));
          } on Object {
            continue;
          }
        }
      }
      return out;
    } on Object {
      return const [];
    }
  }

  Future<void> saveSwatchCodes(List<SwatchCode> codes) => _prefs.setString(
        _swatchCodesKey,
        jsonEncode([for (final c in codes) c.toJson()]),
      );
}
