import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
class SecureCredentialsStore implements CredentialsStore {
  SecureCredentialsStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _jwtKey = 'jwt';
  static const _apiKeyKey = 'api_key';
  static const _usernameKey = 'username';
  static const _passwordKey = 'password';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readJwt() => _storage.read(key: _jwtKey);

  @override
  Future<void> writeJwt(String token) =>
      _storage.write(key: _jwtKey, value: token);

  @override
  Future<String?> readApiKey() => _storage.read(key: _apiKeyKey);

  @override
  Future<void> writeApiKey(String key) =>
      _storage.write(key: _apiKeyKey, value: key);

  @override
  Future<({String username, String password})?> readRememberedLogin() async {
    final username = await _storage.read(key: _usernameKey);
    final password = await _storage.read(key: _passwordKey);
    if (username == null || password == null) return null;
    return (username: username, password: password);
  }

  @override
  Future<void> writeRememberedLogin(String username, String password) async {
    await _storage.write(key: _usernameKey, value: username);
    await _storage.write(key: _passwordKey, value: password);
  }

  @override
  Future<void> clearRememberedLogin() async {
    await _storage.delete(key: _usernameKey);
    await _storage.delete(key: _passwordKey);
  }

  @override
  Future<void> clearAll() => _storage.deleteAll();
}
