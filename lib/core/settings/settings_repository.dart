import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/swatch_code.dart';
import '../notifications/notification_prefs.dart';
import 'print_options.dart';
import 'server_profile.dart';
import 'sign_in_reason.dart';

/// Persistence of server profile in SharedPreferences.
/// URL and auth mode are not secrets — CredentialsStore holds those.
class SettingsRepository {
  SettingsRepository(this._prefs);

  static const _profileKey = 'server_profile';
  static const _signInRequiredKey = 'sign_in_required';
  static const _signInReasonKey = 'sign_in_reason';
  static const _bgMonitoringKey = 'bg_monitoring_enabled';
  static const _notifPrefsKey = 'notification_prefs';
  static const _maintNotifiedKey = 'maintenance_notified_due_ids';
  static const _maintDirtyKey = 'maintenance_dirty';
  static const _inventoryBackendKey = 'inventory_backend';
  static const _swatchCodesKey = 'swatch_codes';
  static const _printOptionsKey = 'print_options';
  static const _diagnosticsSessionKey = 'diagnostics_session';
  static const _clock24hKey = 'clock_24h';
  static const _wearRelayClaimKey = 'wear_relay_claim';
  static const _no3mfDismissedKey = 'archive_no3mf_dismissed';

  final SharedPreferences _prefs;

  /// This repository again, after re-reading what another isolate wrote.
  ///
  /// `SharedPreferences` gives every isolate its own in-memory copy of the file,
  /// so a handle keeps serving the snapshot it was opened with: the maintenance
  /// item the service marked done, the sign-in it saw rejected, the clock the
  /// app has just written down — none of it is visible on the other side until
  /// this. Every read of a value the *other* isolate writes goes through here,
  /// and the ones that forgot it each cost a debugging session.
  Future<SettingsRepository> reloaded() async {
    await _prefs.reload();
    return this;
  }

  /// The same thing where no handle is open yet — a background isolate that was
  /// woken by a notification action rather than started by the app.
  static Future<SettingsRepository> opened() async =>
      SettingsRepository(await SharedPreferences.getInstance()).reloaded();

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

  /// Whether the remembered login can no longer restore a session on its own,
  /// so the user has to sign in by hand again. Set from wherever that is
  /// noticed — including the background isolate, which is why it lives in prefs
  /// rather than in memory — and read by the dashboard to warn on the next app
  /// open.
  bool loadSignInRequired() => _prefs.getBool(_signInRequiredKey) ?? false;

  /// Which of the two situations it was. Meaningless while
  /// [loadSignInRequired] is false; a missing or unknown value degrades to
  /// [SignInReason.credentialsRejected], the case that existed before the
  /// reason was recorded at all.
  SignInReason loadSignInReason() =>
      SignInReason.fromName(_prefs.getString(_signInReasonKey));

  Future<void> saveSignInRequired(
    bool required, {
    SignInReason reason = SignInReason.credentialsRejected,
  }) async {
    if (!required) {
      await _prefs.remove(_signInRequiredKey);
      await _prefs.remove(_signInReasonKey);
      return;
    }
    await _prefs.setBool(_signInRequiredKey, true);
    await _prefs.setString(_signInReasonKey, reason.name);
  }

  /// Whether to monitor prints in the background (foreground service). Enabled by default —
  /// notification reliability is the priority; user can disable to remove the persistent
  /// notification at the cost of potentially missing print start events in the background.
  bool loadBgMonitoringEnabled() => _prefs.getBool(_bgMonitoringKey) ?? true;

  Future<void> saveBgMonitoringEnabled(bool enabled) =>
      _prefs.setBool(_bgMonitoringKey, enabled);

  /// The platform's 12/24-hour switch, as the UI last saw it. It travels through
  /// preferences because the only isolate that can read the switch is the one
  /// with a view attached: the foreground service gets a bare engine, where the
  /// setting is not missing but *wrong* — a default `false` that spelled every
  /// notification ETA in AM/PM on a 24-hour phone.
  ///
  /// Null until an install has run a version that writes it, and null is not
  /// "12-hour": `DateTimeFormats` then follows the locale's own convention.
  bool? loadUse24HourClock() => _prefs.getBool(_clock24hKey);

  Future<void> saveUse24HourClock(bool use24Hour) =>
      _prefs.setBool(_clock24hKey, use24Hour);

  /// Whether the user has waved off the "archived without its 3MF" nudge.
  ///
  /// One-shot and permanent, like the web's own `localStorage` flag: fixing the
  /// cause stops new fallbacks anyway, so there is nothing to re-warn about.
  /// Absent — which is every install that upgrades into this — reads as not
  /// dismissed, so the banner appears once and only if the server says there is
  /// something to say.
  bool loadNo3mfDismissed() => _prefs.getBool(_no3mfDismissedKey) ?? false;

  Future<void> saveNo3mfDismissed() => _prefs.setBool(_no3mfDismissedKey, true);

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

  Future<void> saveNotifiedMaintenanceDueIds(Set<int> ids) => _prefs
      .setStringList(_maintNotifiedKey, [for (final id in ids) id.toString()]);

  /// Whether maintenance state changed outside the UI (action "Mark Done" from notification,
  /// handled in background isolate) and needs screen refresh. Signal between callback isolate
  /// and UI — UI must call `reload()` on prefs before reading, as the write came from another isolate.
  bool maintenanceDirty() => _prefs.getBool(_maintDirtyKey) ?? false;

  Future<void> setMaintenanceDirty(bool dirty) => dirty
      ? _prefs.setBool(_maintDirtyKey, true)
      : _prefs.remove(_maintDirtyKey);

  /// Filament inventory backend: `native` (default) or `spoolman`. Stored as enum name;
  /// unknown/corrupted → native.
  String loadInventoryBackend() =>
      _prefs.getString(_inventoryBackendKey) ?? 'native';

  Future<void> saveInventoryBackend(String backend) =>
      _prefs.setString(_inventoryBackendKey, backend);

  /// Print toggles the user last sent with a new job — what the print form
  /// starts from, so a preference like "no flow calibration" survives instead of
  /// being re-clicked per print. Missing/corrupted → [PrintOptions.initial].
  PrintOptions loadPrintOptions() =>
      PrintOptions.decode(_prefs.getString(_printOptionsKey));

  Future<void> savePrintOptions(PrintOptions options) =>
      _prefs.setString(_printOptionsKey, options.encode());

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

  /// Session id of a bug-report recording in progress, or null when none is.
  /// The id doubles as the on/off flag — the background isolate reads it to
  /// decide whether to write its own log stream, and a separate bool would be
  /// a second thing to keep in sync across isolates. Callers in the isolate
  /// must `reload()` first: the write came from the UI isolate.
  String? loadDiagnosticsSession() => _prefs.getString(_diagnosticsSessionKey);

  Future<void> saveDiagnosticsSession(String? session) => session == null
      ? _prefs.remove(_diagnosticsSessionKey)
      : _prefs.setString(_diagnosticsSessionKey, session);

  /// Which watch-relay responder is listening, as `<pid>:<nonce>` —
  /// `WearRelayClaim` has the why for both halves. Also read natively, as
  /// `flutter.wear_relay_claim` in `FlutterSharedPreferences`
  /// (`WearRelayListenerService.kt`, which only reads the pid): rename it here
  /// and the phone stops waking up for the watch, with nothing to show for it.
  /// `wear_relay_native_contract_test` is what notices.
  String? loadWearRelayClaim() => _prefs.getString(_wearRelayClaimKey);

  Future<void> saveWearRelayClaim(String? claim) => claim == null
      ? _prefs.remove(_wearRelayClaimKey)
      : _prefs.setString(_wearRelayClaimKey, claim);
}
