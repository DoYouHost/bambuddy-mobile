import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../diagnostics/auth_probe.dart';

/// Secrets store. Abstraction so pure-Dart core (AuthService, interceptor)
/// is testable with mock without plugin.
abstract class CredentialsStore {
  Future<String?> readJwt();
  Future<void> writeJwt(String token);

  Future<String?> readApiKey();
  Future<void> writeApiKey(String key);

  /// Username+password stored ONLY on opt-in "remember me" —
  /// enable silent re-login after JWT expiry (24 h, no refresh token).
  Future<({String username, String password})?> readRememberedLogin();
  Future<void> writeRememberedLogin(String username, String password);

  /// Forgets the remembered login while keeping the rest of the profile's
  /// secrets — used when the server has definitively rejected them, so silent
  /// re-login stops replaying a password that can no longer work.
  Future<void> clearRememberedLogin();

  Future<void> clearAll();
}

/// Implementation using Android Keystore via flutter_secure_storage.
///
/// **Reads never delete and never throw.** The plugin's own answer to a failed
/// decrypt is to wipe the entry and carry on (`resetOnError`, true by default
/// since version 10), which turns a Keystore that is briefly unavailable — after
/// a reboot, on an OEM build having a bad day — into a session the user can
/// never get back. Here the data stays where it is and the read answers `null`,
/// the same as a key that was never written: the app asks for a sign-in, and if
/// the Keystore comes back the credential is still there to be read.
///
/// Writes are left to throw. A silently dropped write would leave someone
/// believing they are signed in while nothing was stored.
class SecureCredentialsStore implements CredentialsStore {
  SecureCredentialsStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: false),
          );

  static const _jwtKey = 'jwt';
  static const _apiKeyKey = 'api_key';
  static const _usernameKey = 'username';
  static const _passwordKey = 'password';

  final FlutterSecureStorage _storage;

  /// A read that cannot be decrypted is reported as absent, not as an error:
  /// every caller already handles "no credential", and none handles a throw.
  ///
  /// Retried once, because the failure this exists for is usually a Keystore
  /// that is not ready rather than a key that is gone — it happens seconds
  /// after a reboot, and by the second attempt it is over. Once, not a loop:
  /// a key that is really gone must not cost a retry budget on every read.
  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } on Object {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    try {
      return await _storage.read(key: key);
    } on Object catch (error) {
      AuthProbe.credentialUnreadable(key, error);
      return null;
    }
  }

  /// Deleting is best-effort for the same reason reading is: the caller is
  /// usually in the middle of telling the user to sign in again, and a throw
  /// from here would take that message with it.
  Future<void> _delete(String key) async {
    try {
      await _storage.delete(key: key);
    } on Object catch (error) {
      AuthProbe.credentialUnreadable(key, error);
    }
  }

  @override
  Future<String?> readJwt() => _read(_jwtKey);

  @override
  Future<void> writeJwt(String token) =>
      _storage.write(key: _jwtKey, value: token);

  @override
  Future<String?> readApiKey() => _read(_apiKeyKey);

  @override
  Future<void> writeApiKey(String key) =>
      _storage.write(key: _apiKeyKey, value: key);

  @override
  Future<({String username, String password})?> readRememberedLogin() async {
    final username = await _read(_usernameKey);
    // No second read when the first came up empty: on a failing Keystore that
    // is another wait and another warning in the log for an answer already
    // known.
    if (username == null) return null;
    final password = await _read(_passwordKey);
    if (password == null) return null;
    return (username: username, password: password);
  }

  @override
  Future<void> writeRememberedLogin(String username, String password) async {
    await _storage.write(key: _usernameKey, value: username);
    await _storage.write(key: _passwordKey, value: password);
  }

  @override
  Future<void> clearRememberedLogin() async {
    await _delete(_usernameKey);
    await _delete(_passwordKey);
  }

  @override
  Future<void> clearAll() => _storage.deleteAll();
}
