import 'dart:convert';
import 'dart:io';

/// A certificate the user imported so the app trusts a server signed by their
/// own certificate authority (#62), on top of the system roots.
///
/// `dart:io` — Dio, the socket, the camera stream, `Image.network` — keeps its
/// own copy of the system roots: it never reads the Android user store and
/// ignores `network_security_config`, so a CA installed on the phone does not
/// reach it. This is how Google says to trust an extra CA, done at run time
/// because the CA differs per user.
class CustomCa {
  const CustomCa({required this.name, required this.pem});

  /// The file it came from, shown on the setup screen.
  final String name;

  /// Only the `CERTIFICATE` blocks of the file, so a private key picked by
  /// mistake is never stored.
  final String pem;

  static final _block = RegExp(
    '-----BEGIN CERTIFICATE-----[A-Za-z0-9+/=\\s]+?-----END CERTIFICATE-----',
  );

  /// Reads a `.pem`, `.crt` or `.cer` file, PEM or DER. Null when it holds no
  /// certificate `dart:io` accepts.
  static CustomCa? parse(String name, List<int> bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    final blocks = _block.allMatches(text).map((m) => m[0]!).toList();
    final pem = blocks.isNotEmpty ? '${blocks.join('\n')}\n' : _derToPem(bytes);
    try {
      SecurityContext(
        withTrustedRoots: false,
      ).setTrustedCertificatesBytes(utf8.encode(pem));
    } on TlsException {
      return null;
    }
    return CustomCa(name: name, pem: pem);
  }

  static String _derToPem(List<int> der) {
    final b64 = base64.encode(der);
    final lines = [
      for (var i = 0; i < b64.length; i += 64)
        b64.substring(i, i + 64 > b64.length ? b64.length : i + 64),
    ];
    return '-----BEGIN CERTIFICATE-----\n${lines.join('\n')}\n'
        '-----END CERTIFICATE-----\n';
  }

  factory CustomCa.fromJson(Map<String, dynamic> json) =>
      CustomCa(name: json['name'] as String, pem: json['pem'] as String);

  Map<String, dynamic> toJson() => {'name': name, 'pem': pem};
}

/// Makes every `HttpClient` this isolate creates from now on trust [ca] as well
/// as the system roots; null takes that back. `HttpOverrides.global` is per
/// isolate, so each isolate that talks to the server calls this before its
/// first request.
///
/// shortcut: a client created before the call keeps the trust it was created
/// with — `Image.network` shares one for the life of the isolate, so a CA
/// changed while the app runs reaches images after a restart.
void trustCustomCa(CustomCa? ca) {
  if (ca != null) {
    HttpOverrides.global = _CustomCaOverrides(ca.pem);
  } else if (HttpOverrides.current is _CustomCaOverrides) {
    // Only ours: the test binding installs overrides of its own.
    HttpOverrides.global = null;
  }
}

class _CustomCaOverrides extends HttpOverrides {
  _CustomCaOverrides(String pem)
    : _context = SecurityContext(withTrustedRoots: true)
        ..setTrustedCertificatesBytes(utf8.encode(pem));

  final SecurityContext _context;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context ?? _context);
}
