import 'dart:io';

import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/core/watch/wear_relay_engine.dart';
import 'package:bambuddy_mobile/core/watch/wear_rpc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the wake path's two ends together.
///
/// Waking the phone for the watch crosses the language boundary four times —
/// a prefs key, a method channel, an entry-point name and the ack's field
/// names — and every one of them is a bare string on both sides that only a
/// comment keeps in step. Nothing fails to compile when one of them drifts:
/// the phone simply stops waking up, which is the exact bug this whole path
/// was built to fix, and it would only show on a device.
///
/// Source-scanning for the same reason `action_tag_vocabulary_test` is: the
/// mismatch is a fact about the code, and there is no single place both
/// spellings pass through.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const nativeDir =
      'android/app/src/main/kotlin/page/codeberg/morganmlgman/bambuddy_mobile/wear';

  // Read at load time, so a renamed file fails the whole suite with this
  // sentence rather than one mirror quietly going unchecked. `expect` is not
  // available out here.
  String read(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError('$path is gone, and the mirror it holds is now '
          'unchecked — point this test at its new home');
    }
    return file.readAsStringSync();
  }

  final service = read('$nativeDir/WearRelayListenerService.kt');
  final host = read('$nativeDir/WearRelayEngineHost.kt');
  final codec = read('$nativeDir/WearRpcCodec.kt');
  final entryLibrary = read('lib/main.dart');

  test('the claim is written under the key the service reads', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await SettingsRepository(prefs).saveWearRelayClaim('1:nonce');

    // `shared_preferences` prefixes what it writes; the service reads the file
    // directly and so spells the prefix out.
    expect(service, contains('"flutter.${prefs.getKeys().single}"'),
        reason: 'the service would read an empty claim and wake a second '
            'responder alongside the one that is already listening');
  });

  test('the engine is launched on the channel it listens on', () {
    expect(host, contains('"$wearRelayChannel"'),
        reason: 'the forwarded request would reach no handler');
  });

  test('the entry point the host names is the one that exists', () {
    expect(host, contains('"wearRelayMain"'));
    expect(entryLibrary, contains("@pragma('vm:entry-point')"));
    expect(entryLibrary, contains('void wearRelayMain('),
        reason: 'it must stay in the app entry library — in one of its own it '
            'is tree-shaken out of the release snapshot');
  });

  test('the ack the service writes is the one the watch decodes', () {
    final ack = const WearRpcAck('correlation-id').encode();

    for (final field in ack.keys) {
      expect(codec, contains('"$field"'),
          reason: 'the watch would not find `$field` in the ack and would '
              'keep the deadline the wake needs it to extend');
    }
    // The two values that are protocol, not payload.
    expect(codec, contains('"${ack['kind']}"'));
    expect(codec, contains('"${ack['state']}"'));
    expect(codec, contains('VERSION = ${ack['v']}'));
  });
}
