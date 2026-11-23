import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/jwt.dart';
import '../diagnostics/auth_probe.dart';
import '../models/value_equality.dart';
import '../settings/settings_repository.dart';

/// What the app shows Cloudflare Access in front of the server (#72): a service
/// token, or the `CF_Authorization` cookie of a browser sign-in. Cloudflare
/// answers a request without one by redirecting to its sign-in page, so every
/// request to the server carries it, from every isolate.
///
/// Bound to the [host] it was entered for, so [EdgeHttpClient] never offers it to
/// another one (MakerWorld thumbnails), and to `https`, so a plain-http request
/// to the same host (the app allows cleartext for LAN servers) never carries it.
/// A secret: it lives in [EdgeAccessStore], never in SharedPreferences.
sealed class EdgeAccess with ValueEquality {
  EdgeAccess({required String host})
    : assert(host.isNotEmpty, 'an empty host matches nothing'),
      host = host.toLowerCase();

  /// Lower-case host the credential belongs to, without port or scheme.
  final String host;

  /// The headers a request to [host] carries.
  Map<String, String> get headers;

  /// Whether [url] is a request this credential is for. Host names are
  /// case-insensitive; the port is not compared, as Cloudflare Access is
  /// configured per host name.
  bool appliesTo(Uri url) =>
      url.isScheme('https') && url.host.toLowerCase() == host;

  Map<String, dynamic> toJson();

  /// Null for a kind this version does not know, so a downgrade reads as none
  /// rather than throwing at start.
  static EdgeAccess? fromJson(Map<String, dynamic> json) {
    final host = json['host'] as String?;
    if (host == null || host.isEmpty) return null;
    switch (json['kind']) {
      case ServiceToken.kind:
        return ServiceToken(
          host: host,
          clientId: json['clientId'] as String,
          clientSecret: json['clientSecret'] as String,
        );
      case BrowserSession.kind:
        return BrowserSession(
          host: host,
          cookie: json['cookie'] as String,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            json['expiresAt'] as int,
            isUtc: true,
          ),
        );
    }
    return null;
  }
}

/// Cloudflare Access service token: two headers, no expiry the app has to watch.
final class ServiceToken extends EdgeAccess {
  ServiceToken({
    required super.host,
    required this.clientId,
    required this.clientSecret,
  });

  static const kind = 'service_token';

  final String clientId;
  final String clientSecret;

  @override
  Map<String, String> get headers => {
    'CF-Access-Client-Id': clientId,
    'CF-Access-Client-Secret': clientSecret,
  };

  @override
  Map<String, dynamic> toJson() => {
    'kind': kind,
    'host': host,
    'clientId': clientId,
    'clientSecret': clientSecret,
  };

  @override
  List<Object?> get props => [host, clientId, clientSecret];
}

/// The cookie a browser sign-in left. It ends at [expiresAt] (the token's own
/// `exp`) and only a person can get the next one.
final class BrowserSession extends EdgeAccess {
  BrowserSession({
    required super.host,
    required this.cookie,
    required this.expiresAt,
  });

  static const kind = 'browser_session';

  /// The session a sign-in left, with the end the cookie itself names: Access
  /// signs it as a JWT, and its `exp` is the only place that end is written.
  /// Null for a cookie that is not one, so a value that cannot be told to expire
  /// is not kept as if it never would.
  static BrowserSession? fromCookie({
    required String host,
    required String cookie,
  }) {
    final expiresAt = jwtExpiry(cookie);
    if (host.isEmpty || expiresAt == null) return null;
    return BrowserSession(host: host, cookie: cookie, expiresAt: expiresAt);
  }

  /// Whether the cookie has ended at [now]. The caller passes the clock, so a
  /// test pins it.
  bool isExpired(DateTime now) => !now.isBefore(expiresAt);

  /// Cloudflare's name for it; the server side reads nothing else.
  static const cookieName = 'CF_Authorization';

  final String cookie;
  final DateTime expiresAt;

  @override
  Map<String, String> get headers => {'Cookie': '$cookieName=$cookie'};

  @override
  Map<String, dynamic> toJson() => {
    'kind': kind,
    'host': host,
    'cookie': cookie,
    'expiresAt': expiresAt.millisecondsSinceEpoch,
  };

  @override
  List<Object?> get props => [host, cookie, expiresAt];
}

/// Secure storage for the one [EdgeAccess], in a namespace of its own: signing
/// out wipes the sign-in secrets with `deleteAll`, and this belongs to the proxy
/// in front of the server, not to the account, as the certificate does.
///
/// Reads answer null rather than throw and writes throw, as in
/// `ClientCertStore`.
class EdgeAccessStore {
  EdgeAccessStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              resetOnError: false,
              storageNamespace: 'edge_access',
            ),
          );

  static const _key = 'edge_access';

  final FlutterSecureStorage _storage;

  Future<EdgeAccess?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      return EdgeAccess.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object catch (error) {
      AuthProbe.credentialUnreadable(_key, error);
      return null;
    }
  }

  Future<void> write(EdgeAccess? access) => access == null
      ? _storage.delete(key: _key)
      : _storage.write(key: _key, value: jsonEncode(access.toJson()));
}

/// The stored credential, read from secure storage only when preferences say
/// there is one: opening the namespace creates its Keystore key, which every
/// install without Cloudflare Access would otherwise pay for before its first
/// frame.
Future<EdgeAccess?> loadEdgeAccess(
  SettingsRepository settings, [
  EdgeAccessStore? store,
]) async =>
    settings.loadHasEdgeAccess() ? (store ?? EdgeAccessStore()).read() : null;
