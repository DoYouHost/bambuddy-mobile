import 'package:bambuddy_mobile/core/auth/credentials_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Keystore having a bad day: reads throw the way the plugin reports one that
/// cannot decrypt, writes work.
class _UnreadableStorage extends FlutterSecureStorage {
  const _UnreadableStorage();

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw PlatformException(code: 'Storage decrypt failed');
}

void main() {
  group('SecureCredentialsStore when the store cannot read', () {
    final store = SecureCredentialsStore(const _UnreadableStorage());

    test('reports a token it cannot decrypt as absent', () async {
      // Every caller — the header builder, the WebSocket handshake, the token
      // refresh — handles "no credential". None handles a throw, and one
      // escaping here takes the screen that asked for it with it.
      expect(await store.readJwt(), isNull);
      expect(await store.readApiKey(), isNull);
      expect(await store.readRememberedLogin(), isNull);
    });
  });
}
