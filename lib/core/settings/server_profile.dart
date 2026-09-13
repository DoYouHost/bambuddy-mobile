import 'package:app_util/app_util.dart' as util;

import '../demo/demo_config.dart';

/// Server authentication mode. EVERY code path that touches auth
/// (headers, token minting, re-login) MUST branch on this enum —
/// auth-disabled servers are fully supported configurations.
enum AuthMode { none, jwt, apiKey }

/// Connection profile for a bambuddy server. Does not contain secrets —
/// those live in [CredentialsStore] (secure storage).
class ServerProfile {
  const ServerProfile({
    required this.baseUrl,
    required this.authMode,
    this.label,
  });

  factory ServerProfile.fromJson(Map<String, dynamic> json) => ServerProfile(
    baseUrl: json['baseUrl'] as String,
    authMode: AuthMode.values.asNameMap()[json['authMode']] ?? AuthMode.none,
    label: json['label'] as String?,
  );

  /// E.g., `http://192.168.1.10:8000` — without trailing `/` or `/api/v1`.
  final String baseUrl;
  final AuthMode authMode;
  final String? label;

  /// Demo profile (store-review mode): all data comes from the in-process
  /// `DemoBackend`, no network traffic. See [DemoConfig].
  bool get isDemo => DemoConfig.isDemoUrl(baseUrl);

  /// Shortest thing that still identifies this server, for UI with no room for
  /// the whole URL (the watch). The label when there is one — it is what the
  /// user chose to call it — the host otherwise, since two servers on a LAN
  /// usually differ only there.
  String get displayName {
    final named = label;
    if (named != null && named.trim().isNotEmpty) return named.trim();
    final host = Uri.tryParse(baseUrl)?.host;
    return host == null || host.isEmpty ? baseUrl : host;
  }

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'authMode': authMode.name,
    if (label != null) 'label': label,
  };

  /// Normalizes raw user input: adds `http://` if no scheme, strips trailing `/`
  /// and a trailing `/api/v1`, which is what a URL copied out of the API docs
  /// ends in and what every endpoint path already starts with.
  ///
  /// The `http://` default is intentional: local/self-hosted servers are often
  /// plain http, and a public https server redirects the probe so the caller
  /// adopts the reached URL via `baseUrlFromReached`. See setup flow.
  static String normalizeBaseUrl(String raw) =>
      util.normalizeBaseUrl(raw, defaultScheme: 'http', apiPath: '/api/v1');
}
