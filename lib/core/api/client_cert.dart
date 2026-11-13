import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../diagnostics/auth_probe.dart';
import '../settings/settings_repository.dart';

/// The certificate and private key the app shows a reverse proxy that asks for
/// one (mutual TLS, #65). A `.p12`/`.pfx` file, or a PEM file holding both the
/// certificate and its key; `dart:io` reads either from the same bytes.
///
/// The key is a secret: the whole file and its password live in
/// [ClientCertStore], never in SharedPreferences.
class ClientCert {
  const ClientCert({
    required this.name,
    required this.data,
    required this.password,
  });

  /// The file it came from, shown in settings.
  final String name;

  /// The file's bytes, base64.
  final String data;

  /// Empty for a file without one.
  final String password;

  /// A client bundle is a few KB; the cap keeps a video picked by mistake from
  /// being read on the UI isolate, and the watch's copy inside the Data Layer
  /// item.
  static const maxBytes = 64 * 1024;

  /// Whether [bytes] carry a PEM private key, plain or encrypted: such a file
  /// is meant as a client certificate even when it does not load as one.
  static bool holdsKey(List<int> bytes) =>
      latin1.decode(bytes).contains('PRIVATE KEY-----');

  /// PKCS#8 (`ENCRYPTED PRIVATE KEY`) and the older OpenSSL form.
  static final _encryptedKey = RegExp(
    r'ENCRYPTED PRIVATE KEY-----|Proc-Type: 4,ENCRYPTED',
  );

  /// Reads [bytes] with [password]. `wrongPassword` is set only when the file
  /// is a certificate bundle and the password is what failed, so the caller can
  /// ask for one; any other refusal comes back as both fields empty.
  static ({ClientCert? cert, bool wrongPassword}) parse(
    String name,
    List<int> bytes,
    String password,
  ) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      return (cert: null, wrongPassword: false);
    }
    try {
      _apply(SecurityContext(withTrustedRoots: false), bytes, password);
    } on TlsException catch (e) {
      return (cert: null, wrongPassword: '$e'.contains('INCORRECT_PASSWORD'));
    } on ArgumentError {
      // A PEM with a certificate and no key, or an encrypted PEM key read
      // with the wrong password: BoringSSL reports both as no key found.
      return (
        cert: null,
        wrongPassword: _encryptedKey.hasMatch(latin1.decode(bytes)),
      );
    }
    return (
      cert: ClientCert(
        name: name,
        data: base64.encode(bytes),
        password: password,
      ),
      wrongPassword: false,
    );
  }

  /// Makes [context] present this certificate.
  void applyTo(SecurityContext context) =>
      _apply(context, base64.decode(data), password);

  static void _apply(
    SecurityContext context,
    List<int> bytes,
    String password,
  ) => context
    ..useCertificateChainBytes(bytes, password: password)
    ..usePrivateKeyBytes(bytes, password: password);

  factory ClientCert.fromJson(Map<String, dynamic> json) => ClientCert(
    name: json['name'] as String,
    data: json['data'] as String,
    password: json['password'] as String,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'data': data,
    'password': password,
  };

  @override
  bool operator ==(Object other) =>
      other is ClientCert &&
      other.name == name &&
      other.data == data &&
      other.password == password;

  @override
  int get hashCode => Object.hash(name, data, password);
}

/// Secure storage for the one [ClientCert], in a namespace of its own: signing
/// out wipes the sign-in secrets with `deleteAll`, and the certificate belongs
/// to the proxy in front of the server, not to the account, as the CA does.
///
/// Reads answer null rather than throw and writes throw, as in
/// `SecureCredentialsStore`.
class ClientCertStore {
  ClientCertStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              resetOnError: false,
              storageNamespace: 'client_cert',
            ),
          );

  static const _key = 'client_cert';

  final FlutterSecureStorage _storage;

  Future<ClientCert?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      return ClientCert.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object catch (error) {
      AuthProbe.credentialUnreadable(_key, error);
      return null;
    }
  }

  Future<void> write(ClientCert? cert) => cert == null
      ? _storage.delete(key: _key)
      : _storage.write(key: _key, value: jsonEncode(cert.toJson()));
}

/// The stored certificate, read from secure storage only when preferences say
/// there is one: opening the namespace creates its Keystore key, which every
/// install without a certificate would otherwise pay for before its first frame.
Future<ClientCert?> loadClientCert(
  SettingsRepository settings, [
  ClientCertStore? store,
]) async =>
    settings.loadHasClientCert() ? (store ?? ClientCertStore()).read() : null;
