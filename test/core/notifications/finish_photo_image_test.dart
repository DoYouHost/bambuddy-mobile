import 'dart:io';
import 'dart:ui' as ui;

import 'package:bambuddy_mobile/core/notifications/finish_photo_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// PNG 64×32 — large enough to be shrunk, and does not affect other fixtures
/// because no one else reads it.
final _png = File('test/fixtures/finish_photo.png').readAsBytesSync();

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('photo wider than target is scaled maintaining aspect ratio', () async {
    final scaled = await FinishPhotoImage.scaled(_png, 32);

    final image = await _decode(scaled);
    expect(image.width, 32);
    expect(image.height, 16, reason: '64×32 → 32×16');
  });

  test('photo narrower than target returns without recoding', () async {
    final scaled = await FinishPhotoImage.scaled(_png, 1024);

    expect(identical(scaled, _png), isTrue);
  });

  test('thumbnail target is smaller than full frame target', () {
    // Two different sizes only make sense if they actually differ: thumbnail
    // travels in notification alongside full frame, both across the bridge to
    // the watch.
    expect(
      FinishPhotoImage.thumbnailWidth,
      lessThan(FinishPhotoImage.photoWidth),
    );
  });
}
