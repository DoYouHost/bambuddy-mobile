import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the parts of the launcher icon that `flutter_launcher_icons` does not
/// write and happily overwrites.
///
/// The adaptive icon XML is generated once and then edited by hand: the
/// `<monochrome>` layer, which Android 13+ tints to the user's wallpaper, is
/// not something the package produces. Re-running the generator — a reasonable
/// thing to do after changing the source art — silently drops it, and the loss
/// shows up as "the themed icon stopped working" on somebody's phone weeks
/// later. Nothing else in the build compares the file to what it should hold.
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
          'the themed icon layer is gone — `dart run flutter_launcher_icons` '
          'rewrites this file without it. Put the <monochrome> block back '
          '(same inset drawable as <foreground>) rather than accepting the '
          'generated file.',
    );
  });
}
