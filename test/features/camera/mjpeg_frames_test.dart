import 'dart:math';
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

    test(
      'joins an SOI whose FF ends one chunk and D8 starts the next',
      () async {
        final frames = await framesOf([
          [...boundary(), 0xFF],
          [0xD8, 0x05, 0x05, 0xFF, 0xD9],
        ]);

        expect(frames, [jpeg(0x05, size: 2)]);
      },
    );

    test('remembers a trailing FF across empty chunks', () async {
      final frames = await framesOf([
        [0xFF],
        [],
        [0xD8, 0x06, 0xFF],
        [],
        [0xD9],
      ]);

      expect(frames, [jpeg(0x06, size: 1)]);
    });

    test('ends a frame on FF D9 after fill bytes of FF', () async {
      // JPEG allows any number of FF fill bytes before a marker.
      final frames = await framesOf([
        [0xFF, 0xD8, 0x01, 0xFF, 0xFF, 0xFF, 0xD9],
      ]);

      expect(frames, [
        Uint8List.fromList([0xFF, 0xD8, 0x01, 0xFF, 0xFF, 0xFF, 0xD9]),
      ]);
    });

    test('ignores an SOI inside a frame that is still open', () async {
      final frames = await framesOf([
        [0xFF, 0xD8, 0x01, 0xFF, 0xD8, 0x02, 0xFF, 0xD9],
      ]);

      expect(frames, [
        Uint8List.fromList([0xFF, 0xD8, 0x01, 0xFF, 0xD8, 0x02, 0xFF, 0xD9]),
      ]);
    });

    test('cuts the same frames whatever the chunk boundaries are', () async {
      final stream = [
        ...boundary(),
        ...jpeg(0x11, size: 40),
        ...boundary(),
        0xFF, 0xFF, // Stray markers between parts must not start a frame.
        ...jpeg(0x12, size: 3),
        ...boundary(),
        ...jpeg(0xFF, size: 7), // A body of FF bytes, next to the EOI.
      ];
      final expected = [
        jpeg(0x11, size: 40),
        jpeg(0x12, size: 3),
        jpeg(0xFF, size: 7),
      ];
      expect(await framesOf([stream]), expected);
      expect(
        await framesOf([
          for (final b in stream) [b],
        ]),
        expected,
      );

      final random = Random(7);
      for (var run = 0; run < 200; run++) {
        final chunks = <List<int>>[];
        for (var at = 0; at < stream.length;) {
          final size = min(random.nextInt(9), stream.length - at);
          chunks.add(stream.sublist(at, at + size)); // Size 0 included.
          at += size;
        }
        expect(await framesOf(chunks), expected, reason: 'chunks: $chunks');
      }
    });

    test(
      'resynchronises on an SOI split across the chunk that hit the cap',
      () async {
        final frames = await framesOf([
          [0xFF, 0xD8, ...List.filled(64, 0x07), 0xFF], // Over the cap.
          [0xD8, 0x09, 0xFF, 0xD9],
        ], maxFrameBytes: 32);

        expect(frames, [jpeg(0x09, size: 1)]);
      },
    );

    test(
      'keeps up with a frame that never ends, in small chunks, up to the cap',
      () async {
        // Re-joining the whole buffer on every chunk made this ~64 GB of
        // copying (over 30 s); a linear pass is a few megabytes. A test
        // `timeout` cannot catch it — the stream never leaves the microtask
        // loop, so the timer fires only after the work is done.
        const chunkSize = 512;
        final filler = Uint8List(chunkSize)..fillRange(0, chunkSize, 0x07);
        final chunks = <List<int>>[
          [0xFF, 0xD8],
          for (var sent = 0; sent <= defaultMaxFrameBytes; sent += chunkSize)
            filler,
          jpeg(0x0A),
        ];

        final watch = Stopwatch()..start();
        expect(await framesOf(chunks), [jpeg(0x0A)]);
        expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      },
    );
  });
}
