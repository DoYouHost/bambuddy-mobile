import 'dart:convert';
import 'dart:io';

import 'client_cert.dart';
import 'custom_ca.dart';
import 'edge_access.dart';
import 'edge_http_client.dart';

/// Makes every `HttpClient` this isolate creates from now on trust [ca] on top
/// of the system roots and present [cert] to a server that asks for one; both
/// null takes that back. `HttpOverrides.global` is per isolate, so each isolate
/// that talks to the server calls this before its first request, with both
/// halves, so one context is built per change.
///
/// [edge] (#72) is not TLS but rides the same override, because one global
/// decides what every client of the isolate is: it adds the Cloudflare Access
/// credential to the requests for its host.
///
/// shortcut: a client created before the call keeps what it was created with
/// — `Image.network` shares one for the life of the isolate, so a change made
/// while the app runs reaches images after a restart.
void useTls(CustomCa? ca, ClientCert? cert, [EdgeAccess? edge]) {
  final ours = HttpOverrides.current is _TlsOverrides;
  if (ca != null || cert != null || edge != null) {
    if (!ours) _before = HttpOverrides.current;
    HttpOverrides.global = _TlsOverrides(ca, cert, edge);
  } else if (ours) {
    HttpOverrides.global = _before;
    _before = null;
  }
}

/// The Cloudflare Access credential this isolate presents now, null when it
/// presents none. Read by what has to tell "no credential" from "one that was
/// refused" after the fact.
EdgeAccess? presentedEdgeAccess() => switch (HttpOverrides.current) {
  _TlsOverrides(:final _edge) => _edge,
  _ => null,
};

/// The headers Cloudflare Access wants on a request to [url], for the stacks
/// that do not go through `dart:io` and so never meet [EdgeHttpClient]: the
/// video player (ExoPlayer) and the G-code viewer's WebView. Empty when nothing
/// is presented, or it is not for [url]'s host, or [url] is not https.
///
/// shortcut: ExoPlayer follows a redirect with every header it was given, which
/// `EdgeRequest` prevents for `dart:io`. For the timelapse player that is
/// closed another way: `checkEdgeAccess` asks with the Dart client first, and
/// the player is not started for a request Cloudflare Access would redirect. In
/// the WebView a `fetch` carries custom headers across an origin only after a
/// CORS preflight, which Cloudflare's team domain does not grant. A redirect
/// from bambuddy itself would still be followed by the player; it sends none on
/// these routes (its source and a live server).
Map<String, String> edgeHeadersFor(Uri url) {
  final access = presentedEdgeAccess();
  return access != null && access.appliesTo(url) ? access.headers : const {};
}

/// What was installed before ours — the test binding has overrides of its own
/// — so taking ours back hands it back rather than leaving none.
HttpOverrides? _before;

class _TlsOverrides extends HttpOverrides {
  _TlsOverrides(CustomCa? ca, ClientCert? cert, this._edge)
    : _context = SecurityContext(withTrustedRoots: true) {
    if (ca != null) _context.setTrustedCertificatesBytes(utf8.encode(ca.pem));
    try {
      cert?.applyTo(_context);
    } on Object {
      // A stored certificate that no longer loads must not stop `main` before
      // the first frame: connect without it, and settings can remove it.
    }
  }

  final SecurityContext _context;
  final EdgeAccess? _edge;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context ?? _context);
    final edge = _edge;
    return edge == null ? client : EdgeHttpClient(client, edge);
  }
}
