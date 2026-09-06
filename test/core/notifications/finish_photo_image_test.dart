import 'dart:io';
import 'dart:ui' as ui;

import 'package:bambuddy_mobile/core/notifications/finish_photo_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// PNG 64×32 — dość duży, by dało się go zmniejszyć, i bez wpływu na resztę
/// fixture'ów, bo nikt inny go nie czyta.
final _png = File('test/fixtures/finish_photo.png').readAsBytesSync();

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'zdjęcie szersze niż cel jest zmniejszane z zachowaniem proporcji',
    () async {
      final scaled = await FinishPhotoImage.scaled(_png, 32);

      final image = await _decode(scaled);
      expect(image.width, 32);
      expect(image.height, 16, reason: '64×32 → 32×16');
    },
  );

  test('zdjęcie węższe niż cel wraca bez przekodowania', () async {
    final scaled = await FinishPhotoImage.scaled(_png, 1024);

    expect(identical(scaled, _png), isTrue);
  });

  test('cel miniatury jest mniejszy od celu dużego kadru', () {
    // Dwa różne rozmiary mają sens tylko wtedy, gdy naprawdę się różnią:
    // miniatura jedzie w powiadomieniu obok pełnego kadru, oba przez most do
    // zegarka.
    expect(
      FinishPhotoImage.thumbnailWidth,
      lessThan(FinishPhotoImage.photoWidth),
    );
  });
}
