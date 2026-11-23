import 'package:app_util/app_util.dart';
import 'package:flutter/services.dart';

import 'edge_access.dart';

/// Where the cookies of the sign-in WebView can be read (#72).
///
/// A sign-in through Cloudflare Access leaves `CF_Authorization` in the
/// WebView's cookie store, and the cookie is HttpOnly by default, so the page
/// cannot read it with `document.cookie`. Android's `CookieManager` can, and it
/// is a native call.
abstract interface class EdgeCookieJar {
  /// The values of every cookie [name] that the WebView would send to [url],
  /// in the order it sends them; empty when it holds none. There can be several
  /// (one for the host, an older one for its parent domain), and the first is
  /// the oldest, not the best.
  Future<List<String>> cookies(Uri url, String name);

  /// Forgets every cookie the WebView holds: a signed-out server must not be
  /// signed back in by the cookie it left.
  Future<void> clear();
}

/// The Android `CookieManager`, through the app's own channel.
class WebViewEdgeCookieJar implements EdgeCookieJar {
  const WebViewEdgeCookieJar([
    this._query = const PlatformQuery(
      MethodChannel('page.codeberg.morganmlgman.bambuddy/edge_cookie'),
    ),
  ]);

  final PlatformQuery _query;

  @override
  Future<List<String>> cookies(Uri url, String name) async {
    final header = await _query.ask<String>(
      'cookies',
      fallback: '',
      arguments: {'url': url.toString()},
    );
    return cookieValues(header, name);
  }

  @override
  Future<void> clear() => _query.tell('clear');
}

/// Every value of [name] in a `Cookie` header, `a=1; b=2` as the WebView
/// returns it. Splits on the first `=` only (a value may hold more), and
/// matches the whole name: `CF_Authorization` is not `X_CF_Authorization`. An
/// empty value is not one.
List<String> cookieValues(String? header, String name) {
  if (header == null) return const [];
  return [
    for (final pair in header.split(';'))
      if (pair.indexOf('=') case final at when at >= 0)
        if (pair.substring(0, at).trim() == name)
          if (pair.substring(at + 1).trim() case final value
              when value.isNotEmpty)
            value,
  ];
}

/// What a sign-in WebView does with the pages it reaches: after each one, asks
/// the cookie store whether Access has signed it in, and says so once there is a
/// session that has not ended.
class EdgeSignIn {
  EdgeSignIn({required this.host, required this.jar, required this.now});

  /// The host the session is for: the one Access is in front of.
  final String host;
  final EdgeCookieJar jar;
  final DateTime Function() now;

  /// The session the WebView holds for [host], or null while it holds none, or
  /// only cookies that are not a usable token, or have already ended. Of several
  /// the first good one counts: the cookie store lists an older cookie first, and
  /// an old one left by a previous sign-in must not hide the new.
  Future<BrowserSession?> check() async {
    final values = await jar.cookies(
      Uri(scheme: 'https', host: host),
      BrowserSession.cookieName,
    );
    final at = now();
    for (final value in values) {
      final session = BrowserSession.fromCookie(host: host, cookie: value);
      if (session != null && !session.isExpired(at)) return session;
    }
    return null;
  }
}
