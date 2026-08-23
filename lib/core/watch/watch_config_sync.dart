// Private fields are named constructor params (can't be initializing formals,
// which may not start with `_`), so assignment happens in the initializer list.
// ignore_for_file: prefer_initializing_formals

import 'package:watch_connectivity/watch_connectivity.dart';

import '../auth/credentials_store.dart';
import '../settings/server_profile.dart';
import '../settings/settings_repository.dart';

/// Decoded phone→watch handoff: the server profile plus whichever secret backs
/// its auth mode. Secrets travel over the Wear Data Layer (encrypted bridge
/// between paired devices) so the watch never needs the credentials typed in.
class WatchConfig {
  const WatchConfig({
    required this.profile,
    this.apiKey,
    this.jwt,
    this.username,
    this.password,
  });

  final ServerProfile profile;
  final String? apiKey;
  final String? jwt;
  final String? username;
  final String? password;
}

/// Shape of the application-context map exchanged over the Data Layer. Keeping
/// it in one place so the phone encoder and watch decoder can't drift.
class WatchConfigCodec {
  static const int version = 1;

  static const _kVersion = 'v';
  static const _kBaseUrl = 'baseUrl';
  static const _kAuthMode = 'authMode';
  static const _kLabel = 'label';
  static const _kApiKey = 'apiKey';
  static const _kJwt = 'jwt';
  static const _kUsername = 'username';
  static const _kPassword = 'password';

  /// Build the context map. Only non-null keys are included — the Data Layer
  /// rejects null values in the map.
  static Map<String, dynamic> encode({
    required ServerProfile profile,
    String? apiKey,
    String? jwt,
    ({String username, String password})? login,
  }) =>
      <String, dynamic>{
        _kVersion: version,
        _kBaseUrl: profile.baseUrl,
        _kAuthMode: profile.authMode.name,
        if (profile.label != null) _kLabel: profile.label,
        if (apiKey != null && apiKey.isNotEmpty) _kApiKey: apiKey,
        if (jwt != null && jwt.isNotEmpty) _kJwt: jwt,
        if (login != null) ...{
          _kUsername: login.username,
          _kPassword: login.password,
        },
      };

  /// Parse an incoming context. Returns null for empty/foreign/malformed maps
  /// (a bare `{}` is delivered before the phone has ever pushed) so the watch
  /// falls back to its own setup screen instead of crashing.
  static WatchConfig? decode(Map<String, dynamic> map) {
    final baseUrl = map[_kBaseUrl];
    if (baseUrl is! String || baseUrl.isEmpty) return null;
    final mode = AuthMode.values.asNameMap()[map[_kAuthMode]];
    if (mode == null) return null;
    return WatchConfig(
      profile: ServerProfile(
        baseUrl: baseUrl,
        authMode: mode,
        label: map[_kLabel] as String?,
      ),
      apiKey: map[_kApiKey] as String?,
      jwt: map[_kJwt] as String?,
      username: map[_kUsername] as String?,
      password: map[_kPassword] as String?,
    );
  }
}

/// Phone→watch config handoff over the Wear Data Layer. The same class serves
/// both ends: the phone [push]es its active profile; the watch [apply]s an
/// incoming one into its own stores. Uses `updateApplicationContext` (a latched,
/// last-value-wins channel) so a watch launched later still receives the config.
class WatchConfigSync {
  /// [settings] is only needed on the watch side ([apply]); the phone leaves it null.
  WatchConfigSync({
    required WatchConnectivity watch,
    required CredentialsStore credentials,
    SettingsRepository? settings,
  })  : _watch = watch,
        _credentials = credentials,
        _settings = settings;

  final WatchConnectivity _watch;
  final CredentialsStore _credentials;
  final SettingsRepository? _settings;

  /// PHONE side: push [profile] and its backing secret to the watch. Best-effort
  /// — silently no-ops when no watch is paired/reachable, so it's safe to call
  /// unconditionally on every profile change.
  Future<void> push(ServerProfile profile) async {
    try {
      final map = WatchConfigCodec.encode(
        profile: profile,
        apiKey: profile.authMode == AuthMode.apiKey
            ? await _credentials.readApiKey()
            : null,
        jwt: profile.authMode == AuthMode.jwt
            ? await _credentials.readJwt()
            : null,
        login: profile.authMode == AuthMode.jwt
            ? await _credentials.readRememberedLogin()
            : null,
      );
      await _watch.updateApplicationContext(map);
    } catch (_) {
      // No paired watch / Data Layer unavailable — nothing to do.
    }
  }

  /// WATCH side: persist [config] into this device's own profile + secure
  /// storage. Caller then refreshes `serverProfileProvider` to re-route the UI.
  /// Requires [_settings] (watch entry point provides it).
  Future<void> apply(WatchConfig config) async {
    final settings = _settings;
    if (settings == null) return;
    if (config.apiKey != null) await _credentials.writeApiKey(config.apiKey!);
    if (config.jwt != null) await _credentials.writeJwt(config.jwt!);
    if (config.username != null && config.password != null) {
      await _credentials.writeRememberedLogin(
          config.username!, config.password!);
    }
    await settings.saveProfile(config.profile);
  }

  /// WATCH side: contexts already latched before the listener attached (cold
  /// start after the phone pushed while the watch app was closed).
  Future<List<WatchConfig>> pendingConfigs() async {
    try {
      final raw = await _watch.receivedApplicationContexts;
      return raw
          .map(WatchConfigCodec.decode)
          .whereType<WatchConfig>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// WATCH side: adopt the newest latched config, if the phone has pushed one.
  /// Returns whether anything was applied, so the caller knows to refresh its
  /// profile — and, on the setup screen, whether to tell the user we came back
  /// empty-handed.
  Future<bool> adoptLatestPending() async {
    final configs = await pendingConfigs();
    if (configs.isEmpty) return false;
    await apply(configs.last);
    return true;
  }

  /// WATCH side: live stream of incoming configs (phone pushes while the watch
  /// app is open).
  Stream<WatchConfig> configStream() =>
      _watch.contextStream.map(WatchConfigCodec.decode).where((c) => c != null).cast();
}
