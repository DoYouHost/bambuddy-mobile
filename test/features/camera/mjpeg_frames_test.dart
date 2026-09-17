import 'dart:typed_data';

import 'package:bambuddy_mobile/features/camera/mjpeg_frames.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal JPEG: SOI, a body of [size] bytes all equal to [fill], EOI.
Uint8List jpeg(int fill, {int size = 4}) =>
    Uint8List.fromList([0xFF, 0xD8, ...List.filled(size, fill), 0xFF, 0xD9]);

/// What a server puts between two frames of `multipart/x-mixed-replace`.
List<int> boundary() => '--frame\r\nContent-Type: image/jpeg\r\n\r\n'.codeUnits;

Future<List<Uint8List>> framesOf(
  List<List<int>> chunks, {
  int maxFrameBytes = defaultMaxFrameBytes,
}) => mjpegFrames(
  Stream.fromIterable(chunks),
  maxFrameBytes: maxFrameBytes,
).toList();

void main() {
  group('mjpegFrames', () {
    test(
      'cuts two frames out of one chunk and drops the boundary headers',
      () async {
        final frames = await framesOf([
          [...boundary(), ...jpeg(0x01), ...boundary(), ...jpeg(0x02)],
        ]);

        expect(frames, [jpeg(0x01), jpeg(0x02)]);
      },
    );

    test('joins a frame split across chunks, marker included', () async {
      // The last chunk boundary falls between the FF and the D9 of the EOI —
      // the case a scan that forgets the previous chunk's last byte misses.
      final frames = await framesOf([
        [0xFF, 0xD8, 0x01],
        [0x01, 0xFF],
        [0xD9, ...boundary()],
      ]);

      expect(frames, [jpeg(0x01, size: 2)]);
    });

    test('drops anything before the first SOI', () async {
      final frames = await framesOf([
        [0x00, 0xAA, 0xFF, 0x00, ...jpeg(0x03)],
      ]);

      expect(frames, [jpeg(0x03)]);
    });

    test('emits nothing while a frame has no EOI yet', () async {
      expect(
        await framesOf([
          [0xFF, 0xD8, 0x01, 0x02],
        ]),
        isEmpty,
      );
    });

    test('emits nothing for a stream that is not MJPEG at all', () async {
      expect(await framesOf(['<html>not a stream</html>'.codeUnits]), isEmpty);
    });

    test(
      'drops a frame that never ends and resynchronises on the next one',
      () async {
        final frames = await framesOf([
          [0xFF, 0xD8, ...List.filled(64, 0x07)], // Over the cap, no EOI.
          [...jpeg(0x08)],
        ], maxFrameBytes: 32);

        expect(frames, [jpeg(0x08)]);
      },
    );
  });
}
