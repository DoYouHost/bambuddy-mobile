import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps the themed icon in the generated adaptive icon.
///
/// Android 13+ tints the `<monochrome>` layer to the user's wallpaper, and the
/// layer exists only because `adaptive_icon_monochrome` is set in
/// `pubspec.yaml`. It was a hand-written block once, which the next
/// `dart run flutter_launcher_icons` quietly removed — the loss then shows up
/// as "the themed icon stopped working" on somebody's phone weeks later, and
/// nothing in the build compares this file to what it should hold.
void main() {
  const adaptiveIcon =
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml';

  test('the adaptive icon still carries its themed layer', () {
    final file = File(adaptiveIcon);
    expect(file.existsSync(), isTrue, reason: '$adaptiveIcon is missing');

    expect(
      file.readAsStringSync(),
      contains('<monochrome>'),
      reason:
          'the themed icon layer is gone. Check that `adaptive_icon_monochrome`'
          ' is still set under `flutter_launcher_icons` in pubspec.yaml, then '
          'run `dart run flutter_launcher_icons` again.',
    );
  });
}
