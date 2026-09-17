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

/// Fails the first read of each key and answers the second, the way a Keystore
/// that was not ready yet behaves a moment later.
class _FlakyStorage extends FlutterSecureStorage {
  _FlakyStorage(this.values);

  final Map<String, String> values;
  final failed = <String>{};
  var deletes = 0;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failed.add(key)) throw PlatformException(code: 'Keystore not ready');
    return values[key];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    deletes++;
    throw PlatformException(code: 'Keystore not ready');
  }
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

  test('a store that was only busy answers on the retry', () async {
    // The failure this tolerates is mostly a Keystore that is seconds behind a
    // reboot. Giving up on the first throw would end a session that was about
    // to work.
    final storage = _FlakyStorage({'jwt': 'token'});

    expect(await SecureCredentialsStore(storage).readJwt(), 'token');
  });

  test('forgetting a remembered login survives a store that refuses', () async {
    // The caller is in the middle of telling the user to sign in again; a throw
    // from here would take that message with it and surface in the interceptor.
    final storage = _FlakyStorage({});

    await expectLater(
      SecureCredentialsStore(storage).clearRememberedLogin(),
      completes,
    );
    expect(storage.deletes, 2);
  });
}
