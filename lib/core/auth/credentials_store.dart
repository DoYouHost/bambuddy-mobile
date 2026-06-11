import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Magazyn sekretów. Abstrakcja po to, by czysto-dartowy rdzeń
/// (AuthService, interceptor) dało się testować mockiem bez pluginu.
abstract class CredentialsStore {
  Future<String?> readJwt();
  Future<void> writeJwt(String token);

  Future<String?> readApiKey();
  Future<void> writeApiKey(String key);

  /// Login+hasło trzymane WYŁĄCZNIE przy opt-in „zapamiętaj mnie" —
  /// umożliwiają cichy re-login po wygaśnięciu JWT (24 h, brak refresh-tokena).
  Future<({String username, String password})?> readRememberedLogin();
  Future<void> writeRememberedLogin(String username, String password);

  Future<void> clearAll();
}

/// Implementacja na Android Keystore przez flutter_secure_storage.
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
  Future<void> clearAll() => _storage.deleteAll();
}
