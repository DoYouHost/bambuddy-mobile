import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps every notification on the status-bar glyph, not the launcher icon.
///
/// The foreground service reads the icon through a manifest meta-data name
/// spelled out in Dart; a typo there resolves to resource 0, and Android then
/// refuses `startForeground` ("no valid small icon") — the background monitor
/// dies on start, on the user's phone, with nothing in the build to say so.
void main() {
  const manifest = 'android/app/src/main/AndroidManifest.xml';
  const metaName =
      'page.codeberg.morganmlgman.bambuddy_mobile.NOTIFICATION_ICON';

  test('every density ships the glyph', () {
    for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      final png = File(
        'android/app/src/main/res/drawable-$d/ic_stat_notify.png',
      );
      expect(png.existsSync(), isTrue, reason: '$d is missing');
    }
  });

  test('the manifest names it under the key the service is started with', () {
    final xml = File(manifest).readAsStringSync();
    expect(
      RegExp(
        'android:name="${RegExp.escape(metaName)}"\\s+'
        'android:resource="@drawable/ic_stat_notify"',
      ).hasMatch(xml),
      isTrue,
    );
    expect(
      File('lib/core/notifications/background_monitor.dart').readAsStringSync(),
      contains("'$metaName'"),
    );
  });

  test('local notifications default to it too', () {
    final source = File(
      'lib/core/notifications/notification_service.dart',
    ).readAsStringSync();
    expect(
      source,
      contains("AndroidInitializationSettings('@drawable/ic_stat_notify')"),
    );
    expect(source, isNot(contains('@mipmap/ic_launcher')));
  });
}
