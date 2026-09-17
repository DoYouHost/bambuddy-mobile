import 'package:bambuddy_mobile/core/auth/credentials_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// How `flutter_secure_storage` 9 wrote on Android: RSA PKCS#1 key wrapping and
/// AES-CBC data. Both are deprecated in 10 and gone in 11 — writing with them
/// here is the only way to produce, on a device, exactly what an install that
/// has not been updated yet is holding.
// ignore: deprecated_member_use
const _asVersion9 = AndroidOptions(
  // ignore: deprecated_member_use
  keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_PKCS1Padding,
  // ignore: deprecated_member_use
  storageCipherAlgorithm: StorageCipherAlgorithm.AES_CBC_PKCS7Padding,
  migrateOnAlgorithmChange: false,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const written = FlutterSecureStorage(aOptions: _asVersion9);
  const read = FlutterSecureStorage();

  // Both ends: a run killed halfway leaves keys behind, and the first test
  // would then read them instead of what it wrote.
  setUp(() => read.deleteAll());
  tearDown(() => read.deleteAll());

  testWidgets('reads back a token written by the old cipher', (tester) async {
    await written.write(key: 'jwt', value: 'token-from-version-9');

    // The default options are what the app uses, and their migration is what
    // decides whether an upgrade logs every existing install out.
    expect(await read.read(key: 'jwt'), 'token-from-version-9');
  });

  testWidgets('the credentials store survives the same upgrade', (
    tester,
  ) async {
    await written.write(key: 'jwt', value: 'jwt-9');
    await written.write(key: 'api_key', value: 'key-9');
    await written.write(key: 'username', value: 'morgan');
    await written.write(key: 'password', value: 'hunter2');

    final store = SecureCredentialsStore();

    expect(await store.readJwt(), 'jwt-9');
    expect(await store.readApiKey(), 'key-9');
    expect(await store.readRememberedLogin(), (
      username: 'morgan',
      password: 'hunter2',
    ));
  });

  testWidgets('writes and reads its own format', (tester) async {
    await read.write(key: 'jwt', value: 'token-now');

    expect(await read.read(key: 'jwt'), 'token-now');
    await read.delete(key: 'jwt');
    expect(await read.read(key: 'jwt'), isNull);
  });
}
