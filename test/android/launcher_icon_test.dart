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

  /// Densities the generator writes a monochrome drawable for.
  const densities = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];

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

  test('every density has the drawable that layer points at', () {
    // The XML naming a drawable that is not on disk is not a test failure
    // anywhere else — it is an AAPT error in the middle of a build, and only
    // for whoever builds next. Generated files are easy to leave out of a
    // commit, which is exactly how that happens.
    for (final density in densities) {
      final drawable = File(
        'android/app/src/main/res/drawable-$density/ic_launcher_monochrome.png',
      );
      expect(
        drawable.existsSync(),
        isTrue,
        reason:
            '${drawable.path} is missing, so `flutter build apk` will fail on '
            'the drawable the themed icon points at. Run '
            '`dart run flutter_launcher_icons` and commit what it writes.',
      );
    }
  });
}
