import 'dart:convert';
import 'dart:io';

import 'client_cert.dart';
import 'custom_ca.dart';

/// Makes every `HttpClient` this isolate creates from now on trust [ca] on top
/// of the system roots and present [cert] to a server that asks for one; both
/// null takes that back. `HttpOverrides.global` is per isolate, so each isolate
/// that talks to the server calls this before its first request, with both
/// halves, so one context is built per change.
///
/// shortcut: a client created before the call keeps what it was created with
/// — `Image.network` shares one for the life of the isolate, so a change made
/// while the app runs reaches images after a restart.
void useTls(CustomCa? ca, ClientCert? cert) {
  final ours = HttpOverrides.current is _TlsOverrides;
  if (ca != null || cert != null) {
    if (!ours) _before = HttpOverrides.current;
    HttpOverrides.global = _TlsOverrides(ca, cert);
  } else if (ours) {
    HttpOverrides.global = _before;
    _before = null;
  }
}

/// What was installed before ours — the test binding has overrides of its own
/// — so taking ours back hands it back rather than leaving none.
HttpOverrides? _before;

class _TlsOverrides extends HttpOverrides {
  _TlsOverrides(CustomCa? ca, ClientCert? cert)
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

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context ?? _context);
}
